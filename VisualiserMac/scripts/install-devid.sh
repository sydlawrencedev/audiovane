#!/bin/bash
# Installs a Developer ID Application certificate into the login keychain so
# codesign can use it.
#
# Apple issues the certificate as a .cer file that contains only the public
# key. The matching private key is the one devid.key holds, from the CSR that
# was uploaded to developer.apple.com. The two have to be combined and
# imported together: import the .cer on its own and the keychain holds a
# certificate that signs nothing, and `security find-identity` still says
# "0 valid identities found" with no obvious reason why.
#
# Usage:
#   ./scripts/install-devid.sh ~/Downloads/Developer_ID_Application_*.cer
#
# The private key is expected at $DEVID_KEY, default ~/.vibresia-devid/devid.key
# (see DEVID_DIR below). Nothing here writes to the repository, and nothing
# prints a secret.
#
# After this succeeds:
#   security find-identity -v -p codesigning
# should list a "Developer ID Application: ..." identity, and build-app.sh
# will sign with it automatically — it looks for exactly that.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Where devid.key lives. Outside the repository on purpose: a private key
# sitting in a git working tree is a private key one `git add -A` away from
# being published.
DEVID_DIR="${DEVID_DIR:-$HOME/.vibresia-devid}"
DEVID_KEY="${DEVID_KEY:-$DEVID_DIR/devid.key}"

say() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: $0 <Developer_ID_Application_....cer>"
CER="$1"
[ -f "$CER" ] || die "no such file: $CER"
[ -f "$DEVID_KEY" ] || die "no private key at $DEVID_KEY"

LOGIN_KEYCHAIN="${LOGIN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
[ -f "$LOGIN_KEYCHAIN" ] || die "no login keychain at $LOGIN_KEYCHAIN"

# The .cer Apple downloads is sometimes DER and sometimes PEM. openssl
# figures out which from the first byte, but x509 -inform needs to be told,
# so try both.
read_cert() {
    if openssl x509 -in "$1" -noout -subject >/dev/null 2>&1; then
        openssl x509 -in "$1" -noout -subject
    elif openssl x509 -in "$1" -inform der -noout -subject >/dev/null 2>&1; then
        openssl x509 -in "$1" -inform der -noout -subject
    else
        die "cannot read $1 as a certificate (tried PEM and DER)"
    fi
}

say "Certificate"
read_cert "$CER"

say "Private key"
[ -f "$DEVID_KEY" ] || die "missing $DEVID_KEY"
openssl rsa -in "$DEVID_KEY" -noout -check >/dev/null 2>&1 \
    || die "$DEVID_KEY is not a readable RSA private key"

# The single most common failure here is a .cer that Apple issued for a
# different CSR — the keychain then has a certificate whose public key is not
# the private key's, and codesign says "no identity found" later with nothing
# pointing back here. So check the two match before importing anything.
cert_pub="$(openssl x509 -in "$CER" -noout -pubkey 2>/dev/null \
    || openssl x509 -in "$CER" -inform der -noout -pubkey 2>/dev/null)"
key_pub="$(openssl rsa -in "$DEVID_KEY" -pubout 2>/dev/null)"
[ -n "$cert_pub" ] && [ -n "$key_pub" ] || die "could not read a public key from one of the two"
if [ "$cert_pub" != "$key_pub" ]; then
    die "the certificate and $DEVID_KEY are not a pair.
    This .cer was issued for a different CSR than the one that produced the
    key. Re-upload devid.csr and download the certificate that comes back."
fi
say "    the certificate and the key are a pair"

# Combine them. The p12 password is random and transient: it protects the
# bundle while it is being imported and is discarded immediately afterwards.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
P12_PASS="$(openssl rand -base64 18)"
P12="$WORK/devid.p12"

say "Combining certificate and key"
# a SHA-256 MAC, and macOS's own keychain reader cannot parse that — it fails
# with "MAC verification failed during PKCS12 import (wrong password?)",
# which sends you looking for a password problem that is not there. The
# legacy algorithms are what `security import` understands.
if ! openssl pkcs12 -export -legacy -inkey "$DEVID_KEY" -in "$CER" \
        -out "$P12" -passout "pass:$P12_PASS" 2>/dev/null; then
    # DER input needs telling, and OpenSSL 1.x has no -legacy.
    openssl pkcs12 -export -inkey "$DEVID_KEY" -in "$CER" -inform der \
        -out "$P12" -passout "pass:$P12_PASS" \
        || die "could not build the p12 from the certificate and the key"
