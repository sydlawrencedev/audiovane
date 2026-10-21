import Foundation

/// Strips comments and redundant whitespace out of a vibescape's GLSL.
///
/// Only used when someone sharing asks for a shorter link, because it is not
/// lossless in the way that matters here: the app saves whatever arrives,
/// verbatim, so the recipient's copy is whatever this leaves behind. Compression
/// gets most of the length back with the code intact; this is for the case where
/// a link still won't fit in whatever it's being pasted into.
///
/// GLSL has no string literals, so "the next `//` starts a comment" is safe
/// without tracking quotes the way a C-family minifier has to. Preprocessor
/// lines are left alone: `#version` has to stay on the first line and macros
/// are line-oriented.
enum GLSLMinifier {
    static func minify(_ source: String) -> String {
        var out = ""
        out.reserveCapacity(source.count)
        var i = source.utf8.startIndex
        let end = source.utf8.endIndex

        // Step 1: drop comments, keeping newlines that follow them so that
        // `#`-directives still end up on their own lines.
        var noComments = ""
        while i < end {
            let c = source.utf8[i]
            let n = source.utf8.index(after: i)
            if c == UInt8(ascii: "/"), n < end, source.utf8[n] == UInt8(ascii: "/") {
                while i < end, source.utf8[i] != UInt8(ascii: "\n") {
                    i = source.utf8.index(after: i)
                }
            } else if c == UInt8(ascii: "/"), n < end, source.utf8[n] == UInt8(ascii: "*") {
                i = source.utf8.index(after: n)
                while i < end {
                    if source.utf8[i] == UInt8(ascii: "*"), source.utf8.index(after: i) < end,
                       source.utf8[source.utf8.index(after: i)] == UInt8(ascii: "/") {
                        i = source.utf8.index(i, offsetBy: 2)
                        break
                    }
                    if source.utf8[i] == UInt8(ascii: "\n") { noComments.append("\n") }
                    i = source.utf8.index(after: i)
                }
            } else {
                noComments.append(Character(UnicodeScalar(c)))
                i = n
            }
        }
// Step 2: collapse whitespace, and pull space out from around
        // punctuation that never needs it. The character classes are the two
        // that matter in GLSL: an identifier-ish byte next to another one needs
        // its space kept (`return x` is not `returnx`), everything else can
        // close up.
        func isWordByte(_ b: UInt8) -> Bool {
            (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
                || (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
                || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
                || b == UInt8(ascii: "_")
        }

        var result = ""
        var pendingSpace = false
        var last: UInt8 = 0
        // A preprocessor directive is line-oriented: everything up to the next
        // newline belongs to it. `#define SPEED 3.0` followed by real code has
        // to keep its line break, or the code gets absorbed into the macro and
        // the shader stops compiling. `#version` can't reach here — the
        // validator rejects it before it is ever saved — but `#define` can,
        // and people write them.
        var inDirective = false
        var atLineStart = true

        for b in noComments.utf8 {
            if b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") {
                // A real line break. This is what ends a preprocessor
                // directive — and only a real break does, because the spaces
                // inside `#define SPEED 3.0` are not line ends.
                if inDirective {
                    result.append("\n")
                    inDirective = false
                }
                pendingSpace = false
                last = 0
                atLineStart = true
                continue
            }
            if b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") {
                // `last` is deliberately left alone here. It is the byte before
                // the whitespace, and it is the whole basis of the word-boundary
                // test below; clearing it on every space is what turns `vec3
                // render` into `vec3render`.
                pendingSpace = true
                continue
            }
            if b == UInt8(ascii: "#") && atLineStart {
                if !result.isEmpty, result.last != "\n" { result.append("\n") }
                inDirective = true
                pendingSpace = false
                last = 0
            } else if pendingSpace {
                pendingSpace = false
                if !result.isEmpty, result.last != "\n",
                   isWordByte(last) && isWordByte(b) {
                    result.append(" ")
                }
            }
            result.append(Character(UnicodeScalar(b)))
            last = b
            atLineStart = false
        }
        // A file ending mid-directive still needs its break closed off.
        if inDirective { result.append("\n") }
        return result
    }
}