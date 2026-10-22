#!/usr/bin/env python3
"""Fails if the copies of the vibescape guidance have drifted apart.

The app's MCP server hands the reference out from a string in Swift, and the
website's public MCP server hands it out from a string in JavaScript. An agent
talking to the app and an agent talking to the website should be told the same
thing, so there is one text and two copies of it — and this is what notices
when the copies stop matching.

The same job `check-preview-glsl.py` does for the shader prelude.

There is a second text now: the suggested style, which says how a vibescape
ought to move. It reaches an agent by three routes — the prompt a user copies
into an AI assistant, the MCP server's instructions, and the MCP reference —
and all three have to say the same thing. The style is one block in the app's
source, and this checks that every route carries it.

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
JS_STYLE = ROOT / "worker/mcp-style.js"
JS_MCP = ROOT / "worker/mcp.js"
MCP_SERVER = ROOT / "VisualiserMac/Sources/VisualiserMac/MCP/MCPServer.swift"
MCP_TOOLS = ROOT / "VisualiserMac/Sources/VisualiserMac/MCP/MCPTools.swift"


def swift_string(marker: str) -> str:
    """A Swift multi-line string constant, as it actually reads."""
    source = SWIFT.read_text()
    start = source.find(marker)
    if start < 0:
        sys.exit("could not find " + marker + " in " + str(SWIFT))
    start += len(marker)
    end = source.find('"""', start)
    if end < 0:
        sys.exit("the string in " + str(SWIFT) + " is not closed")

    raw = source[start:end]
    # A Swift multi-line string drops the indentation of the closing quotes,
    # and a trailing backslash continues the line: the next line joins on
    # directly, with no newline between them. Reading it any other way
    # would make the website's copy differ from the app's by a line break
    # here and there, which is exactly the drift this is meant to catch.
    lines = [line[4:] if line.startswith("    ") else line
             for line in raw.split("\n")]
    text = ""
    for number, line in enumerate(lines):
        if line.endswith("\\"):
            text += line[:-1]
        else:
            text += line
            if number < len(lines) - 1:
                text += "\n"
    # The first and last lines are the indentation of the opening and closing
    # quotes, not part of the text.
    return text.strip("\n")


def swift_reference() -> str:
    """The reference as the Swift multi-line string actually reads."""
    return swift_string("static let reference = \"\"\"")


def swift_style() -> str:
    """The shared style block as the Swift multi-line string actually reads."""
    return swift_string("static let style = \"\"\"")


def js_string(path: pathlib.Path, name: str) -> str:
    """A JavaScript string constant, as it actually reads."""
    source = path.read_text()
    # The string, then whatever it is concatenated with.
    match = re.search(name + r"\s*=\s*(\"(?:[^\"\\]|\\.)*\")", source, re.S)
    if not match:
        sys.exit("could not find " + name + " in " + str(path))
    return json.loads(match.group(1))


def js_reference() -> str:
    return js_string(JS, "VIBESCAPE_REFERENCE")


def js_style() -> str:
    return js_string(JS_STYLE, "VIBESCAPE_STYLE")


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
        "import { VIBESCAPE_STYLE } from \"./mcp-style.js\";\n"
        "\n"
        "export const VIBESCAPE_REFERENCE = %s + \"\\n\\n\" + VIBESCAPE_STYLE;\n" % json.dumps(text)
    )
    JS.write_text(body)
    print(f"wrote {JS} from the app's copy ({len(text)} characters)")


def write_style(text: str) -> None:
    """Copies the app's style block over the website's copy."""
    body = (
        "// How a vibescape ought to move.\n"
        "//\n"
        "// One text, reached by three routes: the prompt a user copies into an AI\n"
        "// assistant, the MCP server's instructions, and the MCP reference. The app\n"
        "// keeps it in CustomVibescapeGuide.style; this is the website's copy of it,\n"
        "// and `scripts/check-mcp-reference.py` fails the release if the two drift\n"
        "// apart.\n"
        "\n"
        "export const VIBESCAPE_STYLE = %s;\n" % json.dumps(text)
    )
    JS_STYLE.write_text(body)
    print(f"wrote {JS_STYLE} from the app's copy ({len(text)} characters)")


def main() -> int:
    swift = swift_reference()
    style = swift_style()

    if "--write" in sys.argv:
        write_js(swift)
        write_style(style)
        return 0

    problems = []

    js = js_reference()
    if swift != js:
        problems.append("the two copies of the vibescape reference have drifted apart")
        swift_lines = swift.split("\n")
        js_lines = js.split("\n")
        for number in range(max(len(swift_lines), len(js_lines))):
            a = swift_lines[number] if number < len(swift_lines) else "<missing>"
            b = js_lines[number] if number < len(js_lines) else "<missing>"
            if a != b:
                problems.append("  line %d:" % (number + 1))
                problems.append("    app:    " + a)
                problems.append("    server: " + b)
                break

    if js_style() != style:
        problems.append("the website's copy of the suggested style has drifted "
                        "from the app's")

    # The style has to reach an agent by every route, not just one.
    for path, needle, what in (
        (JS, "VIBESCAPE_STYLE", "the website's reference"),
        (JS_MCP, "VIBESCAPE_STYLE", "the website's MCP instructions"),
        (SWIFT, "withStyle(promptBody)", "the app's copy-paste prompt"),
        (SWIFT, "withStyle(reference)", "the app's MCP reference"),
        (MCP_SERVER, "CustomVibescapeGuide.style", "the app's MCP instructions"),
        (MCP_TOOLS, "CustomVibescapeGuide.fullReference", "the app's reference tool"),
    ):
        if needle not in path.read_text():
            problems.append("%s does not carry the suggested style" % what)

    if problems:
        for line in problems:
            print(line, file=sys.stderr)
        print("", file=sys.stderr)
        print("The app and the website should tell an agent the same thing, and", file=sys.stderr)
        print("every route to an agent should carry the style. The app's text is in", file=sys.stderr)
        print(str(SWIFT) + ", the website's is in " + str(JS) + " and " + str(JS_STYLE) + ".", file=sys.stderr)
        print("Copy the app's text over with:", file=sys.stderr)
        print("  python3 scripts/check-mcp-reference.py --write", file=sys.stderr)
        return 1

    print("the vibescape reference matches (%d characters)" % len(swift))
    print("the suggested style matches and reaches every route (%d characters)" % len(style))
    return 0


if __name__ == "__main__":
    sys.exit(main())
