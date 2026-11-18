// globe-switch: switch keyboard input source the instant the Globe (fn) key goes down,
// no matter how long it's held, and show our own language popup at the text cursor.
// If another key is pressed while Globe is held (fn+Delete, fn+arrows, Globe+E, ...),
// the switch is undone so combos still work.
import Cocoa
import CoreText
import Carbon

let kFnKeyCode: Int64 = 63

func log(_ msg: String) {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    FileHandle.standardError.write("[\(f.string(from: Date()))] \(msg)\n".data(using: .utf8)!)
}

// MARK: - Input sources

func selectableSources() -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceIsSelectCapable as String: true,
                  kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
    return list.filter { src in
        let type = stringProperty(src, kTISPropertyInputSourceType)
        return type == (kTISTypeKeyboardLayout as String) || type == (kTISTypeKeyboardInputMode as String)
    }
}

func stringProperty(_ s: TISInputSource, _ key: CFString) -> String {
    guard let p = TISGetInputSourceProperty(s, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

func sourceID(_ s: TISInputSource) -> String { stringProperty(s, kTISPropertyInputSourceID) }

/// One-character label for the popup, mirroring the letters the menu bar shows
/// (macOS doesn't expose those icons: TIS only returns a generic keyboard picture).
/// Unknown languages fall back to their two-letter code.
let scriptLetters: [String: String] = [
    "ar": "ع", "fa": "ف", "ur": "ع", "he": "א",
    "ru": "Б", "uk": "Б", "el": "Ω", "hi": "अ",
]
let latinLanguages: Set<String> = ["en", "fr", "de", "es", "it", "pt", "nl", "sv", "da", "no", "nb", "fi",
                                   "pl", "cs", "tr", "id", "ms", "vi", "ro", "hu", "hr", "sk", "sl", "ca"]

func sourceGlyph(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceLanguages),
          let langs = Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as? [String],
          let first = langs.first else { return "?" }
    let code = String(first.prefix(2)).lowercased()
    if let letter = scriptLetters[code] { return letter }
    if latinLanguages.contains(code) { return "A" }
    return code.uppercased()
}

// MARK: - Our language popup
// macOS's own popup is disabled (TSMLanguageIndicatorEnabled = false) because it
// sometimes shows the previous language after a programmatic switch. Ours is drawn
// from the source we just selected, so it can't be stale.

/// Draws one glyph centered on its actual ink bounds (not the font's line box),
/// so "A" and "ع" both sit dead-center in the circle.
final class GlyphView: NSView {
    static let side: CGFloat = 22
    var glyph = "" { didSet { needsDisplay = true } }
    private let font = NSFont.systemFont(ofSize: 12, weight: .bold)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, !glyph.isEmpty else { return }
        let str = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor.white])
        let line = CTLineCreateWithAttributedString(str)
        ctx.textPosition = .zero   // image bounds are relative to the current text position
        let ink = CTLineGetImageBounds(line, ctx)
        ctx.textPosition = CGPoint(x: bounds.midX - ink.midX, y: bounds.midY - ink.midY)
        CTLineDraw(line, ctx)
    }
}

final class LanguagePopup {
    private let panel: NSPanel
    private let glyphView = GlyphView()
    private var hideWork: DispatchWorkItem?

    init() {
        let side = GlyphView.side
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        glyphView.wantsLayer = true
        glyphView.layer?.backgroundColor = NSColor.systemBlue.cgColor
        glyphView.layer?.cornerRadius = side / 2
        glyphView.layer?.masksToBounds = true
        panel.contentView = glyphView
    }

