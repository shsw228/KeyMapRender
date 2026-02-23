import Foundation
import DataSource

final class AppDependencies: Sendable {
    let hidKeyboardClient: HIDKeyboardClient
    let vialRawHIDClient: VialRawHIDClient

    init(
        hidKeyboardClient: HIDKeyboardClient = .keyMapRenderLiveValue,
        vialRawHIDClient: VialRawHIDClient = .keyMapRenderLiveValue
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

extension HIDKeyboardClient {
    static let keyMapRenderLiveValue = Self(
        listKeyboards: {
            HIDKeyboardService.listKeyboards()
        }
    )
}

extension VialRawHIDClient {
    static let keyMapRenderLiveValue = Self(
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
