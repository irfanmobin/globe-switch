// globe-switch: switch keyboard input source the instant the Globe (fn) key goes down,
// no matter how long it's held. If another key is pressed while Globe is held
// (fn+Delete, fn+arrows, Globe+E, ...), the switch is undone so combos still work.
import Cocoa
import Carbon

let kFnKeyCode: Int64 = 63

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("[\(ts)] \(msg)\n".data(using: .utf8)!)
}

func selectableSources() -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceIsSelectCapable as String: true,
                  kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
    return list.filter { src in
        guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceType) else { return false }
        let type = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
        return type == (kTISTypeKeyboardLayout as String) || type == (kTISTypeKeyboardInputMode as String)
    }
}

func sourceID(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

var previous: TISInputSource?
var fnDown = false
var switchedThisPress = false

func switchToNext() {
    let sources = selectableSources()
    guard sources.count > 1 else { return }
    let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let idx = sources.firstIndex { sourceID($0) == sourceID(current) } ?? -1
    previous = current
    let next = sources[(idx + 1) % sources.count]
    let err = TISSelectInputSource(next)
    log("switch \(sourceID(current)) -> \(sourceID(next)) (status \(err))")
}

let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

var tapRef: CFMachPort?

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
            switchToNext()
            switchedThisPress = true
        }
        if !down { switchedThisPress = false }
        fnDown = down
    } else if type == .keyDown && fnDown && switchedThisPress {
        // Globe used as a modifier (fn+Delete, fn+arrows, Globe+E...): undo the switch.
        if let prev = previous { TISSelectInputSource(prev); log("combo key: reverted to \(sourceID(prev))") }
        switchedThisPress = false
    }
    return Unmanaged.passUnretained(event)
}

// A listen-only tap can be created without permission but then receives nothing,
// so check explicitly, ask macOS to prompt, and let launchd retry.
if !CGPreflightListenEventAccess() {
    _ = CGRequestListenEventAccess()
    log("no Input Monitoring permission. Enable GlobeSwitch in System Settings > Privacy & Security > Input Monitoring. Retrying in 15s.")
    sleep(15)
    exit(1)
}

tapRef = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                           eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil)
guard let tap = tapRef else {
    FileHandle.standardError.write("globe-switch: no event tap. Grant Input Monitoring in System Settings > Privacy & Security > Input Monitoring.\n".data(using: .utf8)!)
    _ = CGRequestListenEventAccess()
    sleep(10)   // avoid a tight launchd restart loop
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
log("globe-switch running; input monitoring access: \(CGPreflightListenEventAccess())")
CFRunLoopRun()
