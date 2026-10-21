#!/bin/bash
# Packages the built app, submits it to Apple's notary service, and staples the
# ticket on.
#
# Split out of build-app.sh so the build stays runnable without any Apple
# credentials: build-app.sh signs ad-hoc when there's no Developer ID
# certificate, and this script is the only thing that needs one.
#
#   ./scripts/notarize.sh            package, submit, staple
#   ./scripts/notarize.sh --check    everything except the submission
#
# --check exists so the packaging can be rehearsed before the certificate
# arrives. It builds the pkg, and reports exactly what is missing to go the rest
# of the way, rather than failing at the first notarytool call with a message
# about credentials.
#
# Needs a Developer ID Application certificate in the keychain
# (`security find-identity -v -p codesigning`) and notary credentials stored
# under $NOTARY_PROFILE — see `xcrun notarytool store-credentials`.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # VisualiserMac
site="$(cd "$here/.." && pwd)"                              # repo root
cd "$here"

APP_NAME="Vibresia"
BUNDLE_ID="com.minithlabs.visualiser"
APP="$here/build/$APP_NAME.app"
PKG="$here/dist/$APP_NAME.pkg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

NOTARY_PROFILE="${NOTARY_PROFILE:-vibresia-notary}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight

command -v xcrun >/dev/null || die "xcrun is missing — this needs Xcode's command line tools."
command -v pkgbuild >/dev/null || die "pkgbuild is missing."

# The identities are read into a variable first. `head -1` closes the pipe
# early, sed dies of SIGPIPE, and with pipefail on that reads as a failure of
# the whole pipeline — so the identity would come back empty and the script
# would say there is no certificate when there is one.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
IDENTITY="$(printf '%s\n' "$IDENTITIES" \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')"
# The sed above prints every match, one per line; take the first.
IDENTITY="${IDENTITY%%$'\n'*}"

say "Developer ID certificate: ${IDENTITY:-<none found>}"
say "notary profile:          $NOTARY_PROFILE"