fi

# The issuing intermediate has to be in the keychain too, or codesign cannot
# build a chain to a trusted root and refuses the identity with "unable to
# build chain to self-signed root".
#
# macOS does not ship the "Developer ID - G2" intermediate — it ships the
# older "Developer ID - G1" one, whose authority key identifier is different,
# so a certificate issued under G2 has no path to a root on a stock macOS.
# Apple publishes both:
#
#   Developer ID - G1  https://www.apple.com/certificateauthority/DeveloperIDCA.cer
#   Developer ID - G2  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
#
# Which one applies is decided by the authority key identifier in the
# certificate, so fetch both and install the one that matches. With the
# intermediate in the keychain, codesign embeds it in the signed bundle, and
# Gatekeeper builds the chain from there — which is what every other
# Developer ID app does, and what makes the app work on a Mac whose trust
# store has only the G1 intermediate.
# Reads a hex identifier (SKID or AKI) out of a certificate. The .cer Apple
# downloads is sometimes DER and sometimes PEM, and openssl figures out which
# from the first byte for -text but not for the other subcommands, so both
# are tried.
cert_hexid() { # file label
    local f="$1" label="$2" out
    for mode in "-in" "-inform der -in"; do
        # shellcheck disable=SC2086
        out="$(openssl x509 $mode "$f" -noout -text 2>/dev/null \
            | grep -A1 "$label" | tail -1 | tr -d ' \r:' )" || true
        if [ -n "$out" ]; then
            printf '%s' "$out"
            return 0
        fi
    done
    return 1
}

say "Checking the issuing intermediate is available"
cert_aki="$(cert_hexid "$CER" "Authority Key Identifier")" \
    || die "could not read the authority key identifier from the certificate"

intermediate_found=0
for url in \
    "https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer" \
    "https://www.apple.com/certificateauthority/DeveloperIDCA.cer"; do
    name="$(basename "$url")"
    if [ ! -f "$WORK/$name" ]; then
        curl -fsSL -o "$WORK/$name" "$url" 2>/dev/null || continue
    fi
    skid="$(cert_hexid "$WORK/$name" "Subject Key Identifier")" || continue
    if [ "$skid" = "$cert_aki" ]; then
        say "    $name is the issuer — installing it"
        security import "$WORK/$name" -k "$LOGIN_KEYCHAIN" >/dev/null 2>&1 \
            || die "could not import $name into the keychain"
        intermediate_found=1
        break
    fi
done
if [ "$intermediate_found" -eq 0 ]; then
    echo "    could not find the intermediate Apple issued this certificate" >&2
    echo "    under. codesign will not be able to build a chain, so the" >&2
    echo "    identity will not be usable." >&2
fi

say "Importing into the login keychain"
security import "$P12" -k "$LOGIN_KEYCHAIN" \
    -T /usr/bin/codesign -T /usr/bin/security \
    -P "$P12_PASS" >/dev/null \
    || die "security import failed"

# Without this, codesign asks for permission to use the key every time, with
# a dialog that does not name the app asking for it. It needs the keychain
# password, so it prompts for it rather than taking it as an argument —
# a password on the command line ends up in the shell history.
#
# It is not fatal if this fails: it needs a terminal to prompt on, and a key
# imported with -T /usr/bin/codesign often already has the right access. The
# check at the end is the real gate.
say "Granting codesign access to the key (prompts for your login password)"
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$LOGIN_KEYCHAIN"; then
    echo "    could not set the key partition list — continuing." >&2
    echo "    If codesign later asks for permission to use the key, run:" >&2
    echo "      security set-key-partition-list -S apple-tool:,apple:,codesign: -s" >&2
    echo "      $LOGIN_KEYCHAIN" >&2
fi

say "Verifying"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application:"; then
    die "the identity still does not show up.
    security find-identity -v -p codesigning says:
$(security find-identity -v -p codesigning 2>&1 | sed 's/^/      /')"
fi
security find-identity -v -p codesigning | grep "Developer ID Application:" | sed 's/^/    /'

cat <<EOF

==> Installed

    build-app.sh signs with it automatically, and notarize.sh can now
    submit to Apple. Next:

      ./build-app.sh release      # signs with the identity + hardened runtime
      ./scripts/notarize.sh       # submits, staples, rebuilds the zip
      ./release.sh                # publishes

EOF
