import DataSource
import Model

enum KeyboardLayoutLoader {
    nonisolated static func loadDefaultLayout() -> KeyboardLayout {
        KeyboardLayoutService.loadDefaultLayout()
    }

    nonisolated static func makeMatrixLayout(
        rows: Int,
        cols: Int,
        keycodes: [[[UInt16]]],
        layer: Int = 0,
        name: String = "Vial Keymap"
    ) -> KeyboardLayout {
        KeyboardLayoutService.makeMatrixLayout(
            rows: rows,
            cols: cols,
            keycodes: keycodes,
            layer: layer,
            name: name
        )
    }

    nonisolated static func makePhysicalLayoutFromVialKeymap(
        keymapRows: [[Any]],
        keycodes: [[[UInt16]]],
        layer: Int,
        selectedLayoutOptions: [Int: Int] = [:],
        fallbackRows: Int,
        fallbackCols: Int,
        name: String
    ) -> KeyboardLayout {
        KeyboardLayoutService.makePhysicalLayoutFromVialKeymap(
            keymapRows: keymapRows,
            keycodes: keycodes,
            layer: layer,
            selectedLayoutOptions: selectedLayoutOptions,
            fallbackRows: fallbackRows,
            fallbackCols: fallbackCols,
            name: name
        )
    }
}
