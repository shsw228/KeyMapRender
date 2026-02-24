import Foundation

public struct HIDKeyboardHotplugSession: Hashable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public enum HIDKeyboardHotplugError: Error, Sendable {
    case message(String)
}

public struct HIDKeyboardHotplugClient: DependencyClient {
    public var start: @Sendable (@escaping @Sendable () -> Void) -> Result<HIDKeyboardHotplugSession, HIDKeyboardHotplugError>
    public var stop: @Sendable (HIDKeyboardHotplugSession) -> Void

    public init(
        start: @escaping @Sendable (@escaping @Sendable () -> Void) -> Result<HIDKeyboardHotplugSession, HIDKeyboardHotplugError>,
        stop: @escaping @Sendable (HIDKeyboardHotplugSession) -> Void
    ) {
        self.start = start
        self.stop = stop
    }

    public static let liveValue = Self(
        start: { _ in .failure(.message("liveValue is not bound")) },
        stop: { _ in }
    )

    public static let testValue = Self(
        start: { _ in .failure(.message("testValue: start")) },
        stop: { _ in }
    )
}
