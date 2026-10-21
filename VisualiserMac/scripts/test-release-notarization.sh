#!/bin/bash
# Simulates release.sh's notarization control flow with the real script's
# logic, using stubs for the parts that need a real Apple identity.
#
# What it checks:
#   1. ad-hoc build + no identity  -> release proceeds, warns, exit 0
#   2. Developer ID + notarize ok   -> release proceeds, exit 0
#   3. Developer ID + notarize fails-> release aborts, exit 1
#   4. Developer ID + notarize "succeeds" but no valid ticket -> aborts, exit 1
#
# Usage: ./scripts/test-release-notarization.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
release_sh="$here/../release.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# The site checks release.sh runs before it builds anything. They need the
# real repository, so in a sandbox they are stubs that pass.
mkdir -p "$WORK/scripts"
for s in check-vibescapes.sh check-posthog.sh check-no-webhook-leak.sh; do
    printf '#!/bin/bash\necho "==> [stub] %s"\n' "$s" > "$WORK/scripts/$s"
    chmod +x "$WORK/scripts/$s"
done
printf '#!/bin/bash\nexit 0\n' > "$WORK/scripts/check-preview-glsl.py"
chmod +x "$WORK/scripts/check-preview-glsl.py"
# This one is called as `python3 ../scripts/inject-chrome.py`, so it has to be
# a Python file rather than a shell script with a shebang.
printf 'import sys\nsys.exit(0)\n' > "$WORK/scripts/inject-chrome.py"

check() { # name expected actual
    if [ "$2" = "$3" ]; then
        echo "  ok    $1 (exit $3)"
        pass=$((pass + 1))
    else
        echo "  FAIL  $1 (expected exit $2, got $3)"
        echo "  --- output ---"
        echo "$out" | sed 's/^/  | /' | tail -12
        fail=$((fail + 1))
    fi
}

# Build a sandbox that mirrors release.sh's structure, with the real script
# copied in and its external commands stubbed.
make_sandbox() { # $1 = sandbox dir, $2 = notarize exit code, $3 = "devid" or "adhoc", $4 = staple valid or not
    local sb="$1"
    mkdir -p "$sb/scripts" "$sb/build" "$sb/dist"

    # The stub notarize.sh either fails or "succeeds".
    cat > "$sb/scripts/notarize.sh" <<EOF
#!/bin/bash
echo "==> [stub] notarize.sh running"
exit $2
EOF
    chmod +x "$sb/scripts/notarize.sh"

    # A bundle-shaped thing for codesign to look at.
    mkdir -p "$sb/build/Vibresia.app/Contents/MacOS"
    : > "$sb/build/Vibresia.app/Contents/MacOS/Vibresia"

    # Stubs on PATH: codesign reports the identity, xcrun validates or not,
    # gh does nothing, version.sh and build-app.sh are no-ops.
    mkdir -p "$sb/bin"
    if [ "$3" = "devid" ]; then
        cat > "$sb/bin/codesign" <<'EOF'
#!/bin/bash
# The verification of the unpacked zip is a separate concern, tested below;
# here it just has to succeed.
case " $* " in
  *" --verify "*) exit 0 ;;
esac
# The authority line comes first and there is a lot of output after it,
# which is what real codesign does. A reader that stops at the first match
# closes the pipe, codesign dies of SIGPIPE, and with pipefail on the
# whole thing reads as a failure — so a checker that pipes into `grep -q`
# would report "not signed with an identity" for an app that is.
echo "Authority=Developer ID Application: Test Org (ABCDE12345)"
i=0
while [ $i -lt 5000 ]; do
    echo "Identifier=com.example.app"
    i=$((i + 1))
done
EOF
    else
        cat > "$sb/bin/codesign" <<'EOF'
#!/bin/bash
case " $* " in
  *" --verify "*) exit 0 ;;
esac
echo "Signature=adhoc"
i=0
while [ $i -lt 5000 ]; do
    echo "Identifier=com.example.app"
    i=$((i + 1))
