# globe-switch

**Make the 🌐 Globe (fn) key on a Mac switch keyboard languages instantly, every time.**

## The problem

On Mac keyboards, the Globe key (bottom-left, next to Control) can be set to change your input source (keyboard language). macOS only switches if you tap the key **quickly**. Hold it a moment too long and nothing happens when you let go. So a single press sometimes switches and sometimes doesn't, and you end up typing in the wrong language.

## What globe-switch does

globe-switch is a small background program (one Swift file, no dependencies) that:

- **Switches input source the moment the Globe key goes down**, however long you hold it.
- **Cycles through your enabled keyboard layouts and input methods** (e.g. U.S. ↔ Arabic, or English → French → Japanese).
- **Keeps Globe/fn shortcuts working.** If you press another key while holding Globe (fn+Delete, fn+←/→, Globe+E for emoji, Globe+F for full screen), the switch is undone, so shortcuts don't change your language.
- **Shows the language you switched to, right at your text cursor**: a small blue bubble with the language's letter (**A** for English and other Latin-script languages, **ع** for Arabic, **א** for Hebrew, **Б** for Russian, and so on). It appears just below the caret and fades out after about a second.
- Starts automatically at login through a LaunchAgent, and **keeps working after sleep**: close the lid, open it, and the Globe key works straight away.

### Why its own popup?

macOS draws its own language popup at the cursor, but after a Globe press it sometimes shows the *previous* language, which is exactly what you don't want to see. globe-switch turns that popup off and shows its own. Its bubble is drawn from the input source it just selected, so it is never out of date.

It only listens to keyboard events (a *listen-only* event tap). It never changes, blocks, records, or sends your keystrokes anywhere. To find the text cursor it reads only the cursor's position from the focused text field. It never reads your text.

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
2. Sets **System Settings → Keyboard → "Press 🌐 key to"** to **Do Nothing**, so macOS doesn't switch a second time and cancel globe-switch out. It then restarts macOS's `TextInputSwitcher` process, which caches that setting.
3. Turns off macOS's own language popup at the cursor (`TSMLanguageIndicatorEnabled = false`), since globe-switch shows its own. It then restarts `CursorUIViewService`, the process that draws that popup.
4. Installs and starts a LaunchAgent (`~/Library/LaunchAgents/com.local.globe-switch.plist`).

### Grant permissions

globe-switch needs two permissions. Add GlobeSwitch to each list in **System Settings → Privacy & Security**:

| Permission | What it's for | Without it |
|---|---|---|
| **Input Monitoring** (required) | Seeing the Globe key | globe-switch receives nothing, and the Globe key keeps macOS's default behavior |
| **Accessibility** (recommended) | Finding the text cursor so the bubble can appear there | Switching still works, but no bubble is shown |

For each one:
1. Open **System Settings → Privacy & Security → Input Monitoring** (then **Accessibility**).
2. Click **+**, press ⌘⇧G, enter `~/Applications/GlobeSwitch.app`, click Open, and make sure its switch is **on**. (If macOS shows a prompt for GlobeSwitch, you can approve that instead.)
3. Wait about 15 seconds. globe-switch checks for Input Monitoring every 15 seconds and starts on its own once it has it. Accessibility takes effect on the next Globe press.

Also check that **System Settings → Keyboard → "Press 🌐 key to"** reads **Do Nothing**. If it doesn't, set it by hand (or log out and back in).

> **Every time you re-run `./install.sh`, re-grant both permissions.** The app is ad-hoc signed, and macOS ties each permission to the exact build, so a rebuild silently invalidates them, even though GlobeSwitch still *looks* enabled in the list. Select GlobeSwitch, remove it with **–**, then add it again with **+**, in both Input Monitoring and Accessibility.

## Usage

Press the Globe key. That's it: tap or hold, your language switches straight away and a blue bubble at your cursor shows the new language.

| You do | Result |
|---|---|
| Tap Globe | Switches to the next input source and shows the bubble |
| Hold Globe, then release | Switches as soon as it goes down; releasing does nothing |
| Hold Globe + another key (fn+Delete, Globe+E, …) | The shortcut runs; your input source stays the same |

## Troubleshooting

