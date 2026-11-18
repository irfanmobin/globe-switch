# globe-switch

**Make the 🌐 Globe (fn) key on a Mac switch keyboard languages instantly, every time.**

## The problem

On Mac keyboards, the Globe key (bottom-left, next to Control) can be set to change your input source (keyboard language). macOS only switches if you tap the key **quickly**. Hold it a moment too long and nothing happens when you let go. So a single press sometimes switches and sometimes doesn't, and you end up typing in the wrong language.

## What globe-switch does

globe-switch is a tiny background program (about 80 lines of Swift, no dependencies) that:

- **Switches input source the moment the Globe key goes down**, however long you hold it.
- **Cycles through your enabled keyboard layouts and input methods** (e.g. U.S. ↔ Arabic, or English → French → Japanese).
- **Keeps Globe/fn shortcuts working.** If you press another key while holding Globe (fn+Delete, fn+←/→, Globe+E for emoji, Globe+F for full screen), the switch is undone, so shortcuts don't change your language.
- Starts automatically at login through a LaunchAgent.

It only listens to keyboard events (a *listen-only* event tap). It never changes, blocks, records, or sends your keystrokes anywhere.

## Requirements

- macOS 11 or later (tested on macOS 26)
- Xcode Command Line Tools (for `swiftc`): `xcode-select --install`
- At least two input sources added in System Settings → Keyboard → Text Input → Input Sources

## Install

```bash
git clone https://github.com/irfanmobin/globe-switch.git
cd globe-switch
./install.sh
```

The installer:
1. Compiles `main.swift` into a small background app, `~/Applications/GlobeSwitch.app` (no Dock icon), and ad-hoc signs it.
2. Sets **System Settings → Keyboard → "Press 🌐 key to"** to **Do Nothing**, so macOS doesn't switch a second time and cancel globe-switch out.
3. Installs and starts a LaunchAgent (`~/Library/LaunchAgents/com.local.globe-switch.plist`).

### Grant permission (required)

macOS needs your approval before a program can see keyboard events. **Until you give it, globe-switch receives nothing and the Globe key keeps macOS's default behavior.**

1. Open **System Settings → Privacy & Security → Input Monitoring**.
2. Click **+**, press ⌘⇧G, enter `~/Applications/GlobeSwitch.app`, click Open, and make sure its switch is **on**. (If macOS shows a prompt for GlobeSwitch, you can approve that instead.)
3. Wait about 15 seconds. globe-switch checks for permission every 15 seconds and starts on its own once it has it.

Also check that **System Settings → Keyboard → "Press 🌐 key to"** reads **Do Nothing**. If it doesn't, set it by hand (or log out and back in).

## Usage

Press the Globe key. That's it: tap or hold, your language switches straight away.

| You do | Result |
|---|---|
| Tap Globe | Switches to the next input source |
| Hold Globe, then release | Switches as soon as it goes down; releasing does nothing |
| Hold Globe + another key (fn+Delete, Globe+E, …) | The shortcut runs; your input source stays the same |

## Troubleshooting

- **Short taps switch but long presses don't:** globe-switch isn't running with permission, so you're seeing macOS's default behavior. Check the log with `tail /tmp/globe-switch.log`. A repeating `no Input Monitoring permission` line means step 2 above isn't done. When it's working, every press logs `globe down` and `switch A -> B`.
- **It switches and then switches straight back:** macOS's own Globe action is still on. Set "Press 🌐 key to" to **Do Nothing**.
- **Is it running?** `launchctl print gui/$(id -u)/com.local.globe-switch | grep state`
- **After rebuilding (re-running `./install.sh`):** macOS ties the permission to the exact build, so a rebuild can silently invalidate it. In Input Monitoring, remove GlobeSwitch with **–** and add it again.

## Uninstall

```bash
./uninstall.sh
```

This stops and removes GlobeSwitch.app and sets "Press 🌐 key to" back to **Change Input Source**.

## How it works

`main.swift` creates a `CGEventTap` for `flagsChanged` and `keyDown` events. When the fn/Globe key (keycode 63) goes down, it reads the enabled, selectable keyboard input sources with the Text Input Sources API (`TISCreateInputSourceList`) and selects the one after the current one with `TISSelectInputSource`. If a `keyDown` arrives while Globe is still held, it restores the previous source.

On startup it checks for Input Monitoring access with `CGPreflightListenEventAccess`. A listen-only tap can be created without permission but then receives nothing, so without access it asks for it, waits 15 seconds, and exits, and launchd restarts it. Every Globe press and switch is logged to `/tmp/globe-switch.log`.

## License

[MIT](LICENSE)
