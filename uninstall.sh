#!/bin/bash
# Remove globe-switch and restore the default Globe-key behavior.
set -uo pipefail
LABEL="com.local.globe-switch"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/globe-switch"
rm -rf "$HOME/Applications/GlobeSwitch.app"
defaults write com.apple.HIToolbox AppleFnUsageType -int 1   # 1 = Change Input Source
defaults delete kCFPreferencesAnyApplication TSMLanguageIndicatorEnabled 2>/dev/null   # restore macOS's popup
killall -9 TextInputSwitcher 2>/dev/null   # make macOS pick up the restored setting
echo "Uninstalled. 'Press 🌐 key to' restored to 'Change Input Source' ."
