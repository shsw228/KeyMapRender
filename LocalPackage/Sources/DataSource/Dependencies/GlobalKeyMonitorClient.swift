import Foundation

public struct GlobalKeyMonitorConfiguration: Sendable {
    public var targetKeyCode: UInt16
    public var longPressThreshold: TimeInterval

    public init(
        targetKeyCode: UInt16,
        longPressThreshold: TimeInterval
    ) {
        self.targetKeyCode = targetKeyCode
        self.longPressThreshold = longPressThreshold
    }
}

public struct GlobalKeyMonitorSession: Hashable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public enum GlobalKeyMonitorError: Error, Sendable {
    case message(String)
}

public struct GlobalKeyMonitorClient: DependencyClient {
    public var start: @Sendable (
        GlobalKeyMonitorConfiguration,
        @escaping @Sendable () -> Void,
        @escaping @Sendable () -> Void
    ) -> Result<GlobalKeyMonitorSession, GlobalKeyMonitorError>
    public var stop: @Sendable (GlobalKeyMonitorSession) -> Void

    public init(
        start: @escaping @Sendable (
            GlobalKeyMonitorConfiguration,
            @escaping @Sendable () -> Void,
            @escaping @Sendable () -> Void
        ) -> Result<GlobalKeyMonitorSession, GlobalKeyMonitorError>,
        stop: @escaping @Sendable (GlobalKeyMonitorSession) -> Void
    ) {
        self.start = start
        self.stop = stop
    }

    public static let liveValue = Self(
        start: { _, _, _ in .failure(.message("liveValue is not bound")) },
        stop: { _ in }
    )

    public static let testValue = Self(
        start: { _, _, _ in .failure(.message("testValue: start")) },
        stop: { _ in }
    )
}
