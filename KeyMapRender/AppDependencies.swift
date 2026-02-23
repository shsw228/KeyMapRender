import Foundation

final class AppDependencies: Sendable {
    let hidKeyboardClient: HIDKeyboardClient
    let vialRawHIDClient: VialRawHIDClient

    init(
        hidKeyboardClient: HIDKeyboardClient = .liveValue,
        vialRawHIDClient: VialRawHIDClient = .liveValue
    ) {
        self.hidKeyboardClient = hidKeyboardClient
        self.vialRawHIDClient = vialRawHIDClient
    }

    static let shared = AppDependencies()

    static func testDependencies(
        hidKeyboardClient: HIDKeyboardClient = .testValue,
        vialRawHIDClient: VialRawHIDClient = .testValue
    ) -> AppDependencies {
        AppDependencies(
            hidKeyboardClient: hidKeyboardClient,
            vialRawHIDClient: vialRawHIDClient
        )
    }
}