# The installer is a separate certificate from the application. A pkg is
# signed with a "Developer ID Installer" identity, and pkgbuild refuses an
# application identity outright: "Could not find appropriate signing identity
# ... An installer signing identity (not an application signing identity) is
# required for signing flat-style products."
#
# The pkg is the optional extra — for anyone who would rather install
# through Installer than unzip the app. The zip is what release.sh attaches
# and what install.sh and the in-app updater fetch, so a missing installer
# certificate must not stop the zip from being notarized.
INSTALLER_IDENTITY="$(printf '%s\n' "$IDENTITIES" \
    | sed -n 's/.*"\(Developer ID Installer:[^"]*\)".*/\1/p')"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY%%$'\n'*}"
say "installer certificate:   ${INSTALLER_IDENTITY:-<none found — the pkg will be skipped>}"

if [ -z "$IDENTITY" ]; then
    cat >&2 <<'EOF'

Nothing here can be notarized without a Developer ID Application certificate.

  1. Apple Developer Program membership (paid) is required.
  2. Create a CSR:  Keychain Access -> Certificate Assistant -> Create a
     Certificate -> Developer ID Application. Or:
       openssl req -new -newkey rsa:2048 -nodes -keyout devid.key \
         -out devid.csr -subj "/email=YOU@minithlabs.com/commonName=Developer ID Application: Minith Labs"
  3. Upload the .csr at developer.apple.com/account/resources/certificates,
     under Developer ID Application.
  4. Download the .cer and double-click it to install into the login keychain.
  5. Confirm:  security find-identity -v -p codesigning

EOF
    [ "$CHECK_ONLY" -eq 1 ] || die "no Developer ID certificate."
    # Keep going in --check mode: the packaging below is still worth proving out.
fi

if [ ! -d "$APP" ]; then
    die "no built app at $APP — run ./build-app.sh release first."
fi

# The bundle has to be signed with hardened runtime and a real identity before
# it is worth submitting. Catching it here beats Apple's rejection email.
if [ -n "$IDENTITY" ]; then
    flags="$(codesign -dv --verbose=4 "$APP" 2>&1 || true)"
    echo "$flags" | grep -q 'flags=.*runtime' \
        || die "the app is not signed with hardened runtime. Re-run ./build-app.sh release."
    echo "$flags" | grep -q "Authority=$IDENTITY" \
        || die "the app is not signed with '$IDENTITY'."
fi

# ------------------------------------------------------- verify the signature

say "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

if [ -x "$APP/Contents/Helpers/VibresiaWatcher" ]; then
    # Separately, because a bundle can verify while a helper inside it is
    # unsigned — which is the single most common notarization rejection.
    codesign --verify --strict --verbose=2 "$APP/Contents/Helpers/VibresiaWatcher"
fi

# ------------------------------------------------------------------- packaging

mkdir -p "$here/dist"

# The zip is what people actually download and what the in-app updater fetches.
# A .zip cannot be stapled, so the app's ticket goes on the app and the zip is
# rebuilt around it.
#
# --norsrc: ditto otherwise stores attributes it cannot fit in a zip as
# AppleDouble sidecars, and those sidecars land inside the signed bundle when
# it is unpacked, which invalidates the signature. The app has no resource
# forks worth keeping.
say "Packaging the zip"
(cd "$here/build" && ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$WORK/$APP_NAME.zip")

# The pkg needs a "Developer ID Installer" certificate, which is a different
# certificate from the application one and is not issued with it. Without it
# there is no signed pkg, so the pkg is skipped and the zip is notarized on
# its own — the zip is the artifact that matters.
if [ -n "$INSTALLER_IDENTITY" ]; then
    say "Packaging the pkg"
    pkgbuild --component "$APP" \
             --install-location /Applications \
             --identifier "$BUNDLE_ID" \
             --sign "$INSTALLER_IDENTITY" --timestamp \
             "$PKG"
    say "Built $(basename "$PKG") ($(du -h "$PKG" | cut -f1))"
else
    say "Skipping the pkg — no Developer ID Installer certificate." >&2
    say "    That is a separate certificate from the application one, and it" >&2
    say "    is the only thing the .pkg is for. The zip is what people" >&2
    say "    actually download, so it gets notarized on its own." >&2
    rm -f "$PKG"
fi
say "Built $APP_NAME.zip ($(du -h "$WORK/$APP_NAME.zip" | cut -f1))"

if [ "$CHECK_ONLY" -eq 1 ]; then
    cat <<EOF

--- rehearsal only, nothing submitted ---

To finish notarization:

  xcrun notarytool store-credentials $NOTARY_PROFILE \\
      --apple-id "you@minithlabs.com" --team-id TEAMID --password "app-specific"

  ./scripts/notarize.sh

EOF
    exit 0
fi

[ -n "$IDENTITY" ] || die "refusing to submit an ad-hoc-signed build."
# The profile has to be named here, or the check looks for a default profile
# that does not exist and reports that there are no credentials when there
# are — the credentials are stored under $NOTARY_PROFILE and nowhere else.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || \
    die "no notary credentials under '$NOTARY_PROFILE'. Create them with:
  xcrun notarytool store-credentials $NOTARY_PROFILE \\
      --apple-id \"you@minithlabs.com\" --team-id TEAMID
(notarytool prompts for the app-specific password.)"

# --------------------------------------------------------------- submission

# --wait blocks until Apple finishes, and exits non-zero on rejection. The log
# is what says *why*, and Apple's message for most rejections points at a nested
# binary rather than anything obvious in the app itself.
submit() {
    local file="$1" label="$2"
    say "Submitting $label to Apple…"
    if xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait; then
        return 0
    fi
    printf 'ERROR: %s was rejected. Apple says:\n' "$label" >&2
    xcrun notarytool log "$file" --keychain-profile "$NOTARY_PROFILE" >&2 \
        || echo "(could not fetch the log — is the network up?)" >&2
    return 1
}

submit "$WORK/$APP_NAME.zip" "$APP_NAME.zip"
if [ -f "$PKG" ]; then
    submit "$PKG" "$APP_NAME.pkg"
fi

# ------------------------------------------------------------------ stapling

say "Stapling the ticket to the app"
ditto -x -k "$WORK/$APP_NAME.zip" "$WORK/unzipped"
xcrun stapler staple "$WORK/unzipped/$APP_NAME.app"

say "Rebuilding the zip around the stapled app"
rm -f "$WORK/$APP_NAME.zip"
(cd "$WORK/unzipped" && ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$here/dist/$APP_NAME.zip")
# The zip in dist/ now contains a stapled app; refresh the working copy too so a
# second run starts from the same thing rather than the unstapled original.
rm -rf "$APP"
ditto "$WORK/unzipped/$APP_NAME.app" "$APP"

if [ -f "$PKG" ]; then
    say "Stapling the ticket to the pkg"
    xcrun stapler staple "$PKG"
fi

# --------------------------------------------------------------------- verify

say "Verifying the stapled ticket"
xcrun stapler validate "$APP"
if [ -f "$PKG" ]; then
    xcrun stapler validate "$PKG"
fi

say "Checking Gatekeeper's own view"
# spctl is the authority that matters at the user's end: it's what double-clicking
# the app goes through, so it catches a signature Gatekeeper rejects even though
# notarization succeeded.
if spctl --assess --type execute --verbose=4 "$APP" 2>&1 | grep -q 'accepted'; then
    echo "    Gatekeeper: accepted"
else
    echo "    Gatekeeper did not accept it yet — this is normal on the first" >&2
    echo "    run after stapling, and on a machine with no network. Re-run this" >&2
    echo "    script's checks later, or ask someone else to try the download." >&2
fi

cat <<EOF

==> Notarized and stapled

    $here/dist/$APP_NAME.zip
EOF

if [ -f "$PKG" ]; then
    cat <<EOF
    $here/dist/$APP_NAME.pkg
EOF
fi

cat <<EOF

    The zip is what release.sh attaches and what the in-app updater fetches.
EOF

if [ -f "$PKG" ]; then
    cat <<EOF
    The pkg is there for anyone who would rather install through Installer.
EOF
else
    cat <<EOF
    There is no pkg: signing one needs a Developer ID Installer certificate,
    which is a separate certificate from the application one.
EOF
fi