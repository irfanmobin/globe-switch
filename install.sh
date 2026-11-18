#!/bin/bash
# Build globe-switch, disable macOS's built-in Globe-key action, and start it at login.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/GlobeSwitch.app"
BIN="$APP/Contents/MacOS/globe-switch"
PLIST="$HOME/Library/LaunchAgents/com.local.globe-switch.plist"
LABEL="com.local.globe-switch"

echo "Building $APP ..."
rm -f "$HOME/.local/bin/globe-switch"   # old location from earlier versions
mkdir -p "$(dirname "$BIN")"
cat > "$APP/Contents/Info.plist" <<IP
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>GlobeSwitch</string>
  <key>CFBundleExecutable</key><string>globe-switch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
IP
swiftc -O main.swift -o "$BIN"
codesign -s - -f --identifier "$LABEL" "$APP"

echo "Setting 'Press 🌐 key to' -> Do Nothing (so macOS doesn't also switch)..."
defaults write com.apple.HIToolbox AppleFnUsageType -int 0

echo "Installing LaunchAgent..."
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/tmp/globe-switch.log</string>
  <key>StandardOutPath</key><string>/tmp/globe-switch.log</string>
</dict></plist>
PL

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo
echo "Done. If the Globe key doesn't switch input sources yet:"
echo "  1. System Settings > Privacy & Security > Input Monitoring: enable GlobeSwitch ($APP)"
echo "  2. System Settings > Keyboard: confirm 'Press 🌐 key to' is 'Do Nothing'"
echo "  3. Restart it: launchctl kickstart -k gui/\$(id -u)/$LABEL"
