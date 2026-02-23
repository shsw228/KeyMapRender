import AppKit

final class GlobalKeyLongPressMonitor {
    var targetKeyCode: CGKeyCode = 49
    var longPressThreshold: TimeInterval = 0.45
    var onLongPressStart: (() -> Void)?
    var onLongPressEnd: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isTargetPressed = false
    private var isLongPressActive = false
    private var workItem: DispatchWorkItem?

    func start() -> Bool {
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalKeyLongPressMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        workItem?.cancel()
        workItem = nil
        isTargetPressed = false
        isLongPressActive = false

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout, let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged, let mask = modifierMask(for: keyCode) {
            let pressed = event.flags.contains(mask)
            if pressed {
                if !isTargetPressed {
                    beginPress()
                }
            } else {
                endPress()
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
            if isRepeat || isTargetPressed {
                return Unmanaged.passUnretained(event)
            }
            beginPress()
        } else {
            endPress()
        }
        return Unmanaged.passUnretained(event)
    }

    private func beginPress() {
        isTargetPressed = true
        workItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isTargetPressed else { return }
            self.isLongPressActive = true
            self.onLongPressStart?()
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold, execute: item)
    }

    private func endPress() {
        isTargetPressed = false
        workItem?.cancel()
        workItem = nil

        if isLongPressActive {
            isLongPressActive = false
            onLongPressEnd?()
        }
    }

    private func modifierMask(for keyCode: CGKeyCode) -> CGEventFlags? {
        switch keyCode {
        case 56, 60:
            return .maskShift
        case 59, 62:
            return .maskControl
        case 58, 61:
            return .maskAlternate
        case 55, 54:
            return .maskCommand
        case 63:
            return .maskSecondaryFn
        case 57:
            return .maskAlphaShift
        default:
            return nil
        }
    }
}
