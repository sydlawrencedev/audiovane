#!/usr/bin/env python3
"""Drive the Vibresia MCP server over stdio the way a real client would,
and save whatever pictures come back so they can be looked at.

This is the whole loop the tools exist for: describe or write a vibescape, get
a frame back, change a constant, get another one. If this passes, the loop
passes.
"""
import base64
import json
import os
import subprocess
import sys
import time

APP = os.path.join(os.path.dirname(__file__), "..", "build", "Vibresia.app",
                   "Contents", "MacOS", "Vibresia")
OUT = os.path.join(os.path.dirname(__file__), "..", "build", "preview-check")


class Client:
    def __init__(self):
        self.proc = subprocess.Popen(
            [APP, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.n = 0

    def raw(self, method, params=None, timeout=60):
        """A bare JSON-RPC method, for initialize and tools/list."""
        self.n += 1
        msg = {"jsonrpc": "2.0", "id": self.n, "method": method,
               "params": params or {}}
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError(f"{method}: server closed the connection")
        return json.loads(line)

    def call(self, tool, args=None, timeout=60):
        self.n += 1
        msg = {"jsonrpc": "2.0", "id": self.n,
               "method": "tools/call",
               "params": {"name": tool, "arguments": args or {}}}
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError(f"{tool}: server closed the connection")
        return json.loads(line)

    def close(self):
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        self.proc.wait(timeout=10)


def save_images(result, label):
    """Pull every PNG out of a tool result and write it next to the text."""
    os.makedirs(OUT, exist_ok=True)
    content = result.get("result", {}).get("content", [])
    written, texts = [], []
    for i, item in enumerate(content):
        if item.get("type") == "image":
            path = os.path.join(OUT, f"{label}-{i}.png")
            with open(path, "wb") as f:
                f.write(base64.b64decode(item["data"]))
            written.append((path, os.path.getsize(path)))
        elif item.get("type") == "text":
            texts.append(item["text"])
    return written, "\n".join(texts)


def check(condition, label, detail=""):
    mark = "ok  " if condition else "FAIL"
    print(f"  [{mark}] {label}" + (f" — {detail}" if detail and not condition else ""))
    return bool(condition)


results = []

# The server must never publish live uniform values itself. It builds a renderer
# as a side effect of SwiftUI constructing AppState, and a renderer in the
# server would write silence over the file the running app is publishing — so
# every snapshot would report a quiet room no matter what was playing.
LIVE_FILE = os.path.expanduser("~/Library/Application Support/Vibresia/uniforms.json")
app_running = bool(subprocess.run(
    ["pgrep", "-f", "Vibresia.app/Contents/MacOS/Vibresia"],
    capture_output=True).stdout.strip())
before = os.path.getmtime(LIVE_FILE) if os.path.exists(LIVE_FILE) else None

TUNNEL = """
vec3 render(vec2 p, float t) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float depth = 1.0 / (r * 2.4 + 0.12);
    float rings = sin(depth * 9.0 - uScroll * 3.0 + uBeats * 0.4);
    float grid = smoothstep(0.35, 0.0, abs(fract(a * 8.0) - 0.5) - 0.42);
    vec3 cyan = vec3(0.0, 1.0, 0.9);
    vec3 magenta = vec3(1.0, 0.0, 0.8);
    vec3 c = mix(cyan, magenta, 0.5 + 0.5 * rings);
    c += vec3(1.0) * pow(depth, 6.0) * 2.0;
    return c * (0.35 + grid * 0.5 + uBeatStrength * 0.3) * uActive;
}
"""

BARS = """
vec3 render(vec2 p, float t) {
    float x = p.x + 0.5;
    float b = bandAt(clamp(x, 0.0, 1.0));
    // Reads uBass too, so the uBass override has something to show.
    float v = b * 0.7 + uBass * 0.5;
    return vec3(v * v, v * 0.3, v * 0.6) * uActive;
}
"""

SPARSE = TUNNEL.replace("9.0", "1.5")

BROKEN = "vec3 render(vec2 p, float t) { return vec3(nope); }"
NO_MUSIC = "vec3 render(vec2 p, float t) { return vec3(0.2, 0.0, 0.3); }"

print("Driving the real MCP server over stdio\n")

print("1. handshake")
c2 = Client()
c2.raw("initialize", {"protocolVersion": "2024-11-05"})
r = c2.raw("tools/list")
names = [t["name"] for t in r.get("result", {}).get("tools", [])]
required = ["preview_vibescape", "validate_vibescape", "get_uniform_snapshot",
            "get_palette", "save_vibescape", "list_vibescapes", "get_vibescape",
            "preview_vibescape_animation", "diff_vibescape", "what_i_hear"]
results.append(check(all(n in names for n in required), "all tools advertised",
                     f"missing {set(required) - set(names)}"))

# -------------------------------------------------------------- 2. preview
print("\n2. preview_vibescape — one frame of a described visual")
t0 = time.time()
r = c2.call("preview_vibescape", {"code": TUNNEL})
elapsed = (time.time() - t0) * 1000
imgs, text = save_images(r, "tunnel")
results.append(check(len(imgs) == 1, "returns a PNG", text[:300]))
results.append(check(elapsed < 4000, "fast enough to iterate", f"{elapsed:.0f}ms"))
print("       " + text.replace("\n", "\n       ")[:400])

# The picture must not be flat — a shader that draws nothing still returns an
# image, so size alone proves nothing.
def png_is_flat(path):
    with open(path, "rb") as f:
        data = f.read()
    return len(set(data[-2000:])) < 12


results.append(check(not png_is_flat(imgs[0][0]), "the frame has real content"))

# ------------------------------------------ 3. the two-tool-call edit loop
print("\n3. the edit loop: render, change a constant, render again")
r = c2.call("preview_vibescape", {"code": SPARSE})
imgs2, _ = save_images(r, "sparse")
a = open(imgs[0][0], "rb").read()
b = open(imgs2[0][0], "rb").read()
results.append(check(a != b, "changing a constant changes the picture"))
print(f"       rings 9.0 -> {os.path.getsize(imgs[0][0])}B,  rings 1.5 -> {os.path.getsize(imgs2[0][0])}B")

# ------------------------------------------------------------ 4. multi-frame
print("\n4. preview_vibescape_animation — 8 frames over 4s")
t0 = time.time()
r = c2.call("preview_vibescape_animation", {"code": TUNNEL})
elapsed = (time.time() - t0) * 1000
imgs3, text3 = save_images(r, "strip")
results.append(check(len(imgs3) == 1, "one strip comes back"))
results.append(check(elapsed < 8000, "8 frames is not a wait", f"{elapsed:.0f}ms"))
print(f"       {elapsed:.0f}ms for 8 frames")
print("       " + text3.replace("\n", "\n       ")[:300])

# ------------------------------------------------------------- 5. uniforms
print("\n5. preview with uniforms set by hand")
r = c2.call("preview_vibescape", {"code": BARS, "options": {"width": 300, "height": 200,
                                                            "uniforms": {"uBass": 0.95, "uActive": 1.0}}})
imgs4, text4 = save_images(r, "bass-high")
results.append(check(len(imgs4) == 1, "renders with overrides"))
results.append(check("uBass" in text4, "reports which uniforms were overridden"))
print("       " + text4.replace("\n", "\n       ")[:300])

r = c2.call("preview_vibescape", {"code": BARS, "options": {"width": 300, "height": 200,
                                                            "uniforms": {"uBass": 0.0, "uBands": [0.0] * 96}}})
imgs5, _ = save_images(r, "bass-zero")
results.append(check(open(imgs4[0][0], "rb").read() != open(imgs5[0][0], "rb").read(),
                     "uBass 0.95 and uBass 0.0 look different"))

# And the reverse: silence has to be askable for, not just escaped from.
r = c2.call("preview_vibescape", {"code": BARS, "options": {"width": 200, "height": 150,
                                                            "uniforms": {"uActive": 0.0}}})
imgs8, _ = save_images(r, "silence")
results.append(check(os.path.getsize(imgs8[0][0]) < 9000,
                     "uActive 0 draws a resting vibescape, not a dead one",
                     f"{os.path.getsize(imgs8[0][0])}B"))

# ------------------------------------------------------------- 6. palette
print("\n6. get_palette")
r = c2.call("get_palette", {"name": "NEON"})
text = r["result"]["content"][0]["text"]
results.append(check("uPalette[0]" in text and "duotone" in text,
                     "returns source colours and tint strength"))
print("       " + text.replace("\n", "\n       ")[:300])

print("\n7. get_palette with no name")
r = c2.call("get_palette")
text = r["result"]["content"][0]["text"]
results.append(check(all(p in text for p in ["NEON", "EMBER", "TOXIC", "ABYSS", "MONO"]),
                     "lists every palette"))

# ------------------------------------------- 6c. the grade is the app's grade
# This is the whole reason previews are faithful: "I picked cyan and got muted
# teal" has to be reproducible here, and get_palette has to be able to explain
# it. Both are checked against real pixels rather than assumed.
print("\n7b. palette grade — the colours the app actually puts on screen")


def centre_rgb(grade, palette=None):
    """A flat field of a known colour; read back the middle pixel."""
    import struct, tempfile
    opts = {"width": 16, "height": 16, "grade": grade}
    if palette:
        opts["palette"] = palette
    r = c2.call("preview_vibescape",
                {"code": "vec3 render(vec2 p, float t) { return vec3(0.0, 1.0, 0.85); }",
                 "options": opts})
    raw = None
    for item in r["result"]["content"]:
        if item.get("type") == "image":
            raw = base64.b64decode(item["data"])
    assert raw, "no image came back"
    png, bmp = tempfile.mktemp(suffix=".png"), tempfile.mktemp(suffix=".bmp")
    with open(png, "wb") as f:
        f.write(raw)
    subprocess.run(["sips", "-s", "format", "bmp", png, "--out", bmp],
                   capture_output=True, check=True)
    d = open(bmp, "rb").read()
    off = struct.unpack("<I", d[10:14])[0]
    w = struct.unpack("<i", d[18:22])[0]
    h = struct.unpack("<i", d[22:26])[0]
    bpp = struct.unpack("<H", d[28:30])[0]
    stride = ((bpp * w + 31) // 32) * 4
    y = abs(h) // 2
    yy = y if h < 0 else abs(h) - 1 - y
    o = off + yy * stride + (w // 2) * (bpp // 8)
    os.unlink(png); os.unlink(bmp)
    return (d[o + 2], d[o + 1], d[o])   # BGR -> RGB


ungraded = centre_rgb(False)
results.append(check(ungraded == (0, 255, 217),
                     "grade:false returns the shader's own colour, untouched",
                     f"got rgb{ungraded}, wanted rgb(0, 255, 217)"))

graded = {pal: centre_rgb(True, pal) for pal in ["NEON", "EMBER", "MONO"]}
results.append(check(graded["NEON"] != ungraded,
                     "the palette really does shift the colour",
                     f"NEON gave the same colour back: rgb{graded['NEON']}"))
results.append(check(len(set(graded.values())) == len(graded),
                     "each palette shifts it differently",
                     f"got {graded}"))
print(f"       cyan  rgb{ungraded}")
for pal, rgb in graded.items():
    print(f"       {pal:<6} rgb{rgb}")

# ------------------------------------------------------------ 8. validate
print("\n8. validate_vibescape")
r = c2.call("validate_vibescape", {"code": TUNNEL})
text = r["result"]["content"][0]["text"]
results.append(check("compiles" in text.lower(), "a good one passes"))

r = c2.call("validate_vibescape", {"code": BROKEN})
text = r["result"]["content"][0]["text"]
results.append(check(r["result"].get("isError") and "nope" in text,
                     "a broken one says what the driver said"))
print("       " + text.replace("\n", "\n       ")[:300])

r = c2.call("validate_vibescape", {"code": NO_MUSIC})
text = r["result"]["content"][0]["text"]
results.append(check("never reads the music" in text,
                     "warns about a vibescape that ignores the music"))
print("       " + text.replace("\n", "\n       ")[:300])

# ------------------------------------------------------ 9. broken preview
print("\n9. broken code still gets a real error, not a blank picture")
r = c2.call("preview_vibescape", {"code": BROKEN})
text = r["result"].get("content", [{}])[0].get("text", "")
results.append(check(r["result"].get("isError"), "returns isError"))

# ------------------------------------------------------------- 10. gallery
print("\n10. list_vibescapes — with thumbnails")
t0 = time.time()
r = c2.call("list_vibescapes")
elapsed = (time.time() - t0) * 1000
content = r["result"]["content"]
pics = [c for c in content if c.get("type") == "image"]
results.append(check(len(pics) >= 15, "every vibescape has a thumbnail", f"{len(pics)} images"))
print(f"       {len(pics)} thumbnails in {elapsed:.0f}ms")

# ------------------------------------------------------------- 11. save
print("\n11. save_vibescape — refuses broken code, previews what it saves")
r = c2.call("save_vibescape", {"name": "zz-check-broken", "code": BROKEN})
results.append(check(r["result"].get("isError"), "does not save broken code"))

r = c2.call("save_vibescape", {"name": "zz-preview-check", "code": TUNNEL,
                              "description": "a tunnel for the test", "palette": "NEON",
                              "audio_targets": "bass and the beat"})
imgs6, text6 = save_images(r, "saved")
results.append(check(len(imgs6) == 1, "shows what it saved"))
results.append(check("zz-preview-check" in text6, "reports the id"))
print("       " + text6.replace("\n", "\n       ")[:400])

r = c2.call("list_vibescapes")
names_in_list = r["result"]["content"][-1]["text"]
results.append(check("zz-preview-check" in names_in_list, "it's in the list afterwards"))

# -------------------------------------------------------------- 12. diff
print("\n12. diff_vibescape — two versions, one picture")
r = c2.call("diff_vibescape", {"code_a": SPARSE, "code_b": TUNNEL,
                              "label_a": "1.5", "label_b": "9.0"})
imgs7, text7 = save_images(r, "diff")
results.append(check(len(imgs7) == 1, "returns one side-by-side picture"))
print("       " + text7.replace("\n", "\n       ")[:300])

# tidy up after ourselves
c2.call("delete_vibescape", {"id": "zz-preview-check"})
# ------------------------------------------- 13. it doesn't fake a live app
print("\n13. honesty about where the numbers came from")
r = c2.call("preview_vibescape", {"code": TUNNEL, "options": {"width": 64, "height": 64}})
text = r["result"]["content"][-1]["text"]

if app_running:
    # Reading "the music playing now" can only come from the file the app
    # writes, so this proves the server is reading the app and not inventing a
    # reading of its own.
    results.append(check("the music playing now" in text,
                         "says the numbers come from the running app",
                         text[:200]))
else:
    # The decisive test for the other direction. With no app running there is
    # nothing legitimate to write, so any write here is the server faking it —
    # and it would mean every snapshot reports silence while music plays.
    after = os.path.getmtime(LIVE_FILE) if os.path.exists(LIVE_FILE) else None
    results.append(check(after == before,
                         "never publishes live values of its own",
                         f"mtime moved from {before} to {after}"))
    results.append(check("stand-in values" in text,
                         "says stand-in values when no app is running",
                         text[:200]))

c2.close()

print("\n" + "=" * 60)
passed = sum(1 for r in results if r)
print(f"{passed}/{len(results)} checks passed")
print(f"pictures in {os.path.abspath(OUT)}")
sys.exit(0 if passed == len(results) else 1)
