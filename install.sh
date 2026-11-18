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
# TextInputSwitcher handles the Globe key (and its language popup) and caches this
# setting. Restart it so it stops switching on its own; macOS relaunches it on demand.
echo "Turning off macOS's language popup at the cursor (GlobeSwitch shows its own)..."
defaults write kCFPreferencesAnyApplication TSMLanguageIndicatorEnabled -bool false
killall -9 TextInputSwitcher 2>/dev/null || true
killall -9 CursorUIViewService 2>/dev/null || true   # draws macOS's popup; relaunches on demand

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
# bootout is asynchronous; bootstrap can fail with "5: Input/output error" until it finishes.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null && break
    sleep 0.5
done
launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || { echo "Failed to load LaunchAgent $LABEL" >&2; exit 1; }

echo
echo "Done. If the Globe key doesn't switch input sources yet:"
echo "  1. System Settings > Privacy & Security: add GlobeSwitch ($APP) to"
echo "       - Input Monitoring (required: lets it see the Globe key)"
echo "       - Accessibility (recommended: shows the language bubble at your text cursor)"
echo "     Re-installing invalidates both: remove GlobeSwitch with '-' and add it again with '+'."
echo "  2. System Settings > Keyboard: confirm 'Press 🌐 key to' is 'Do Nothing'"
echo "     (if quick taps still don't stick, run: killall -9 TextInputSwitcher)"
echo "  3. Restart it: launchctl kickstart -k gui/\$(id -u)/$LABEL"
