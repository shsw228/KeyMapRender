import Foundation
import IOKit.hid

public final class HIDKeyboardHotplugMonitor {
    private let manager: IOHIDManager
    private let callback: @Sendable () -> Void
    private var isRunning = false
    public private(set) var lastOpenResult: IOReturn = kIOReturnSuccess

    public init(callback: @escaping @Sendable () -> Void) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.callback = callback
    }

    @discardableResult
    public func start() -> Bool {
        guard !isRunning else { return true }

        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        let keypadMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keypad
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [keyboardMatch, keypadMatch] as CFArray)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceChangedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceChangedCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        lastOpenResult = openResult
        guard openResult == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            return false
        }

        isRunning = true
        return true
    }

    public func stop() {
        guard isRunning else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = false
    }

    private func handleDeviceChanged() {
        callback()
    }

    private static let deviceChangedCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let monitor = Unmanaged<HIDKeyboardHotplugMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleDeviceChanged()
    }
}
