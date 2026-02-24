import Foundation

public struct HIDKeyboardClient: DependencyClient {
    public var listKeyboards: @Sendable () -> [HIDKeyboardDevice]

    public init(
        listKeyboards: @escaping @Sendable () -> [HIDKeyboardDevice]
    ) {
        self.listKeyboards = listKeyboards
    }

    public static let liveValue = Self(
        listKeyboards: {
            []
        }
    )

    public static let testValue = Self(
        listKeyboards: {
            []
        }
    )
}