    func show(_ source: TISInputSource) {
        glyphView.glyph = sourceGlyph(source)
        let size = NSSize(width: GlyphView.side, height: GlyphView.side)

        // Only show at the text caret; if we can't find it, show nothing.
        guard let anchor = caretAnchor() else { hide(); return }
        var origin = NSPoint(x: anchor.x, y: anchor.y - size.height - 3)
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            if origin.y < vf.minY { origin.y = anchor.y + 26 }   // no room below: go above
            origin.x = min(max(origin.x, vf.minX + 4), vf.maxX - size.width - 4)
            origin.y = min(max(origin.y, vf.minY + 4), vf.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.panel.alphaValue == 0 { self?.panel.orderOut(nil) }
        })
    }

    /// Bottom-left of the text caret in Cocoa screen coordinates, or nil if the
    /// focused app doesn't expose it through Accessibility.
    private func caretAnchor() -> NSPoint? {
        guard let caret = caretRect() else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: caret.minX, y: primaryHeight - caret.maxY)
    }

    private func caretRect() -> CGRect? {
        func fail(_ why: String) -> CGRect? { log("  no popup: \(why)"); return nil }
        guard AXIsProcessTrusted() else {
            return fail("no Accessibility permission (System Settings > Privacy & Security > Accessibility)")
        }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)   // never hang on an unresponsive app
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else {
            return fail("\(app) has no focused text element")
        }
        let element = f as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.05)
        var rangeValue: CFTypeRef?
        var sel = CFRange(location: 0, length: 0)
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rv = rangeValue, CFGetTypeID(rv) == AXValueGetTypeID(),
              AXValueGetValue(rv as! AXValue, .cfRange, &sel) else {
            return fail("\(app) doesn't report a text cursor")
        }

        func bounds(_ r: CFRange) -> CGRect? {
            var r = r
            guard let axRange = AXValueCreate(.cfRange, &r) else { return nil }
            var b: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                             axRange, &b) == .success,
                  let bv = b, CFGetTypeID(bv) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(bv as! AXValue, .cgRect, &rect),
                  rect.height > 0, rect.height < 200, rect.origin.x > -10_000, rect.origin.y > -10_000 else { return nil }
            return rect
        }

        // The caret itself. Some apps (e.g. Terminal) return an empty box for a
        // zero-length range, so fall back to the character at the caret, then the
        // character just before it (the caret sits at its right edge).
        if let r = bounds(sel) { return r }
        if sel.length == 0 {
            if let r = bounds(CFRange(location: sel.location, length: 1)) {
                return CGRect(x: r.minX, y: r.minY, width: 0, height: r.height)
            }
            if sel.location > 0, let r = bounds(CFRange(location: sel.location - 1, length: 1)) {
                return CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height)
            }
        }
        return fail("\(app) doesn't report where its text cursor is")
    }
}

// MARK: - Globe key handling

var popup: LanguagePopup!
var previous: TISInputSource?
var fnDown = false
var switchedThisPress = false

// Ignore a Globe press that comes this soon after the last release (switch bounce).
let debounceInterval: TimeInterval = 0.04
var lastUp = Date.distantPast

// If macOS's own Globe-key action is still active (the "Press 🌐 key to" setting
// hasn't taken effect), it switches back on a quick tap's release, cancelling our
// switch. For this long after a Globe press/release, undo any switch away from ours.
let guardInterval: TimeInterval = 1.0
var target: TISInputSource?
var guardUntil = Date.distantPast

func switchToNext() {
    let sources = selectableSources()
    guard sources.count > 1 else { return }
    let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let idx = sources.firstIndex { sourceID($0) == sourceID(current) } ?? -1
    let next = sources[(idx + 1) % sources.count]
    previous = current
    target = next
    guardUntil = Date().addingTimeInterval(guardInterval)
    let err = TISSelectInputSource(next)
    popup.show(next)
    log("switch \(sourceID(current)) -> \(sourceID(next)) (status \(err))")
}

func inputSourceChanged() {
    guard let t = target, Date() < guardUntil else { return }
    let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    if sourceID(current) != sourceID(t) {
        TISSelectInputSource(t)
        log("macOS switched to \(sourceID(current)) right after Globe; re-applied \(sourceID(t))")
    }
}

let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
var tapRef: CFMachPort?
var tapSource: CFRunLoopSource?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        log("tap disabled (\(type.rawValue)), re-enabling")
        if let t = tapRef { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if type == .flagsChanged && event.getIntegerValueField(.keyboardEventKeycode) == kFnKeyCode {
        let down = event.flags.contains(.maskSecondaryFn)
        log("globe \(down ? "down" : "up")")
        if down && !fnDown {
            if Date().timeIntervalSince(lastUp) < debounceInterval {
                log("ignored bounce (\(Int(Date().timeIntervalSince(lastUp) * 1000)) ms after release)")
            } else {
                switchToNext()
                switchedThisPress = true
            }
        }
        if !down {
            lastUp = Date()
            if target != nil { guardUntil = lastUp.addingTimeInterval(guardInterval) }
            switchedThisPress = false
        }
        fnDown = down
    } else if type == .keyDown && fnDown {
        // Globe used as a modifier (fn+Delete, fn+arrows, Globe+E...): undo the switch.
        if switchedThisPress {
            target = nil
            popup.hide()
            if let prev = previous { TISSelectInputSource(prev); log("combo key: reverted to \(sourceID(prev))") }
        }
        switchedThisPress = false
    }
    return Unmanaged.passUnretained(event)
}

