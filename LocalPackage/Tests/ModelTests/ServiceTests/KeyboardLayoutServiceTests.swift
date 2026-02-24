import Testing

@testable import DataSource
@testable import Model

struct KeyboardLayoutServiceTests {
    @Test
    func makeMatrixLayout_buildsExpectedGrid() {
        let keycodes: [[[UInt16]]] = [[[0x0029, 0x001E], [0x001F, 0x0020]]]

        let layout = KeyboardLayoutService.makeMatrixLayout(
            rows: 2,
            cols: 2,
            keycodes: keycodes,
            layer: 0,
            name: "Test"
        )

        #expect(layout.name == "Test L0")
        #expect(layout.rows.count == 2)
        #expect(layout.rows[0].count == 2)
        #expect(layout.rows[0][0].label == "Esc")
    }

    @Test
    func makeMatrixLayout_returnsInvalidLayoutWhenLayerOutOfRange() {
        let keycodes: [[[UInt16]]] = [[[0x0029]]]

        let layout = KeyboardLayoutService.makeMatrixLayout(
            rows: 1,
            cols: 1,
            keycodes: keycodes,
            layer: 2,
            name: "Test"
        )

        #expect(layout.name.contains("(invalid)"))
        #expect(layout.rows.isEmpty)
    }
}
