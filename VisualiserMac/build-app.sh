#!/bin/bash
# Builds the Swift package and packages it as a Mac .app bundle.
# Usage: ./build-app.sh [debug|release]

set -e

CONFIG="${1:-debug}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="VisualiserMac"
BUNDLE_ID="com.minithlabs.visualiser"

if [ "$CONFIG" = "release" ]; then
    swift build -c release
    BIN_PATH=".build/release/$APP_NAME"
else
    swift build
    BIN_PATH=".build/debug/$APP_NAME"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "Build did not produce binary at $BIN_PATH"
    exit 1
fi

APP_BUNDLE="build/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AUDIVANE</string>
    <key>CFBundleDisplayName</key>
    <string>AUDIVANE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AUDIVANE</string>
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
    <string>AUDIVANE listens to the microphone so it can visualize ambient sound. No audio is stored or transmitted.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>AUDIVANE listens to system audio so it can visualize whatever is playing on your Mac. No audio is stored or transmitted.</string>
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

# codesign ad-hoc so ScreenCaptureKit permission prompts work reliably
codesign --force --sign - --entitlements "$APP_BUNDLE/Contents/Resources/Entitlements.plist" "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "Built: $APP_BUNDLE"
echo "Run: open $APP_BUNDLE"