// MARK: - Event tap lifecycle (survive sleep/wake)
// After sleep, screen lock, or a user switch, macOS can leave an event tap disabled
// or dead without sending tapDisabledBy*, so the app looks alive but hears nothing.
// So: rebuild the tap on every wake/unlock, and check it every few seconds.

@discardableResult
func installTap() -> Bool {
    if let old = tapRef {
        CGEvent.tapEnable(tap: old, enable: false)
        if let src = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        CFMachPortInvalidate(old)
        tapRef = nil; tapSource = nil
    }
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                      eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil)
    else { return false }
    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    tapRef = tap; tapSource = src
    return true
}

var tapFailures = 0

/// Recreate the tap; if that keeps failing, exit so launchd starts a fresh process.
func rebuildTap(_ reason: String) {
    // A Globe release may have been lost while asleep; don't let stale state eat the next press.
    fnDown = false; switchedThisPress = false; target = nil
    if installTap() {
        tapFailures = 0
        log("event tap rebuilt (\(reason))")
    } else {
        tapFailures += 1
        log("could not rebuild event tap (\(reason)), attempt \(tapFailures)")
        if tapFailures >= 5 { log("giving up; exiting so launchd restarts globe-switch"); exit(1) }
    }
}

func checkTapHealth() {
    if !CGPreflightListenEventAccess() {
        // Permission revoked (or invalidated by a rebuild): restart into the permission-wait loop.
        log("lost Input Monitoring permission; exiting so launchd restarts globe-switch")
        exit(1)
    }
    guard let tap = tapRef, CFMachPortIsValid(tap) else { rebuildTap("tap was invalid"); return }
    if !CGEvent.tapIsEnabled(tap: tap) {
        CGEvent.tapEnable(tap: tap, enable: true)
        log("event tap was silently disabled; re-enabled")
    }
}

func watchSleepWake() {
    let ws = NSWorkspace.shared.notificationCenter
    ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in log("system going to sleep") }
    let rebuildOn: [(Notification.Name, String)] = [
        (NSWorkspace.didWakeNotification, "system woke"),
        (NSWorkspace.screensDidWakeNotification, "display woke"),
        (NSWorkspace.sessionDidBecomeActiveNotification, "user session active"),
    ]
    for (name, reason) in rebuildOn {
        ws.addObserver(forName: name, object: nil, queue: .main) { _ in
            log(reason)
            rebuildTap(reason)
            // The window server can still be settling right after wake; check again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { checkTapHealth() }
        }
    }
    DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
        log("screen unlocked")
        rebuildTap("screen unlocked")
    }
    Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in checkTapHealth() }
}

// MARK: - Startup

// A listen-only tap can be created without permission but then receives nothing,
// so check explicitly, ask macOS to prompt, and let launchd retry.
if !CGPreflightListenEventAccess() {
    _ = CGRequestListenEventAccess()
    log("no Input Monitoring permission. Enable GlobeSwitch in System Settings > Privacy & Security > Input Monitoring. Retrying in 15s.")
    sleep(15)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, never steals focus
popup = LanguagePopup()

guard installTap() else {
    log("could not create event tap; retrying in 10s")
    sleep(10)   // avoid a tight launchd restart loop
    exit(1)
}
DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: .main) { _ in inputSourceChanged() }

// Accessibility is optional: it lets the popup appear at the text caret instead of
// the mouse pointer. Prompt once if it's missing.
if !AXIsProcessTrusted() {
    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
}
watchSleepWake()
// Opt out of App Nap so event handling and the popup stay prompt in the background.
let appNapActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                           reason: "Respond to the Globe key immediately")
log("globe-switch running; input monitoring: \(CGPreflightListenEventAccess()), accessibility (caret popup): \(AXIsProcessTrusted())")
app.run()
