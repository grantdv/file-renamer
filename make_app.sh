#!/bin/bash
# Builds release binaries and assembles:
#   FileRenamer.app                  — the menu bar app
#   FileRenamerService.app           — the Finder Services helper
# and installs the service into ~/Library/Services so it shows up in
# Finder's right-click → Services menu.
set -e
cd "$(dirname "$0")"
swift build -c release

# ---------- Menu bar app ----------
APP=FileRenamer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/FileRenamer "$APP/Contents/MacOS/FileRenamer"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>FileRenamer</string>
    <key>CFBundleDisplayName</key>
    <string>AI FileRenamer</string>
    <key>NSHumanReadableCopyright</key>
    <string>Made by Grant</string>
    <key>CFBundleIdentifier</key>
    <string>local.grant.filerenamer</string>
    <key>CFBundleVersion</key>
    <string>1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleExecutable</key>
    <string>FileRenamer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# ---------- Finder Services helper ----------
SVC=FileRenamerService.app
rm -rf "$SVC"
mkdir -p "$SVC/Contents/MacOS"
cp .build/release/FileRenamerService "$SVC/Contents/MacOS/FileRenamerService"
cat > "$SVC/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AI FileRenamer Service</string>
    <key>CFBundleDisplayName</key>
    <string>AI FileRenamer Service</string>
    <key>CFBundleIdentifier</key>
    <string>local.grant.filerenamer.service</string>
    <key>CFBundleVersion</key>
    <string>1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleExecutable</key>
    <string>FileRenamerService</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Rename with AI FileRenamer</string>
            </dict>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.file-url</string>
            </array>
            <key>NSServiceName</key>
            <string>RenameWithAIFileRenamer</string>
        </dict>
    </array>
</dict>
</plist>
EOF

# ad-hoc sign both so Gatekeeper/launchd is happy locally
codesign --force --sign - "$APP" 2>/dev/null || true
codesign --force --sign - "$SVC" 2>/dev/null || true

# ---------- Install the service ----------
SERVICES_DIR="$HOME/Library/Services"
mkdir -p "$SERVICES_DIR"
rm -rf "$SERVICES_DIR/AI FileRenamer.service"
cp -R "$SVC" "$SERVICES_DIR/AI FileRenamer.service"
# Make LaunchServices notice it immediately (usually happens on its own,
# but this avoids a logout in the common case).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$SERVICES_DIR/AI FileRenamer.service" 2>/dev/null || true

echo "Built $APP and $SVC"
echo "Installed service to $SERVICES_DIR/AI FileRenamer.service"
echo "Run the app with: open $APP"
