import Testing

@testable import DataSource
@testable import Model

struct VialPresentationServiceTests {
    private let sut = VialPresentationService()

    @Test
    func makePreview_formatsKeycodesWithLayerAndRow() {
        let dump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 1,
            matrixRows: 2,
            matrixCols: 2,
            keycodes: [
                [
                    [0x0029, 0x001E],
                    [0x001F, 0x0020],
                ],
            ],
            layoutKeymapRows: nil,
            layoutLabels: nil,
            layoutOptions: nil,
            backend: "python"
        )

        let preview = sut.makePreview(from: dump, layer: 0, maxRows: 2, maxCols: 2)

        #expect(preview.contains("L0 R0: 0029 001E"))
        #expect(preview.contains("L0 R1: 001F 0020"))
    }

    @Test
    func makeLayoutChoices_decodesOptionBitsInReverseOrder() {
        let dump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 1,
            matrixRows: 1,
            matrixCols: 1,
            keycodes: [[[0x0000]]],
            layoutKeymapRows: nil,
            layoutLabels: [
                ["Space", "6u", "3u+3u"],
                "ISO Enter",
            ],
            layoutOptions: 0b10,
            backend: "python"
        )

        let choices = sut.makeLayoutChoices(from: dump)

        #expect(choices.count == 2)
        #expect(choices[0].title == "Space")
        #expect(choices[0].selected == 1)
        #expect(choices[1].title == "ISO Enter")
        #expect(choices[1].selected == 0)
    }
}
