import Foundation

struct KeyboardLayout {
    let name: String
    let rows: [[KeyboardKey]]
}

struct KeyboardKey {
    let label: String
    let width: Double
    let height: Double
    let isSpacer: Bool
}

enum KeyboardLayoutLoader {
    nonisolated static func loadDefaultLayout() -> KeyboardLayout {
        guard
            let url = Bundle.main.url(forResource: "default-layout", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return fallbackLayout()
        }
        return parse(json: json)
    }

    nonisolated private static func parse(json: Any) -> KeyboardLayout {
        if let dict = json as? [String: Any],
           let name = dict["name"] as? String,
           let rows = dict["rows"] as? [[Any]] {
            return KeyboardLayout(name: name, rows: rows.map(parseRow))
        }

        if let dict = json as? [String: Any],
           let name = dict["name"] as? String,
           let layouts = dict["layouts"] as? [String: Any],
           let keymap = layouts["keymap"] as? [[Any]] {
            return KeyboardLayout(name: name, rows: keymap.map(parseRow))
        }

        return fallbackLayout()
    }

    nonisolated private static func parseRow(_ row: [Any]) -> [KeyboardKey] {
        var keys: [KeyboardKey] = []
        var width = 1.0
        var height = 1.0
        var spacerX = 0.0

        for item in row {
            if let dict = item as? [String: Any] {
                if let x = dict["x"] as? Double {
                    spacerX += x
                }
                if let w = dict["w"] as? Double {
                    width = w
                }
                if let h = dict["h"] as? Double {
                    height = h
                }
                if let label = dict["label"] as? String {
                    if spacerX > 0 {
                        keys.append(KeyboardKey(label: "", width: spacerX, height: 1, isSpacer: true))
                        spacerX = 0
                    }
                    keys.append(KeyboardKey(label: label, width: width, height: height, isSpacer: false))
                    width = 1
                    height = 1
                }
                continue
            }

            let label: String
            if let text = item as? String {
                label = text
            } else if let number = item as? NSNumber {
                label = number.stringValue
            } else {
                continue
            }

            if spacerX > 0 {
                keys.append(KeyboardKey(label: "", width: spacerX, height: 1, isSpacer: true))
                spacerX = 0
            }
            keys.append(KeyboardKey(label: label, width: width, height: height, isSpacer: false))
            width = 1
            height = 1
        }

        return keys
    }

    nonisolated private static func fallbackLayout() -> KeyboardLayout {
        KeyboardLayout(
            name: "Fallback ANSI",
            rows: [
                ["Esc", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"].map {
                    KeyboardKey(label: $0, width: $0 == "Backspace" ? 2 : 1, height: 1, isSpacer: false)
                },
                ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"].map {
                    KeyboardKey(label: $0, width: $0 == "Tab" || $0 == "\\" ? 1.5 : 1, height: 1, isSpacer: false)
                },
                ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Enter"].map {
                    KeyboardKey(label: $0, width: $0 == "Caps" ? 1.75 : ($0 == "Enter" ? 2.25 : 1), height: 1, isSpacer: false)
                },
                ["Shift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "Shift"].map {
                    KeyboardKey(label: $0, width: $0 == "Shift" ? 2.25 : 1, height: 1, isSpacer: false)
                },
                [
                    KeyboardKey(label: "Ctrl", width: 1.25, height: 1, isSpacer: false),
                    KeyboardKey(label: "Opt", width: 1.25, height: 1, isSpacer: false),
                    KeyboardKey(label: "Cmd", width: 1.25, height: 1, isSpacer: false),
                    KeyboardKey(label: "Space", width: 6.25, height: 1, isSpacer: false),
                    KeyboardKey(label: "Cmd", width: 1.25, height: 1, isSpacer: false),
                    KeyboardKey(label: "Opt", width: 1.25, height: 1, isSpacer: false),
                ]
            ]
        )
    }

    nonisolated static func makeMatrixLayout(
        rows: Int,
        cols: Int,
        keycodes: [[[UInt16]]],
        layer: Int = 0,
        name: String = "Vial Keymap"
    ) -> KeyboardLayout {
        guard rows > 0, cols > 0, layer >= 0, layer < keycodes.count else {
            return KeyboardLayout(name: name + " (invalid)", rows: [])
        }

        let matrixRows: [[KeyboardKey]] = (0..<rows).map { row in
            (0..<cols).map { col in
                let value: UInt16
                if row < keycodes[layer].count, col < keycodes[layer][row].count {
                    value = keycodes[layer][row][col]
                } else {
                    value = 0
                }
                return KeyboardKey(
                    label: String(format: "%04X", value),
                    width: 1,
                    height: 1,
                    isSpacer: false
                )
            }
        }

        return KeyboardLayout(name: "\(name) L\(layer)", rows: matrixRows)
    }
}
