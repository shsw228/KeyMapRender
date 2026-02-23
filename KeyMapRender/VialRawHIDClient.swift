import Foundation

struct VialRawHIDClient: DependencyClient {
    var probe: @Sendable (HIDKeyboardDevice) -> Result<VialProbeResult, VialProbeError>
    var readKeymap: @Sendable (HIDKeyboardDevice, Int, Int) -> Result<VialKeymapDump, VialProbeError>
    var inferMatrix: @Sendable (HIDKeyboardDevice) -> Result<VialMatrixInfo, VialProbeError>
    var readDefinition: @Sendable (HIDKeyboardDevice) -> Result<String, VialProbeError>
    var readSwitchMatrixState: @Sendable (HIDKeyboardDevice, Int, Int) -> Result<VialSwitchMatrixState, VialProbeError>

    public static let liveValue = Self(
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

    public static let testValue = Self(
        probe: { _ in
            .failure(.message("testValue: probe"))
        },
        readKeymap: { _, _, _ in
            .failure(.message("testValue: readKeymap"))
        },
        inferMatrix: { _ in
            .failure(.message("testValue: inferMatrix"))
        },
        readDefinition: { _ in
            .failure(.message("testValue: readDefinition"))
        },
        readSwitchMatrixState: { _, _, _ in
            .failure(.message("testValue: readSwitchMatrixState"))
        }
    )
}
