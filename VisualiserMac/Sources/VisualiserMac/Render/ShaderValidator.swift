import Foundation

/// What went wrong with a custom vibscape, in words a person can act on.
///
/// The OpenGL compiler's messages are precise and close to unreadable: they
/// name internal symbols and point at lines in a program the user has never
/// seen, because most of it is a prelude the app wrote for them. So the raw
/// log is kept, but never shown on its own — every case that can be
/// recognised gets a sentence about what to change instead.
struct ShaderProblem: Error {
    enum Kind {
        /// Nothing recognisable in the shape of the code.
        case missingRenderFunction
        case wroteMainInstead
        case hasVersionDirective
        case empty
        /// A real compile or link failure.
        case compileFailed
        /// The graphics system wasn't ready yet. Not the vibscape's fault, and
        /// not worth telling anybody about — it'll be tried again.
        case notReady
    }

    var kind: Kind
    /// What to do about it, in one sentence.
    var message: String
    /// The line in the user's own code to look at, when we can tell.
    var line: Int?
    /// The driver's own words. Kept for the "technical details" disclosure,
    /// never the first thing shown.
    var driverLog: String = ""

    var title: String {
        switch kind {
        case .missingRenderFunction: return "There's no vibscape in there yet"
        case .wroteMainInstead: return "This is written the wrong way round"
        case .hasVersionDirective: return "Remove the #version line"
        case .empty: return "There's nothing to try"
        case .compileFailed: return line == nil ? "That didn't compile" : "Line \(line!) needs a fix"
        case .notReady: return "Not ready yet"
        }
    }
}

/// Checks a candidate vibscape before it's saved, and explains the failure.
enum ShaderValidator {

    /// The function every vibscape must define. Matched loosely enough to allow
    /// a line break or a space between the return type and the name.
    private static let renderSignature = ##"vec3\s+render\s*\(\s*vec2\s+\w+\s*,\s*float\s+\w+\s*\)"##

    enum ShapeCheck {
        case ok
        case failed(ShaderProblem)
    }

    /// Cheap checks that need no GPU: run these first so an obviously wrong
    /// paste gets an obvious answer without waiting on a compile.
    static func checkShape(_ source: String) -> ShapeCheck {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failed(ShaderProblem(
                kind: .empty,
                message: "There's nothing in the box yet. Paste in a vibscape, or start from the example."))
        }

        // The user pasted a whole standalone shader rather than a vibscape body.
        // The prelude already supplies the version line, the uniforms and
        // main(), so all of it has to come out.
        if trimmed.contains("#version") {
            return .failed(ShaderProblem(
                kind: .hasVersionDirective,
                message: "Delete the line starting with #version. Vibresia already says which version of graphics it uses — leaving yours in causes an error."))
        }
        if trimmed.contains("#include") {
            return .failed(ShaderProblem(
                kind: .hasVersionDirective,
                message: "Delete any line starting with #include. Vibresia already provides everything a vibscape needs."))
        }
        // main() is the standard entry point, so a first attempt very often
        // writes one. It's the single most likely mistake, so it's worth its
        // own message rather than a compile error about a redefined symbol.
        if trimmed.range(of: ##"void\s+main\s*\("##, options: .regularExpression) != nil {
            return .failed(ShaderProblem(
                kind: .wroteMainInstead,
                message: "Vibscapes use a function called render, not main. Change \"void main()\" to \"vec3 render(vec2 p, float t)\", and at the end return your colour instead of assigning to fragColor."))
        }

