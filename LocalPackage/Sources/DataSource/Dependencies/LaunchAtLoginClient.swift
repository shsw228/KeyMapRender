import Foundation

public enum LaunchAtLoginError: Error, Sendable {
    case message(String)
}

public struct LaunchAtLoginClient: DependencyClient {
    public var status: @Sendable () -> Result<Bool, LaunchAtLoginError>
    public var setEnabled: @Sendable (Bool) -> Result<Bool, LaunchAtLoginError>

    public init(
        status: @escaping @Sendable () -> Result<Bool, LaunchAtLoginError>,
        setEnabled: @escaping @Sendable (Bool) -> Result<Bool, LaunchAtLoginError>
    ) {
        self.status = status
        self.setEnabled = setEnabled
    }

    public static let liveValue = Self(
        status: { .failure(.message("liveValue is not bound")) },
        setEnabled: { _ in .failure(.message("liveValue is not bound")) }
    )

    public static let testValue = Self(
        status: { .failure(.message("testValue: status")) },
        setEnabled: { _ in .failure(.message("testValue: setEnabled")) }
    )
}
