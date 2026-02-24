import Testing

@testable import DataSource
@testable import Model

struct ActiveLayerTrackingServiceTests {
    private let sut = ActiveLayerTrackingService()

    @Test
    func deriveTrackedLayer_resolvesLTKey() {
        let dump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 4,
            matrixRows: 1,
            matrixCols: 1,
            keycodes: [
                [[0x412C]], // LT(1, KC_SPACE)
                [[0x0001]],
                [[0x0001]],
                [[0x0001]],
            ],
            layoutKeymapRows: nil,
            layoutLabels: nil,
            layoutOptions: nil,
            backend: "python"
        )
        let layer = sut.deriveTrackedLayer(from: [[true]], dump: dump, baseLayer: 0)
        #expect(layer == 1)
    }

    @Test
    func deriveTrackedLayer_resolvesFnCompositeLayer() {
        let dump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 4,
            matrixRows: 1,
            matrixCols: 2,
            keycodes: [
                [[0x5F10, 0x5F11]],
                [[0x0001, 0x0001]],
                [[0x0001, 0x0001]],
                [[0x0001, 0x0001]],
            ],
            layoutKeymapRows: nil,
            layoutLabels: nil,
            layoutOptions: nil,
            backend: "python"
        )
        let layer = sut.deriveTrackedLayer(from: [[true, true]], dump: dump, baseLayer: 0)
        #expect(layer == 3)
    }
}
