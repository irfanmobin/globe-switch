// globe-switch: switch keyboard input source the instant the Globe (fn) key goes down,
// no matter how long it's held. If another key is pressed while Globe is held
// (fn+Delete, fn+arrows, Globe+E, ...), the switch is undone so combos still work.
import Cocoa
import Carbon

let kFnKeyCode: Int64 = 63

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
    TISSelectInputSource(sources[(idx + 1) % sources.count])
}

let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

var tapRef: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = tapRef { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if type == .flagsChanged && event.getIntegerValueField(.keyboardEventKeycode) == kFnKeyCode {
        let down = event.flags.contains(.maskSecondaryFn)
        if down && !fnDown {
            switchToNext()
            switchedThisPress = true
        }
        if !down { switchedThisPress = false }
        fnDown = down
    } else if type == .keyDown && fnDown && switchedThisPress {
        // Globe used as a modifier (fn+Delete, fn+arrows, Globe+E...): undo the switch.
        if let prev = previous { TISSelectInputSource(prev) }
        switchedThisPress = false
    }
    return Unmanaged.passUnretained(event)
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
print("globe-switch running")
CFRunLoopRun()
