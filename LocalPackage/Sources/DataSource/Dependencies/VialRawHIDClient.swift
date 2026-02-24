import Foundation

public struct VialRawHIDClient: DependencyClient {
    public var probe: @Sendable (HIDKeyboardDevice) -> Result<VialProbeResult, VialProbeError>
    public var readKeymap: @Sendable (HIDKeyboardDevice, Int, Int) -> Result<VialKeymapDump, VialProbeError>
    public var inferMatrix: @Sendable (HIDKeyboardDevice) -> Result<VialMatrixInfo, VialProbeError>
    public var readDefinition: @Sendable (HIDKeyboardDevice) -> Result<String, VialProbeError>
    public var readSwitchMatrixState: @Sendable (HIDKeyboardDevice, Int, Int) -> Result<VialSwitchMatrixState, VialProbeError>

    public init(
        probe: @escaping @Sendable (HIDKeyboardDevice) -> Result<VialProbeResult, VialProbeError>,
        readKeymap: @escaping @Sendable (HIDKeyboardDevice, Int, Int) -> Result<VialKeymapDump, VialProbeError>,
        inferMatrix: @escaping @Sendable (HIDKeyboardDevice) -> Result<VialMatrixInfo, VialProbeError>,
        readDefinition: @escaping @Sendable (HIDKeyboardDevice) -> Result<String, VialProbeError>,
        readSwitchMatrixState: @escaping @Sendable (HIDKeyboardDevice, Int, Int) -> Result<VialSwitchMatrixState, VialProbeError>
    ) {
        self.probe = probe
        self.readKeymap = readKeymap
        self.inferMatrix = inferMatrix
        self.readDefinition = readDefinition
        self.readSwitchMatrixState = readSwitchMatrixState
    }

    public static let liveValue = Self(
        probe: { _ in .failure(.message("liveValue is not bound")) },
        readKeymap: { _, _, _ in .failure(.message("liveValue is not bound")) },
        inferMatrix: { _ in .failure(.message("liveValue is not bound")) },
        readDefinition: { _ in .failure(.message("liveValue is not bound")) },
        readSwitchMatrixState: { _, _, _ in .failure(.message("liveValue is not bound")) }
    )

    public static let testValue = Self(
        probe: { _ in .failure(.message("testValue: probe")) },
        readKeymap: { _, _, _ in .failure(.message("testValue: readKeymap")) },
        inferMatrix: { _ in .failure(.message("testValue: inferMatrix")) },
        readDefinition: { _ in .failure(.message("testValue: readDefinition")) },
        readSwitchMatrixState: { _, _, _ in .failure(.message("testValue: readSwitchMatrixState")) }
    )
}
