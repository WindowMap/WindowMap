import AppKit
import Logging

enum GestureDirection: String {
    case up, down
}

struct GestureConfig {
    let fingerCount: Int
    let direction: GestureDirection
}

func parseGestureConfig(_ value: String) -> GestureConfig? {
    let parts = value.lowercased().split(separator: "-").map(String.init)
    guard parts.count == 3, parts.last == "up" || parts.last == "down",
          parts[1] == "finger", let fingers = Int(parts[0]), (3...4).contains(fingers)
    else { return nil }
    return GestureConfig(fingerCount: fingers, direction: GestureDirection(rawValue: parts.last!)!)
}

private let log = Log(module: "TrackpadGesture")
private let minSwipeDistance: CGFloat = 0.04
private let maxWrongAxisDistance: CGFloat = 0.1

private class GestureState {
    let config: GestureConfig
    let onTrigger: () -> Void
    weak var handle: EventTapHandle?
    var startPositions: [String: NSPoint] = [:]
    var triggered = false
    var otherGestureActive = false
    var destroyed = false

    init(_ config: GestureConfig, _ onTrigger: @escaping () -> Void) {
        self.config = config; self.onTrigger = onTrigger
    }

    func reset() {
        startPositions.removeAll()
        triggered = false
        otherGestureActive = false
    }
}

func destroyGestureTap(_ handle: EventTapHandle) {
    if let ptr = handle.boxPtr {
        Unmanaged<GestureState>.fromOpaque(ptr).takeUnretainedValue().destroyed = true
    }
    handle.destroy()
}

func registerGestureTrigger(config: GestureConfig, onTrigger: @escaping () -> Void) -> EventTapHandle? {
    let handle = EventTapHandle()
    let state = GestureState(config, onTrigger)
    state.handle = handle
    let statePtr = Unmanaged.passRetained(state).toOpaque()

    let callback: CGEventTapCallBack = { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let state = Unmanaged<GestureState>.fromOpaque(userInfo).takeUnretainedValue()
        guard !state.destroyed else { return Unmanaged.passUnretained(event) }
        guard state.handle?.isEnabled == true else { return Unmanaged.passUnretained(event) }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.warning("gesture tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")) — re-enabling")
            if let tap = state.handle?.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let eventCopy = event.copy() else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async {
            guard state.handle?.isEnabled == true else { return }
            guard let nsEvent = NSEvent(cgEvent: eventCopy), nsEvent.type == .gesture else { return }

            let touches = nsEvent.allTouches()
            var active: [(id: String, pos: NSPoint)] = []
            for touch in touches where touch.phase == .began || touch.phase == .moved || touch.phase == .stationary {
                active.append(("\(touch.identity)", touch.normalizedPosition))
            }

            if active.isEmpty { state.reset(); return }
            if state.otherGestureActive || state.triggered { return }
            if active.count < state.config.fingerCount { return }
            if active.count > state.config.fingerCount { state.otherGestureActive = true; return }

            let activeIds = Set(active.map { $0.id })
            state.startPositions = state.startPositions.filter { activeIds.contains($0.key) }
            for t in active where state.startPositions[t.id] == nil {
                state.startPositions[t.id] = t.pos
            }

            guard state.startPositions.count >= state.config.fingerCount else { return }

            var totalDistance: CGFloat = 0
            var maxWrongAxis: CGFloat = 0
            for t in active {
                guard let start = state.startPositions[t.id] else { continue }
                totalDistance += t.pos.y - start.y
                maxWrongAxis = max(maxWrongAxis, abs(t.pos.x - start.x))
            }

            let avgDistance = totalDistance / CGFloat(active.count)
            let directionMatch: Bool
            switch state.config.direction {
            case .up:   directionMatch = avgDistance > minSwipeDistance
            case .down: directionMatch = avgDistance < -minSwipeDistance
            }

            if directionMatch && maxWrongAxis < maxWrongAxisDistance {
                state.triggered = true
                log.info("\(state.config.fingerCount)-finger \(state.config.direction) triggered")
                state.onTrigger()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    let eventMask: CGEventMask = 1 << 29
    let ready = DispatchSemaphore(value: 0)
    var tapCreated = false

    let thread = Thread {
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: statePtr
        ) else {
            log.error("failed to create gesture event tap")
            Unmanaged<GestureState>.fromOpaque(statePtr).release()
            ready.signal()
            return
        }

        handle.tap = tap
        handle.boxPtr = statePtr
        handle.runLoop = CFRunLoopGetCurrent()
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        handle.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        tapCreated = true
        ready.signal()
        CFRunLoopRun()

        while !state.destroyed {
            log.warning("gesture run loop exited — retrying in 2s")
            Thread.sleep(forTimeInterval: 2)
            guard !state.destroyed else { break }
            guard let newTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: statePtr
            ) else {
                log.debug("gesture tap retry failed — waiting")
                continue
            }
            handle.tap = newTap
            let newSrc = CFMachPortCreateRunLoopSource(nil, newTap, 0)
            handle.runLoopSource = newSrc
            handle.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), newSrc, .commonModes)
            log.info("gesture tap recovered")
            CFRunLoopRun()
        }
        log.info("gesture tap destroyed — recovery stopped")
    }
    thread.name = "windowmap.gesture"
    thread.qualityOfService = .userInteractive
    thread.start()

    ready.wait()
    return tapCreated ? handle : nil
}
