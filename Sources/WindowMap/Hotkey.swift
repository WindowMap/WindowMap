import AppKit
import Logging

private let log = Log(module: "Hotkey")

class EventTapHandle {
    var tap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var runLoop: CFRunLoop?
    var boxPtr: UnsafeMutableRawPointer?
    var isEnabled = true

    func disable() { isEnabled = false }
    func enable() { isEnabled = true }

    func confirmIfModifierReleased() {
        guard let ptr = boxPtr else { return }
        let box = Unmanaged<TapBox>.fromOpaque(ptr).takeUnretainedValue()
        guard box.activeModifierMask != [] else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if !flags.contains(box.activeModifierMask) {
            box.modifierWasDown = false
            if let onUp = box.onModifierUp {
                DispatchQueue.main.async { onUp() }
            }
        }
    }

    func destroy() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        let rl = runLoop ?? CFRunLoopGetMain()
        if let src = runLoopSource { CFRunLoopRemoveSource(rl, src, .commonModes) }
        if let rl = runLoop, rl !== CFRunLoopGetMain() { CFRunLoopStop(rl) }
        if let ptr = boxPtr { Unmanaged<AnyObject>.fromOpaque(ptr).release() }
        tap = nil; runLoopSource = nil; runLoop = nil; boxPtr = nil
    }

    deinit { destroy() }
}

private class TapBox {
    let keys: [(keyCode: Int64, modifierMask: CGEventFlags)]
    let onKeyDown: () -> Void
    var onModifierUp: (() -> Void)?
    weak var handle: EventTapHandle?
    var modifierWasDown = false
    var activeModifierMask: CGEventFlags = []

    init(_ keys: [(Int64, CGEventFlags)], _ down: @escaping () -> Void) {
        self.keys = keys
        self.onKeyDown = down
    }
}

func registerHotkey(
    keys: [(keyCode: Int64, modifierMask: CGEventFlags)],
    onKeyDown: @escaping () -> Void,
    onModifierUp: (() -> Void)? = nil
) -> EventTapHandle? {
    let handle = EventTapHandle()

    let box = TapBox(keys, onKeyDown)
    box.onModifierUp = onModifierUp
    box.handle = handle
    let boxPtr = Unmanaged.passRetained(box).toOpaque()

    let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    let callback: CGEventTapCallBack = { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let box = Unmanaged<TapBox>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = box.handle?.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            if let matched = box.keys.first(where: {
                event.getIntegerValueField(.keyboardEventKeycode) == $0.keyCode
                && event.flags.contains($0.modifierMask)
            }) {
                if box.handle?.isEnabled == true {
                    box.modifierWasDown = true
                    box.activeModifierMask = matched.modifierMask
                }
                DispatchQueue.main.async { box.onKeyDown() }
                return nil
            }
        }

        if type == .flagsChanged {
            if box.modifierWasDown && !event.flags.contains(box.activeModifierMask) {
                box.modifierWasDown = false
                if let onUp = box.onModifierUp {
                    DispatchQueue.main.async { onUp() }
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: callback,
        userInfo: boxPtr
    ) else {
        log.error("failed to create event tap")
        Unmanaged<TapBox>.fromOpaque(boxPtr).release()
        return nil
    }

    handle.tap = tap
    handle.boxPtr = boxPtr
    let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
    handle.runLoopSource = src
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    return handle
}
