import Foundation

struct KeyboardLayout {
    let name: String
    let rows: [[KeyboardKey]]
    let positionedKeys: [PositionedKey]
    let positionedWidth: Double
    let positionedHeight: Double
}

struct KeyboardKey {
    let label: String
    let width: Double
    let height: Double
    let isSpacer: Bool
}

struct PositionedKey: Identifiable {
    let id: String
    let label: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
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
            return makeLayout(name: name, rows: rows.map(parseRow), positionedKeys: [])
        }

        if let dict = json as? [String: Any],
           let name = dict["name"] as? String,
           let layouts = dict["layouts"] as? [String: Any],
           let keymap = layouts["keymap"] as? [[Any]] {
            return makeLayout(name: name, rows: keymap.map(parseRow), positionedKeys: [])
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
        makeLayout(
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
            ],
            positionedKeys: []
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
            return makeLayout(name: name + " (invalid)", rows: [], positionedKeys: [])
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

        return makeLayout(name: "\(name) L\(layer)", rows: matrixRows, positionedKeys: [])
    }

    nonisolated static func makePhysicalLayoutFromVialKeymap(
        keymapRows: [[Any]],
        keycodes: [[[UInt16]]],
        layer: Int,
        fallbackRows: Int,
        fallbackCols: Int,
        name: String
    ) -> KeyboardLayout {
        guard !keymapRows.isEmpty else {
            return makeMatrixLayout(rows: fallbackRows, cols: fallbackCols, keycodes: keycodes, layer: layer, name: name)
        }
        guard layer >= 0, layer < keycodes.count else {
            return makeMatrixLayout(rows: fallbackRows, cols: fallbackCols, keycodes: keycodes, layer: 0, name: name)
        }

        var positioned: [PositionedKey] = []
        var keyIndex = 0
        var cursorY = 0.0

        let rows: [[KeyboardKey]] = keymapRows.enumerated().map { rowIndex, rowItems in
            if rowIndex > 0 {
                cursorY += 1.0
            }
            var keys: [KeyboardKey] = []
            var width = 1.0
            var height = 1.0
            var spacerX = 0.0
            var cursorX = 0.0

            for item in rowItems {
                if let dict = item as? [String: Any] {
                    if let x = toDouble(dict["x"]) {
                        spacerX += x
                        cursorX += x
                    }
                    if let y = toDouble(dict["y"]) {
                        cursorY += y
                    }
                    if let w = toDouble(dict["w"]) { width = w }
                    if let h = toDouble(dict["h"]) { height = h }
                    continue
                }

                let raw = String(describing: item)
                if spacerX > 0 {
                    keys.append(KeyboardKey(label: "", width: spacerX, height: 1, isSpacer: true))
                    spacerX = 0
                }

                let mappedLabel = mapKeyLabel(rawLabel: raw, layer: layer, keycodes: keycodes)
                positioned.append(
                    PositionedKey(
                        id: "k\(keyIndex)",
                        label: mappedLabel,
                        x: cursorX,
                        y: cursorY,
                        width: width,
                        height: height
                    )
                )
                keyIndex += 1
                keys.append(
                    KeyboardKey(
                        label: mappedLabel,
                        width: width,
                        height: height,
                        isSpacer: false
                    )
                )
                cursorX += width
                width = 1.0
                height = 1.0
            }
            return keys
        }

        return makeLayout(name: "\(name) L\(layer)", rows: rows, positionedKeys: positioned)
    }

    nonisolated private static func mapKeyLabel(
        rawLabel: String,
        layer: Int,
        keycodes: [[[UInt16]]]
    ) -> String {
        let firstLine = rawLabel.split(separator: "\n").first.map(String.init) ?? rawLabel
        let pair = firstLine.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        if pair.count == 2, let row = Int(pair[0]), let col = Int(pair[1]) {
            if row >= 0, col >= 0, row < keycodes[layer].count, col < keycodes[layer][row].count {
                return String(format: "%04X", keycodes[layer][row][col])
            }
            return "----"
        }
        return firstLine.isEmpty ? "----" : firstLine
    }

    nonisolated private static func makeLayout(
        name: String,
        rows: [[KeyboardKey]],
        positionedKeys: [PositionedKey]
    ) -> KeyboardLayout {
        let bounds = positionedKeys.reduce((0.0, 0.0)) { partial, key in
            let maxX = max(partial.0, key.x + key.width)
            let maxY = max(partial.1, key.y + key.height)
            return (maxX, maxY)
        }
        return KeyboardLayout(
            name: name,
            rows: rows,
            positionedKeys: positionedKeys,
            positionedWidth: bounds.0,
            positionedHeight: bounds.1
        )
    }

    nonisolated private static func toDouble(_ value: Any?) -> Double? {
        switch value {
        case let d as Double:
            return d
        case let n as NSNumber:
            return n.doubleValue
        case let s as String:
            return Double(s)
        default:
            return nil
        }
    }
}
