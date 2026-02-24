import Foundation

public struct InputAccessStatus: Sendable {
    public let accessibilityTrusted: Bool
    public let inputMonitoringTrusted: Bool

    public init(accessibilityTrusted: Bool, inputMonitoringTrusted: Bool) {
        self.accessibilityTrusted = accessibilityTrusted
        self.inputMonitoringTrusted = inputMonitoringTrusted
    }
}

public struct InputAccessClient: DependencyClient {
    public var checkStatus: @Sendable (_ promptAccessibility: Bool, _ requestInputMonitoring: Bool) -> InputAccessStatus

    public init(
        checkStatus: @escaping @Sendable (_ promptAccessibility: Bool, _ requestInputMonitoring: Bool) -> InputAccessStatus
    ) {
        self.checkStatus = checkStatus
    }

    public static let liveValue = Self(
        checkStatus: { _, _ in .init(accessibilityTrusted: false, inputMonitoringTrusted: false) }
    )

    public static let testValue = Self(
        checkStatus: { _, _ in .init(accessibilityTrusted: false, inputMonitoringTrusted: false) }
    )
}
