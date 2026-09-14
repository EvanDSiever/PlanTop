#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "🔨 Compiling SongTop..."
swiftc -O -framework AppKit -framework QuartzCore -framework Combine -framework WebKit -framework EventKit -framework ServiceManagement \
    Sources/SongTop/Models/*.swift \
    Sources/SongTop/Services/*.swift \
    Sources/SongTop/Views/*.swift \
    Sources/SongTop/Controllers/*.swift \
    Sources/SongTop/AppDelegate.swift \
    Sources/SongTop/main.swift \
    -o SongTop

APP_NAME="SongTop.app"
APP_DIR="$DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating $APP_NAME bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp SongTop "$MACOS_DIR/SongTop"
chmod +x "$MACOS_DIR/SongTop"

# Copy Icon if present
if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Create Info.plist
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SongTop</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.songtop.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SongTop</string>
    <key>CFBundleDisplayName</key>
    <string>SongTop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>SongTop detects currently playing YouTube tracks from your web browser tabs.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>SongTop accesses your calendar to display today's events in the calendar panel.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>SongTop accesses your Google Calendar events to show today's schedule in the floating panel.</string>
</dict>
</plist>
EOF

# Ad-hoc codesign
codesign --force --deep -s - "$APP_DIR" 2>/dev/null || true

echo "📦 Packaging SongTop.zip for distribution..."
rm -f "$DIR/SongTop.zip"
zip -r -y -q "$DIR/SongTop.zip" "$APP_NAME"

echo "✅ Successfully built and signed $APP_NAME!"
echo "📍 Location: $APP_DIR"
echo "🎁 Release archive: $DIR/SongTop.zip"