- **Short taps switch but long presses don't:** globe-switch isn't running with permission, so you're seeing macOS's default behavior. Check the log with `tail /tmp/globe-switch.log`. A repeating `no Input Monitoring permission` line means step 2 above isn't done. When it's working, every press logs `globe down` and `switch A -> B`.
- **Quick taps don't stick, or the language popup shows the wrong language:** macOS's own Globe action is still on. It switches back as you release a quick tap, and its popup shows *its* choice. globe-switch detects this and switches back again within about 1 second (you'll see `re-applied` lines in the log), but the popup will still be wrong. To fix it for real, make sure "Press 🌐 key to" is **Do Nothing**, then restart the process that caches that setting:
  ```bash
  killall -9 TextInputSwitcher   # macOS relaunches it automatically
  ```
- **No bubble appears:** check the log. Each press that can't show a bubble logs a `no popup: <reason>` line. The usual reason is missing **Accessibility** permission (see above, and re-grant it after any rebuild). The first press in a browser, Electron app, or Office app can miss while that app switches its accessibility on; later presses work. A few apps don't report their cursor position at all. In those, globe-switch skips the bubble rather than showing it in the wrong place, and logs a `focused element: …` line describing what the app does offer (useful in a bug report).
- **VS Code asks whether you use a screen reader:** that's VS Code noticing globe-switch asking it for cursor positions. Answer no, or set `"editor.accessibilitySupport": "off"`. The bubble still works.
- **macOS's own popup still appears next to the bubble:** apps read the setting that hides it when they launch. Quit the app with ⌘Q and reopen it, or log out and back in once.
- **Stopped working after sleep or unlock:** this should fix itself within a few seconds. The log shows what happened: look for `system going to sleep`, then `system woke` / `screen unlocked` followed by `event tap rebuilt`. If those lines are there but the key still doesn't work, restart it with `launchctl kickstart -k gui/$(id -u)/com.local.globe-switch` and open an issue with the log.
- **Is it running?** `launchctl print gui/$(id -u)/com.local.globe-switch | grep state`
- **Stopped working after re-running `./install.sh`:** macOS ties permissions to the exact build, so a rebuild silently invalidates them. In both Input Monitoring and Accessibility, remove GlobeSwitch with **–** and add it again.

## Uninstall

```bash
./uninstall.sh
```

This stops and removes GlobeSwitch.app, sets "Press 🌐 key to" back to **Change Input Source**, and turns macOS's own language popup back on. You can then remove GlobeSwitch from Input Monitoring and Accessibility in System Settings.

## How it works

`main.swift` creates a `CGEventTap` for `flagsChanged` and `keyDown` events. When the fn/Globe key (keycode 63) goes down, it reads the enabled, selectable keyboard input sources with the Text Input Sources API (`TISCreateInputSourceList`) and selects the one after the current one with `TISSelectInputSource`. If a `keyDown` arrives while Globe is still held, it restores the previous source.

On startup it checks for Input Monitoring access with `CGPreflightListenEventAccess`. A listen-only tap can be created without permission but then receives nothing, so without access it asks for it, waits 15 seconds, and exits, and launchd restarts it. Every Globe press and switch is logged to `/tmp/globe-switch.log`.

**The bubble:** after each switch, globe-switch asks the focused app (through the Accessibility API) for the text caret's position: `kAXSelectedTextRangeAttribute`, then `kAXBoundsForRangeParameterizedAttribute`. Some apps, such as Terminal, return an empty box for the caret. For those it uses the position of the character at or just before the caret instead. If it still can't find the caret, it shows nothing; the bubble never appears at the mouse pointer. Apps differ in how much they tell accessibility clients, so globe-switch tries, in order: the caret's own bounds; the character at or before the caret; WebKit-style text markers (`AXSelectedTextMarkerRange` + `AXBoundsForTextMarkerRange`, used by Safari, Mail, Pages, Word, and others); and, for single-line fields like a browser's address bar, the left edge of the field. If the system-wide focused element isn't available it asks the frontmost app directly.

Chromium, Electron (VS Code, Slack, …) and Firefox keep their accessibility tree off until an assistive app asks for it. globe-switch asks each app once as it comes to the front, with `AXManualAccessibility` (no side effects), or `AXEnhancedUserInterface` for browsers that don't support it. If an app still can't report its caret on a Globe press, globe-switch also sets `AXEnhancedUserInterface` on that app only (Microsoft Office, for example, needs it) and retries 0.35 seconds later. It isn't set on every app because it can make window animations slower in some apps.

The bubble is a borderless, non-activating `NSPanel`, so it never takes focus. It shows the first letter of the input source's script (from `kTISPropertyInputSourceLanguages`), centered on the letter's actual shape, and fades out after about 0.9 seconds.

**Surviving sleep and wake:** after sleep, a screen lock, or a user switch, macOS can disable or invalidate an event tap without sending the usual `tapDisabledByTimeout` / `tapDisabledByUserInput` event, so a program looks alive but receives nothing. globe-switch therefore:
- rebuilds its event tap whenever the system or display wakes, the user session becomes active, or the screen is unlocked (`NSWorkspace.didWakeNotification`, `screensDidWakeNotification`, `sessionDidBecomeActiveNotification`, `com.apple.screenIsUnlocked`), and clears any half-finished Globe press;
- checks the tap every 3 seconds and re-enables or rebuilds it if it was silently disabled or invalidated;
- exits if Input Monitoring permission disappears or the tap can't be rebuilt after 5 tries, so launchd (`KeepAlive`, `ProcessType` Interactive) restarts it cleanly.

Two safety nets:
- **Switch-back guard:** for 1 second after a Globe press or release, it watches for input-source change notifications (`kTISNotifySelectedKeyboardInputSourceChanged`). If something else (usually macOS's own Globe action) switches away from the source globe-switch chose, it selects that source again.
- **Debounce:** a Globe press within 40 ms of the previous release is ignored as switch bounce.

## License

[MIT](LICENSE)
