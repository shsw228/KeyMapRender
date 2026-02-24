import ApplicationServices
import Foundation

extension HIDKeyboardClient {
    public static let keyMapRenderLiveValue = Self(
        listKeyboards: {
            HIDKeyboardService.listKeyboards()
        }
    )
}

extension VialRawHIDClient {
    public static let keyMapRenderLiveValue = Self(
        probe: { device in
            VialRawHIDService.probe(device: device)
        },
        readKeymap: { device, rows, cols in
            VialRawHIDService.readKeymap(device: device, matrixRows: rows, matrixCols: cols)
        },
        inferMatrix: { device in
            VialRawHIDService.inferMatrix(device: device)
        },
        readDefinition: { device in
            VialRawHIDService.readDefinition(device: device)
        },
        readSwitchMatrixState: { device, rows, cols in
            VialRawHIDService.readSwitchMatrixState(device: device, matrixRows: rows, matrixCols: cols)
        }
    )
}

@MainActor
private final class HotplugMonitorRegistry {
    static let shared = HotplugMonitorRegistry()
    private let lock = NSLock()
    private var monitors: [UUID: HIDKeyboardHotplugMonitor] = [:]

    private init() {}

    func start(onChanged: @escaping @Sendable () -> Void) -> Result<HIDKeyboardHotplugSession, HIDKeyboardHotplugError> {
        let id = UUID()
        let monitor = HIDKeyboardHotplugMonitor {
            onChanged()
        }
        guard monitor.start() else {
            return .failure(.message("start failed"))
        }
        lock.lock()
        monitors[id] = monitor
        lock.unlock()
        return .success(HIDKeyboardHotplugSession(id: id))
    }

    func stop(_ session: HIDKeyboardHotplugSession) {
        lock.lock()
        let monitor = monitors.removeValue(forKey: session.id)
        lock.unlock()
        guard let monitor else { return }
        monitor.stop()
    }
}

extension HIDKeyboardHotplugClient {
    public static let keyMapRenderLiveValue = Self(
        start: { onChanged in
            MainActor.assumeIsolated {
                HotplugMonitorRegistry.shared.start(onChanged: onChanged)
            }
        },
        stop: { session in
            MainActor.assumeIsolated {
                HotplugMonitorRegistry.shared.stop(session)
            }
        }
    )
}

@MainActor
private final class GlobalKeyMonitorRegistry {
    static let shared = GlobalKeyMonitorRegistry()
    private let lock = NSLock()
    private var monitors: [UUID: GlobalKeyLongPressMonitor] = [:]

    private init() {}

    func start(
        _ configuration: GlobalKeyMonitorConfiguration,
        onLongPressStart: @escaping @Sendable () -> Void,
        onLongPressEnd: @escaping @Sendable () -> Void
    ) -> Result<GlobalKeyMonitorSession, GlobalKeyMonitorError> {
        let id = UUID()
        let monitor = GlobalKeyLongPressMonitor()
        monitor.targetKeyCode = CGKeyCode(configuration.targetKeyCode)
        monitor.longPressThreshold = configuration.longPressThreshold
        monitor.onLongPressStart = {
            onLongPressStart()
        }
        monitor.onLongPressEnd = {
            onLongPressEnd()
        }
        guard monitor.start() else {
            return .failure(.message("start failed"))
        }
        lock.lock()
        monitors[id] = monitor
        lock.unlock()
        return .success(GlobalKeyMonitorSession(id: id))
    }

    func stop(_ session: GlobalKeyMonitorSession) {
        lock.lock()
        let monitor = monitors.removeValue(forKey: session.id)
        lock.unlock()
        guard let monitor else { return }
        monitor.stop()
    }
}

extension GlobalKeyMonitorClient {
    public static let keyMapRenderLiveValue = Self(
        start: { configuration, onLongPressStart, onLongPressEnd in
            MainActor.assumeIsolated {
                GlobalKeyMonitorRegistry.shared.start(
                    configuration,
                    onLongPressStart: onLongPressStart,
                    onLongPressEnd: onLongPressEnd
                )
            }
        },
        stop: { session in
            MainActor.assumeIsolated {
                GlobalKeyMonitorRegistry.shared.stop(session)
            }
        }
    )
}