        let withoutComments = stripComments(trimmed)
        if withoutComments.range(of: renderSignature, options: .regularExpression) == nil {
            // Distinguish "no function at all" from "close but misspelled" —
            // a typo'd name otherwise produces a baffling "undeclared" error.
            if withoutComments.range(of: ##"render\s*\("##, options: .regularExpression) != nil {
                return .failed(ShaderProblem(
                    kind: .missingRenderFunction,
                    message: "Found something called render, but not in the shape Vibresia expects. It needs to be exactly: vec3 render(vec2 p, float t)" ))
            }
            return .failed(ShaderProblem(
                kind: .missingRenderFunction,
                message: "A vibscape needs a function called render that returns a colour. Copy the example above to start from a working one."))
        }
        return .ok
    }

    static func stripComments(_ s: String) -> String {
        var out = ""
        var inBlock = false
        var chars = Array(s)
        var i = 0
        while i < chars.count {
            if inBlock {
                if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                    inBlock = false; chars[i] = " "; chars[i + 1] = " "; i += 2; continue
                }
                chars[i] = " "; i += 1; continue
            }
            if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count && chars[i] != "\n" { chars[i] = " "; i += 1 }
                continue
            }
            if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                inBlock = true; chars[i] = " "; chars[i + 1] = " "; i += 2; continue
            }
            i += 1
        }
        out = String(chars)
        return out
    }

    /// Line number inside the user's code for an error the driver reported.
    ///
    /// The compiler is given `prelude + body`, so its line numbers count the
    /// prelude. Subtracting it puts the number back on the text the user can
    /// actually see and edit.
    static func userLine(fromDriverLine driverLine: Int, preludeLines: Int) -> Int {
        let n = driverLine - preludeLines
        return n < 1 ? 1 : n
    }

    /// Turn a driver info-log into the closest thing we can say in English.
    ///
    /// The log is driver- and error-specific and has no stable grammar, so
    /// this matches on the shapes that turn up most and falls back to showing
    /// the first meaningful line verbatim rather than inventing a diagnosis.
    static func explain(_ log: String, preludeLines: Int) -> ShaderProblem {
        let lowered = log.lowercased()
        let lines = log.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let first = lines.first ?? log

        var line: Int?

        // Pick up "ERROR: 0:123: '...' : message" or "0(123) : error ..."
        // Capture group 1 is the driver line number.
        if let m = log.firstMatch(of: #"(\d+)\s*[:(]\s*(\d+)\s*\)?\s*:"#) {
            line = userLine(fromDriverLine: Int(m.groups[1]) ?? 0, preludeLines: preludeLines)
        }

        func problem(_ message: String) -> ShaderProblem {
            ShaderProblem(kind: .compileFailed, message: message, line: line, driverLog: log)
        }

        // The two mistakes that account for most failed pastes.
        if lowered.contains("redefinition") || lowered.contains("already defined") {
            let name = quotedName(in: first) ?? "Something"
            if name == "main" {
                return problem("You have a main() function, but Vibresia supplies its own. Delete yours and use render() instead.")
            }
            return problem("You declared \(name), which Vibresia already provides. Remove your line declaring it — using the existing one is usually all that's needed.")
        }
        if lowered.contains("undeclared identifier") || lowered.contains("unknown identifier") {
            let name = quotedName(in: first) ?? "that name"
            // "render" is the name we're asking for, so the driver saying it
            // doesn't exist means the signature is wrong, not the name.
            if name == "render" {
                return problem("Your render function isn't quite the right shape. It needs to be exactly: vec3 render(vec2 p, float t) — returning a vec3, taking a vec2 and a float, in that order.")
            }
            if let known = knownUniformName(name) {
                return problem("\(name) isn't a thing Vibresia provides. The closest is \(known) — check the spelling.")
            }
            return problem("Vibresia doesn't recognise \(name). If it's a uniform or helper you expected, check the spelling against the list below. If it's your own variable, make sure you declare it before you use it.")
        }
        if lowered.contains("no matching overloaded function") {
            return problem("A function was called with the wrong number or type of arguments. Check any brackets you've just edited.")
        }
        if lowered.contains("expected") && lowered.contains(";" ) {
            return problem("Something is missing a semicolon, or a bracket doesn't close. Check the line above this one too.")
        }
        if lowered.contains("syntax error") {
            return problem("There's a typo or a missing bracket on this line. Check that every { has a matching }.")
        }
        if lowered.contains("undeclared") || lowered.contains("undefined") {
            return problem("Something in this line isn't defined yet — a variable used before it's created, most likely.")
        }
        if lowered.contains("fragment") && lowered.contains("out") {
            return problem("The shader didn't produce an output. Make sure render() returns a colour.")
        }
        // Nothing matched: show the driver's first real line rather than
        // pretending to understand it.
        return ShaderProblem(
            kind: .compileFailed,
            message: "This didn't compile. The graphics system said:",
            line: line,
            driverLog: first)
    }

    private static func quotedName(in line: String) -> String? {
        guard let m = line.firstMatch(of: #"['"`]([^'"`]+)['"`]"#) else { return nil }
        return m.groups[0]
    }

    /// The nearest real name, for "did you mean". Only offers uniforms that
    /// actually exist, so it can't suggest something that then also fails.
    private static func knownUniformName(_ name: String) -> String? {
        let real = ["uTime", "uBass", "uMid", "uTreble", "uBeat", "uBeatStrength", "uLevel",
                    "uResolution", "uIdle", "uBands", "uActive", "uBeats", "uScroll",
                    "uClock", "uLevelSmooth", "uBassSmooth", "uPalette"]
        guard !real.contains(name) else { return nil }
        // Cheap edit distance: close enough to suggest, far enough to be sure.
        if let best = real.min(by: { editDistance($0, name) < editDistance($1, name) }),
           editDistance(best, name) <= max(2, name.count / 3) {
            return best
        }
        return nil
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}

private extension String {
    /// First regex match. `groups` holds the numbered capture groups, so
    /// `groups[0]` is capture group 1. Avoids `firstMatch(of:)` being
    /// unavailable on older toolchains.
    func firstMatch(of pattern: String) -> (groups: [String], range: Range<String.Index>)? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)),
              let r = Range(m.range, in: self) else { return nil }
        var groups: [String] = []
        if m.numberOfRanges > 1 {
            for i in 1..<m.numberOfRanges {
                if let gr = Range(m.range(at: i), in: self) {
                    groups.append(String(self[gr]))
                } else {
                    groups.append("")
                }
            }
        } else {
            groups.append(String(self[r]))
        }
        return (groups, r)
    }
}
