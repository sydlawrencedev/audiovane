#!/usr/bin/env python3
"""Fails if the two copies of the vibescape reference have drifted apart.

The app's MCP server hands the reference out from a string in Swift, and the
website's public MCP server hands it out from a string in JavaScript. An agent
talking to the app and an agent talking to the website should be told the
same thing, so there is one text and two copies of it — and this is what
notices when the copies stop matching.

The same job `check-preview-glsl.py` does for the shader prelude.

    python3 scripts/check-mcp-reference.py
    python3 scripts/check-mcp-reference.py --write   # copy the app's text over
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "VisualiserMac/Sources/VisualiserMac/Render/Vibescapes.swift"
JS = ROOT / "worker/mcp-reference.js"


def swift_reference() -> str:
    """The reference as the Swift multi-line string actually reads."""
    source = SWIFT.read_text()
    marker = "static let reference = \"\"\""
    start = source.find(marker)
    if start < 0:
        sys.exit("could not find the reference in " + str(SWIFT))
    start += len(marker)
    end = source.find('"""', start)
    if end < 0:
        sys.exit("the reference in " + str(SWIFT) + " is not closed")

    raw = source[start:end]
    # In a Swift multi-line string a trailing backslash continues the line and
    # the next line's indentation is stripped.
    lines = []
    for line in raw.split("\n"):
        if line.endswith("\\"):
            lines.append(line[:-1])
        else:
            lines.append(line)
    text = "\n".join(lines)
    # The first and last lines are the indentation of the opening and closing
    # quotes, not part of the text.
    text = text.strip("\n")
    return "\n".join(line[4:] if line.startswith("    ") else line
                     for line in text.split("\n"))


def js_reference() -> str:
    source = JS.read_text()
    match = re.search(r"VIBESCAPE_REFERENCE\s*=\s*(\".*\")\s*;", source, re.S)
    if not match:
        sys.exit("could not find VIBESCAPE_REFERENCE in " + str(JS))
    return json.loads(match.group(1))


def write_js(text: str) -> None:
    """Copies the app's text over the website's copy."""
    body = (
        "// The uniforms and helpers a custom vibescape can use.\n"
        "//\n"
        "// The same text the app's own MCP server hands out, so an agent talking to\n"
        "// the app and an agent talking to the website are told the same thing.\n"
        "// `scripts/check-mcp-reference.py` fails the release if the two drift apart —\n"
        "// the same guard `check-preview-glsl.py` gives the shader prelude.\n"
        "\n"
        "export const VIBESCAPE_REFERENCE = %s;\n" % json.dumps(text)
    )
    JS.write_text(body)
    print(f"wrote {JS} from the app's copy ({len(text)} characters)")


def main() -> int:
    swift = swift_reference()
    js = js_reference()

    if "--write" in sys.argv:
        write_js(swift)
        return 0

    if swift == js:
        print(f"the vibescape reference matches ({len(swift)} characters)")
        return 0

    print("the two copies of the vibescape reference have drifted apart:", file=sys.stderr)
    swift_lines = swift.split("\n")
    js_lines = js.split("\n")
    for number in range(max(len(swift_lines), len(js_lines))):
        a = swift_lines[number] if number < len(swift_lines) else "<missing>"
        b = js_lines[number] if number < len(js_lines) else "<missing>"
        if a != b:
            print(f"  line {number + 1}:", file=sys.stderr)
            print(f"    app:    {a}", file=sys.stderr)
            print(f"    server: {b}", file=sys.stderr)
            break
    print("", file=sys.stderr)
    print("The app and the website should tell an agent the same thing. Copy the", file=sys.stderr)
    print("text from one to the other — the app's is in " + str(SWIFT), file=sys.stderr)
    print("and the website's is in " + str(JS) + ".", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
