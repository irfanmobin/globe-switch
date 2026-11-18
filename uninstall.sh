#!/bin/bash
# Remove globe-switch and restore the default Globe-key behavior.
set -uo pipefail
LABEL="com.local.globe-switch"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/globe-switch"
defaults write com.apple.HIToolbox AppleFnUsageType -int 1   # 1 = Change Input Source
echo "Uninstalled. 'Press 🌐 key to' restored to 'Change Input Source' (log out/in if it doesn't take effect)."
