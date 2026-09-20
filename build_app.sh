#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "🔨 Compiling PlanTop..."
swiftc -O -framework AppKit -framework QuartzCore -framework Combine -framework EventKit -framework ServiceManagement \
    Sources/PlanTop/Models/*.swift \
    Sources/PlanTop/Services/*.swift \
    Sources/PlanTop/Views/*.swift \
    Sources/PlanTop/Controllers/*.swift \
    Sources/PlanTop/AppDelegate.swift \
    Sources/PlanTop/main.swift \
    -o PlanTop

APP_NAME="PlanTop.app"
APP_DIR="$DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating $APP_NAME bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp PlanTop "$MACOS_DIR/PlanTop"
chmod +x "$MACOS_DIR/PlanTop"

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
    <string>PlanTop</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.plantop.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PlanTop</string>
    <key>CFBundleDisplayName</key>
    <string>PlanTop</string>
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
    <key>NSCalendarsUsageDescription</key>
    <string>PlanTop accesses your calendar to display your schedule in the daily planner panel.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>PlanTop accesses your calendar events to show your schedule in the daily planner panel.</string>
</dict>
</plist>
EOF

# Ad-hoc codesign
codesign --force --deep -s - "$APP_DIR" 2>/dev/null || true

echo "📦 Packaging PlanTop.zip for distribution..."
rm -f "$DIR/PlanTop.zip"
zip -r -y -q "$DIR/PlanTop.zip" "$APP_NAME"

echo "✅ Successfully built and signed $APP_NAME!"
echo "📍 Location: $APP_DIR"
echo "🎁 Release archive: $DIR/PlanTop.zip"