done
EOF
    fi
    chmod +x "$sb/bin/codesign"

    # The release unpacks its own zip and checks the result. The stub
    # unpacks to a directory with no AppleDouble files in it, which is what
    # a clean zip produces.
    cat > "$sb/bin/unzip" <<'EOF'
#!/bin/bash
dest=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-d" ]; then dest="$a"; fi
  prev="$a"
done
[ -n "$dest" ] && mkdir -p "$dest/Vibresia.app"
exit 0
EOF
    chmod +x "$sb/bin/unzip"

    if [ "$4" = "valid" ]; then
        cat > "$sb/bin/xcrun" <<'EOF'
#!/bin/bash
exit 0
EOF
    else
        cat > "$sb/bin/xcrun" <<'EOF'
#!/bin/bash
exit 1
EOF
    fi
    chmod +x "$sb/bin/xcrun"

    # `gh release view` is how release.sh asks whether the tag is already
    # taken: it must fail, or the script thinks the release exists and stops.
    # `gh release create` is the publish step, and should succeed.
    cat > "$sb/bin/gh" <<'EOF'
#!/bin/bash
if [ "$1" = "release" ] && [ "$2" = "view" ]; then
    exit 1
fi
echo "==> [stub] gh $*"
EOF
    chmod +x "$sb/bin/gh"

    cat > "$sb/version.sh" <<'EOF'
#!/bin/bash
echo "0.10.2126"
EOF
    chmod +x "$sb/version.sh"

    cat > "$sb/build-app.sh" <<'EOF'
#!/bin/bash
echo "==> [stub] build-app.sh $*"
EOF
    chmod +x "$sb/build-app.sh"

    # The real release.sh, with only the git-version line's dependency on
    # `git` left alone (it is inside the repo, so git works).
    cp "$release_sh" "$sb/release.sh"
    chmod +x "$sb/release.sh"
}

echo "release.sh notarization control flow"
echo

echo "1. ad-hoc build, no identity, no ticket -> proceeds with a warning"
make_sandbox "$WORK/a" 0 adhoc invalid
out="$(cd "$WORK/a" && PATH="$WORK/a/bin:$PATH" ./release.sh 2>&1)"; rc=$?
check "proceeds" 0 "$rc"
echo "$out" | grep -q "NOT notarized" \
    && { echo "  ok    warns that it is not notarized"; pass=$((pass+1)); } \
    || { echo "  FAIL  no warning about notarization"; fail=$((fail+1)); }

echo
echo "2. Developer ID, notarization succeeds -> proceeds"
make_sandbox "$WORK/b" 0 devid valid
out="$(cd "$WORK/b" && PATH="$WORK/b/bin:$PATH" ./release.sh 2>&1)"; rc=$?
check "proceeds" 0 "$rc"
echo "$out" | grep -q "notarizing before release" \
    && { echo "  ok    notarization ran"; pass=$((pass+1)); } \
    || { echo "  FAIL  notarization did not run"; fail=$((fail+1)); }

echo
echo "3. Developer ID, notarization fails -> aborts, nothing published"
make_sandbox "$WORK/c" 1 devid valid
out="$(cd "$WORK/c" && PATH="$WORK/c/bin:$PATH" ./release.sh 2>&1)"; rc=$?
check "aborts" 1 "$rc"
echo "$out" | grep -q "not going out" \
    && { echo "  ok    explains why"; pass=$((pass+1)); } \
    || { echo "  FAIL  no explanation"; fail=$((fail+1)); }
echo "$out" | grep -q "gh release create" \
    && { echo "  FAIL  published anyway"; fail=$((fail+1)); } \
    || { echo "  ok    nothing was published"; pass=$((pass+1)); }

echo
echo "4. Developer ID, notarization claims success but no valid ticket -> aborts"
make_sandbox "$WORK/d" 0 devid invalid
out="$(cd "$WORK/d" && PATH="$WORK/d/bin:$PATH" ./release.sh 2>&1)"; rc=$?
check "aborts" 1 "$rc"
echo "$out" | grep -q "no valid notarization ticket" \
    && { echo "  ok    caught the invalid ticket"; pass=$((pass+1)); } \
    || { echo "  FAIL  invalid ticket not caught"; fail=$((fail+1)); }

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
