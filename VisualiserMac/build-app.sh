#!/bin/bash
# Builds the Swift package and packages it as a Mac .app bundle.
# Usage: ./build-app.sh [debug|release]
#
# Set REQUIRE_WATCHER=1 to make a missing startup watcher a hard failure rather
# than a warning — release.sh does, since a release that ships without it has a
# toggle that silently does nothing.

set -e

CONFIG="${1:-debug}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Vibresia"
BUNDLE_ID="com.minithlabs.visualiser"
# Build version, computed from today's date — see version.sh. A release
# pins the version it decided on with VERSION_OVERRIDE, so the app and the
# git tag can't drift apart.
VERSION="${VERSION_OVERRIDE:-$("$SCRIPT_DIR/version.sh")}"

# PostHog project key. Public by design (write-only, like Stripe's publishable
# key) — it can only add events, never read them. Override in the environment
# or in a .env file sitting next to this script:
#
#   POSTHOG_KEY=phc_xxxxxxxxxxxxxxxxxxxx
#   POSTHOG_HOST=https://eu.i.posthog.com   # or https://us.i.posthog.com
#
# Leave POSTHOG_KEY empty to ship a build with no telemetry wired up at all;
# the in-app toggle then reads "Not configured in this build."
if [ -f "$SCRIPT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
fi
POSTHOG_KEY="${POSTHOG_KEY:-}"
POSTHOG_HOST="${POSTHOG_HOST:-https://us.i.posthog.com}"

# Where the app reports crashes and audio failures, and the shared token that
# says it's us. Same site the landing page is served from, so the Discord
# webhook behind /api/notify stays a Worker secret instead of shipping inside
# the app. Leave empty to build an app that reports nothing.
#
#   REPORT_TOKEN=…            (the same value as the NOTIFY_TOKEN secret)
#   REPORT_ENDPOINT=https://…  (defaults to the live site)
REPORT_TOKEN="${REPORT_TOKEN:-}"
REPORT_ENDPOINT="${REPORT_ENDPOINT:-https://vibresia.com/api/notify}"
if [ -z "$REPORT_TOKEN" ]; then
    echo "NOTE: no REPORT_TOKEN set — this build won't report crashes to Discord."
fi

if [ "$CONFIG" = "release" ]; then
    # Preserve DWARF in the optimized binary so dsymutil can emit the symbols
    # PostHog Error Tracking needs to symbolicate production crashes.
    swift build -c release -Xswiftc -g
    BIN_PATH=".build/release/$APP_NAME"
    WATCHER_PATH=".build/release/VibresiaWatcher"
else
    swift build
    BIN_PATH=".build/debug/$APP_NAME"
    WATCHER_PATH=".build/debug/VibresiaWatcher"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "Build did not produce binary at $BIN_PATH"
    exit 1
fi

APP_BUNDLE="build/$APP_NAME.app"
DSYM_PATH="build/$APP_NAME.app.dSYM"
rm -rf "$APP_BUNDLE"
if [ "$CONFIG" = "release" ]; then
    rm -rf "$DSYM_PATH"
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
# The watcher runs from inside the bundle as a launchd agent — see
# Sources/VisualiserMac/Startup/WatcherControl.swift.
mkdir -p "$APP_BUNDLE/Contents/Helpers"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [ -f "$WATCHER_PATH" ]; then
    cp "$WATCHER_PATH" "$APP_BUNDLE/Contents/Helpers/VibresiaWatcher"
    chmod +x "$APP_BUNDLE/Contents/Helpers/VibresiaWatcher"
else
    echo "WARNING: no VibresiaWatcher binary — 'Open with Music or Spotify' will be unavailable." >&2
fi
# Regenerate with: swift scripts/make-icon.swift (from the repo root)
cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Vibresia</string>
    <key>CFBundleDisplayName</key>
    <string>Vibresia</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Vibresia listens to the microphone so it can visualize ambient sound. No audio is stored or transmitted.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Vibresia listens to system audio so it can visualize whatever is playing on your Mac. No audio is stored or transmitted.</string>
    <key>PostHogKey</key>
    <string>${POSTHOG_KEY}</string>
    <key>PostHogHost</key>
    <string>${POSTHOG_HOST}</string>
    <key>ReportEndpoint</key>
    <string>${REPORT_ENDPOINT}</string>
    <key>ReportToken</key>
    <string>${REPORT_TOKEN}</string>
    <!-- Register Vibresia as the handler for vibresia:// URLs so a shared
         vibescape link handed to us (vibresia://open?p=ribbons or ?d=...) lands
         in the app rather than in the browser. The handler is wired up in
         AppDelegate.applicationWillFinishLaunching. -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.minithlabs.visualiser.share</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>vibresia</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Add the screen-capture entitlement so SCK can capture system audio
mkdir -p "$APP_BUNDLE/Contents/Resources"
cat > "$APP_BUNDLE/Contents/Resources/Entitlements.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.screen-capture</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

# codesign ad-hoc so ScreenCaptureKit permission prompts work reliably.
# Fail loudly if this doesn't work — a broken signature makes macOS refuse
# to launch the app with "may be damaged or incomplete".
if ! codesign --force --sign - --entitlements "$APP_BUNDLE/Contents/Resources/Entitlements.plist" "$APP_BUNDLE"; then
    echo "ERROR: codesign failed — the app would not open." >&2
    exit 1
fi

# Sanity-check the bundle: LaunchServices refuses to open a bundle whose
# Info.plist points at an executable that isn't there, and the error it shows
# ("may be damaged or incomplete") gives no hint why.
PLIST_EXEC=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_BUNDLE/Contents/Info.plist")
if [ ! -x "$APP_BUNDLE/Contents/MacOS/$PLIST_EXEC" ]; then
    echo "ERROR: Info.plist says CFBundleExecutable=$PLIST_EXEC but" \
         "Contents/MacOS/$PLIST_EXEC does not exist." >&2
    exit 1
fi
# The watcher is referenced by absolute path in a LaunchAgent the app writes at
# runtime, so a missing helper is a silent feature failure unless it's checked.
if [ "$REQUIRE_WATCHER" = "1" ] && [ ! -x "$APP_BUNDLE/Contents/Helpers/VibresiaWatcher" ]; then
    echo "ERROR: the startup watcher helper is missing from the bundle." >&2
    exit 1
fi
if ! plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null; then
    echo "ERROR: Info.plist is malformed." >&2
    exit 1
fi
if ! codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    echo "ERROR: signature does not verify — the app would not open." >&2
    exit 1
fi

if [ "$CONFIG" = "release" ]; then
    dsymutil "$BIN_PATH" -o "$DSYM_PATH"

    # Teammate and pull-request builds may not have upload credentials. Keep
    # producing the dSYM in that case, and upload only when the full CLI
    # credential set is available from the environment or the root .env file.
    if [ -n "${POSTHOG_CLI_API_KEY:-}" ] && \
       [ -n "${POSTHOG_CLI_PROJECT_ID:-}" ] && \
       [ -n "${POSTHOG_CLI_HOST:-}" ]; then
        CONFIGURATION=Release \
        DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
        ENABLE_USER_SCRIPT_SANDBOXING=NO \
        DWARF_DSYM_FOLDER_PATH="$SCRIPT_DIR/build" \
        DWARF_DSYM_FILE_NAME="$APP_NAME.app.dSYM" \
        EXECUTABLE_NAME="$APP_NAME" \
        TARGET_BUILD_DIR="$SCRIPT_DIR/build" \
        EXECUTABLE_PATH="$APP_NAME.app/Contents/MacOS/$APP_NAME" \
        SRCROOT="$SCRIPT_DIR" \
        INFOPLIST_FILE="$SCRIPT_DIR/$APP_BUNDLE/Contents/Info.plist" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$VERSION" \
        POSTHOG_INCLUDE_SOURCE=1 \
        POSTHOG_CLI_DOTENV_FILE="$SCRIPT_DIR/.env" \
        "$SCRIPT_DIR/.build/checkouts/posthog-ios/build-tools/upload-symbols.sh"
    else
        echo "NOTE: PostHog upload credentials are incomplete — dSYM upload skipped."
    fi
fi

echo ""
echo "Built: $APP_BUNDLE"
echo "Run: open $APP_BUNDLE"