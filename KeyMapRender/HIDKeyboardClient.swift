import Foundation

struct HIDKeyboardClient: DependencyClient {
    var listKeyboards: @Sendable () -> [HIDKeyboardDevice]

    public static let liveValue = Self(
        listKeyboards: {
            HIDKeyboardService.listKeyboards()
        }
    )

    public static let testValue = Self(
        listKeyboards: {
            []
        }
    )
}
