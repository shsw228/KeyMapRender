import Testing

@testable import DataSource
@testable import Model

struct KeymapLayerRenderingServiceTests {
    @Test
    func render_buildsMatrixLayoutAndPreviewWhenPhysicalLayoutIsMissing() {
        let dump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 1,
            matrixRows: 2,
            matrixCols: 2,
            keycodes: [[[0x0029, 0x001E], [0x001F, 0x0020]]],
            layoutKeymapRows: nil,
            layoutLabels: nil,
            layoutOptions: nil,
            backend: "python"
        )
        let sut = KeymapLayerRenderingService()

        let result = sut.render(
            dump: dump,
            requestedLayer: 0,
            selectedLayoutChoices: [],
            overlayName: "TestBoard"
        )

        #expect(result.layout.name == "TestBoard L0")
        #expect(result.layout.rows.count == 2)
        #expect(result.layout.rows[0][0].label == "Esc")
        #expect(result.keymapPreviewText.contains("L0 R0:"))
        #expect(result.diagnosticMessages.isEmpty)
    }

    @Test
    func render_acceptsPhysicalLayoutChoices() {
        let dump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 1,
            matrixRows: 1,
            matrixCols: 2,
            keycodes: [[[0x0029, 0x002A]]],
            layoutKeymapRows: [[
                "0,0",
                "0,1,0,0",
                "0,1,0,1"
            ]],
            layoutLabels: [["Split", "Off", "On"]],
            layoutOptions: 0,
            backend: "python"
        )
        let sut = KeymapLayerRenderingService()

        let offResult = sut.render(
            dump: dump,
            requestedLayer: 0,
            selectedLayoutChoices: [
                VialLayoutChoiceValue(id: 0, title: "Split", options: ["Off", "On"], selected: 0)
            ],
            overlayName: "TestBoard"
        )
        let onResult = sut.render(
            dump: dump,
            requestedLayer: 0,
            selectedLayoutChoices: [
                VialLayoutChoiceValue(id: 0, title: "Split", options: ["Off", "On"], selected: 1)
            ],
            overlayName: "TestBoard"
        )

        #expect(offResult.layout.positionedKeys.count == 1)
        #expect(onResult.layout.positionedKeys.count == 1)
        #expect(offResult.layout.name == "TestBoard L0")
        #expect(onResult.layout.name == "TestBoard L0")
    }
}
