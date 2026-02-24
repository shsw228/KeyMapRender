import Foundation

public struct ClipboardClient: DependencyClient {
    public var copyString: @Sendable (String) -> Void

    public init(copyString: @escaping @Sendable (String) -> Void) {
        self.copyString = copyString
    }

    public static let liveValue = Self(copyString: { _ in })
    public static let testValue = Self(copyString: { _ in })
}
