#!/bin/bash
# Builds release binaries and assembles:
#   FileRenamer.app                  — the menu bar app
#   FileRenamerService.app           — the Finder Services helper
# and installs the service into ~/Library/Services so it shows up in
# Finder's right-click → Services menu.
set -e
cd "$(dirname "$0")"

# ---------- Version (derived from git, never hand-edited) ----------
# Version = latest vX.Y.Z tag on this branch (commits after the tag keep the
# last release's version); build number = total commit count.
# Release flow: make the changes, commit, `git tag v1.3.0`, run make_app.sh.
VERSION=$(git describe --tags --match 'v[0-9]*' --first-parent 2>/dev/null | sed 's/^v//; s/-[0-9]*-g[0-9a-f]*$//')
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
[ -n "$VERSION" ] || VERSION="0.0.0"
echo "Building AI FileRenamer $VERSION (build $BUILD)"

swift build -c release

# ---------- Menu bar app ----------
APP=FileRenamer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FileRenamer "$APP/Contents/MacOS/FileRenamer"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>FileRenamer</string>
    <key>CFBundleDisplayName</key>
    <string>AI FileRenamer</string>
    <key>NSHumanReadableCopyright</key>
    <string>Made by Grant Della Vecchia</string>
    <key>CFBundleIdentifier</key>
    <string>local.grant.filerenamer</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    <!-- Endpoints are user-configured and are very often plain-HTTP local/self-hosted
         LLM servers (Ollama, llama.cpp, ...), so allow arbitrary loads. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

# ---------- Finder Services helper ----------
# Built directly into ~/Library/Services. Do NOT also keep a copy in the
# project directory: two bundles sharing the service's CFBundleIdentifier
# confuse LaunchServices and the Services menu drops the entry.
SERVICES_DIR="$HOME/Library/Services"
SVC="$SERVICES_DIR/AI FileRenamer.service"
rm -rf "$SVC"
mkdir -p "$SVC/Contents/MacOS"
cp .build/release/FileRenamerService "$SVC/Contents/MacOS/FileRenamerService"
cat > "$SVC/Contents/Info.plist" <<EOF
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
    <string>$BUILD</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
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

# Make LaunchServices and the Services menu (pbs daemon) notice it right
# away — otherwise this can take until the next login.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$SVC" 2>/dev/null || true
killall pbs 2>/dev/null || true   # pbs rebuilds its service database on restart

echo "Built $APP (v$VERSION, build $BUILD)"
echo "Installed service to $SVC"
echo "Run the app with: open $APP"
