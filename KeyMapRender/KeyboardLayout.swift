import Foundation
import DataSource

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
                    label: KeycodeLabelFormatter.label(for: value),
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
        selectedLayoutOptions: [Int: Int] = [:],
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

        var candidates: [PhysicalKeyCandidate] = []
        var cursorY = 0.0

        var align = 4
        keymapRows.enumerated().forEach { rowIndex, rowItems in
            if rowIndex > 0 {
                cursorY += 1.0
            }
            var width = 1.0
            var height = 1.0
            var cursorX = 0.0
            var pendingDecal = false

            for item in rowItems {
                if let dict = item as? [String: Any] {
                    if let x = toDouble(dict["x"]) {
                        cursorX += x
                    }
                    if let y = toDouble(dict["y"]) {
                        cursorY += y
                    }
                    if let w = toDouble(dict["w"]) { width = w }
                    if let h = toDouble(dict["h"]) { height = h }
                    if let d = dict["d"] as? Bool { pendingDecal = d }
                    if let a = dict["a"] as? Int { align = a }
                    continue
                }

                let raw = String(describing: item)
                let parsed = parseRawLabel(raw, align: align)
                let mappedLabel = mapKeyLabel(parsed: parsed, layer: layer, keycodes: keycodes)
                let rawKeycode = rawKeycodeAt(parsed: parsed, layer: layer, keycodes: keycodes)
                candidates.append(
                    PhysicalKeyCandidate(
                        label: mappedLabel,
                        x: cursorX,
                        y: cursorY,
                        width: width,
                        height: height,
                        matrixRow: parsed.row,
                        matrixCol: parsed.col,
                        rawKeycode: rawKeycode,
                        layoutIndex: parsed.layoutIndex,
                        layoutOption: parsed.layoutOption,
                        isDecal: pendingDecal
                    )
                )
                pendingDecal = false
                cursorX += width
                width = 1.0
                height = 1.0
            }
        }

        var positioned: [PositionedKey] = []
        var keyIndex = 0
        for candidate in candidates {
            if let idx = candidate.layoutIndex, let opt = candidate.layoutOption {
                let selected = selectedLayoutOptions[idx] ?? 0
                guard selected == opt else { continue }
            }
            if candidate.isDecal { continue }
            guard candidate.matrixRow != nil, candidate.matrixCol != nil else { continue }
            let resolvedLabel: String
            if let raw = candidate.rawKeycode {
                resolvedLabel = KeycodeLabelFormatter.label(for: raw)
            } else {
                resolvedLabel = candidate.label
            }
            positioned.append(
                PositionedKey(
                    id: "k\(keyIndex)",
                    label: resolvedLabel,
                    x: candidate.x,
                    y: candidate.y,
                    width: candidate.width,
                    height: candidate.height,
                    matrixRow: candidate.matrixRow,
                    matrixCol: candidate.matrixCol,
                    rawKeycode: candidate.rawKeycode
                )
            )
            keyIndex += 1
        }

        return makeLayout(name: "\(name) L\(layer)", rows: [], positionedKeys: positioned)
    }

    nonisolated private static func mapKeyLabel(
        parsed: RawLabel,
        layer: Int,
        keycodes: [[[UInt16]]]
    ) -> String {
        if let row = parsed.row, let col = parsed.col {
            if row >= 0, col >= 0, row < keycodes[layer].count, col < keycodes[layer][row].count {
                return resolvedLayerAwareLabel(layer: layer, row: row, col: col, keycodes: keycodes)
            }
            return "----"
        }
        if let rawCode = parseNumericKeycode(parsed.displayLabel) {
            return KeycodeLabelFormatter.label(for: rawCode)
        }
        if let normalized = normalizeLiteralKeyLabel(parsed.displayLabel) {
            return normalized
        }
        return parsed.displayLabel.isEmpty ? "----" : parsed.displayLabel
    }

    nonisolated private static func rawKeycodeAt(
        parsed: RawLabel,
        layer: Int,
        keycodes: [[[UInt16]]]
    ) -> UInt16? {
        guard
            let row = parsed.row,
            let col = parsed.col,
            row >= 0,
            col >= 0,
            row < keycodes[layer].count,
            col < keycodes[layer][row].count
        else {
            return nil
        }
        return keycodes[layer][row][col]
    }

    nonisolated private static func resolvedLayerAwareLabel(
        layer: Int,
        row: Int,
        col: Int,
        keycodes: [[[UInt16]]]
    ) -> String {
        let keycode = keycodes[layer][row][col]
        // TRNS should show its effective fallback key on lower layers.
        if keycode == 0x0001 {
            if let fallback = fallbackKeycode(from: layer, row: row, col: col, keycodes: keycodes) {
                return "TRNS\n↓\(KeycodeLabelFormatter.label(for: fallback))"
            }
            return "TRNS"
        }
        return KeycodeLabelFormatter.label(for: keycode)
    }

    nonisolated private static func fallbackKeycode(
        from layer: Int,
        row: Int,
        col: Int,
        keycodes: [[[UInt16]]]
    ) -> UInt16? {
        guard layer > 0 else { return nil }
        var current = layer - 1
        while current >= 0 {
            guard row < keycodes[current].count, col < keycodes[current][row].count else {
                if current == 0 { break }
                current -= 1
                continue
            }
            let candidate = keycodes[current][row][col]
            if candidate != 0x0001 {
                return candidate
            }
            if current == 0 { break }
            current -= 1
        }
        return nil
    }

    nonisolated private static func normalizeLiteralKeyLabel(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !text.isEmpty else { return nil }
        if ["TRNS", "KC_TRNS", "TRANSPARENT", "_______"].contains(text) {
            return "TRNS"
        }
        if ["NO", "KC_NO", "XXXXXXX"].contains(text) {
            return "NO"
        }
        return nil
    }

    nonisolated private static func parseNumericKeycode(_ raw: String) -> UInt16? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return UInt16(text.dropFirst(2), radix: 16)
        }
        guard let decimal = Int(text), decimal >= 0, decimal <= Int(UInt16.max) else {
            return nil
        }
        return UInt16(decimal)
    }

    nonisolated private static func parseRawLabel(_ raw: String, align: Int) -> RawLabel {
        let lines = raw.components(separatedBy: "\n")
        let ordered = reorderLabels(lines, align: align)
        let primary = ordered.indices.contains(0) ? ordered[0] : ""
        let first = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pair = first.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let row = pair.count == 2 ? Int(pair[0]) : nil
        let col = pair.count == 2 ? Int(pair[1]) : nil

        let tagged = extractLayoutTag(fromOrdered: ordered)
        let layoutIndex = tagged?.0
        let layoutOption = tagged?.1

        return RawLabel(
            displayLabel: first,
            row: row,
            col: col,
            layoutIndex: layoutIndex,
            layoutOption: layoutOption
        )
    }

    nonisolated private static func extractLayoutTag(fromOrdered labels: [String?]) -> (Int, Int)? {
        if labels.count > 8, let text = labels[8], let parsed = parseIntPair(text) {
            return parsed
        }
        return nil
    }

    nonisolated private static func reorderLabels(_ labels: [String], align: Int) -> [String?] {
        let map = labelMap.indices.contains(align) ? labelMap[align] : labelMap[4]
        var out: [String?] = Array(repeating: nil, count: 12)
        for (index, value) in labels.enumerated() where index < map.count {
            let target = map[index]
            if target >= 0, target < out.count {
                out[target] = value
            }
        }
        return out
    }

    nonisolated private static let labelMap: [[Int]] = [
        [0, 6, 2, 8, 9, 11, 3, 5, 1, 4, 7, 10],
        [1, 7, -1, -1, 9, 11, 4, -1, -1, -1, -1, 10],
        [3, -1, 5, -1, 9, 11, -1, -1, 4, -1, -1, 10],
        [4, -1, -1, -1, 9, 11, -1, -1, -1, -1, -1, 10],
        [0, 6, 2, 8, 10, -1, 3, 5, 1, 4, 7, -1],
        [1, 7, -1, -1, 10, -1, 4, -1, -1, -1, -1, -1],
        [3, -1, 5, -1, 10, -1, -1, -1, 4, -1, -1, -1],
        [4, -1, -1, -1, 10, -1, -1, -1, -1, -1, -1, -1]
    ]

    nonisolated private static func parseIntPair(_ value: String) -> (Int, Int)? {
        let parts = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let first = Int(parts[0]), let second = Int(parts[1]) else {
            return nil
        }
        return (first, second)
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

private struct RawLabel {
    let displayLabel: String
    let row: Int?
    let col: Int?
    let layoutIndex: Int?
    let layoutOption: Int?
}

private struct PhysicalKeyCandidate {
    let label: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let matrixRow: Int?
    let matrixCol: Int?
    let rawKeycode: UInt16?
    let layoutIndex: Int?
    let layoutOption: Int?
    let isDecal: Bool
}

enum KeycodeLabelFormatter {
    nonisolated static func label(for keycode: UInt16) -> String {
        if keycode >= 0x0100, keycode <= 0x1FFF {
            return modsKeyLabelV6(for: keycode)
        }
        if keycode >= 0x6000, keycode <= 0x7FFF {
            return modTapLabelV5(for: keycode)
        }
        if keycode >= 0x2000, keycode <= 0x3FFF {
            return modTapLabel(for: keycode)
        }
        if keycode >= 0x4000, keycode <= 0x4FFF {
            return layerTapLabel(for: keycode)
        }
        if let named = specialNames[keycode] { return named }

        if let basic = basicLabel(for: keycode) { return basic }

        return String(format: "%04X", keycode)
    }

    nonisolated private static func basicLabel(for keycode: UInt16) -> String? {
        if let named = specialNames[keycode] { return named }
        if keycode >= 0x0004, keycode <= 0x001D {
            let offset = Int(keycode - 0x0004)
            let scalar = UnicodeScalar(UInt8(ascii: "A") + UInt8(offset))
            return String(Character(scalar))
        }
        if let number = numberNames[keycode] { return number }
        if let symbol = symbolNames[keycode] { return symbol }
        if let function = functionNames[keycode] { return function }
        return nil
    }

    nonisolated private static func modTapLabel(for keycode: UInt16) -> String {
        let mods = Int((keycode >> 8) & 0x1F)
        let tap = UInt16(keycode & 0x00FF)
        let tapLabel = tapKeyLabel(for: tap) ?? String(format: "0x%02X", tap)
        return modTapMacroLabel(mods: mods, tapLabel: tapLabel)
    }

    nonisolated private static func layerTapLabel(for keycode: UInt16) -> String {
        let layer = Int((keycode >> 8) & 0x0F)
        let tap = UInt16(keycode & 0x00FF)
        let tapLabel = tapKeyLabel(for: tap) ?? String(format: "0x%02X", tap)
        return "LT\(layer)(\(tapLabel))"
    }

    // QMK/Vial v5 style mod-tap range (0x60xx-0x7Fxx).
    // Example: 0x6129 -> LCTL_T(Esc)
    nonisolated private static func modTapLabelV5(for keycode: UInt16) -> String {
        let outer = keycode & 0xFF00
        let tap = UInt16(keycode & 0x00FF)
        let tapLabel = tapKeyLabel(for: tap) ?? String(format: "0x%02X", tap)
        if let hold = v5ModTapHoldNames[outer] {
            return "\(hold)(\(tapLabel))"
        }
        return String(format: "0x%04X", keycode)
    }

    // QMK/Vial v6 generic QK_MODS range (0x01xx-0x1Fxx): MODS(kc)
    nonisolated private static func modsKeyLabelV6(for keycode: UInt16) -> String {
        let mods = Int((keycode >> 8) & 0x1F)
        let tap = UInt16(keycode & 0x00FF)
        let tapLabel = tapKeyLabel(for: tap) ?? String(format: "0x%02X", tap)
        if let name = singleOrCompositeModName(mods) {
            return "\(name)(\(tapLabel))"
        }
        return String(format: "0x%04X", keycode)
    }

    nonisolated private static func singleOrCompositeModName(_ mods: Int) -> String? {
        if let single = singleModName(mods) {
            return single.replacingOccurrences(of: "_T", with: "")
        }
        let isRight = (mods & 0x10) != 0
        let base = mods & 0x0F
        if base == 0x07 { return isRight ? "RCSA" : "MEH" }
        if base == 0x0F { return isRight ? "RCAGS" : "HYPR" }

        var parts: [String] = []
        if (base & 0x01) != 0 { parts.append(isRight ? "RCtrl" : "LCtrl") }
        if (base & 0x02) != 0 { parts.append(isRight ? "RShift" : "LShift") }
        if (base & 0x04) != 0 { parts.append(isRight ? "RAlt" : "LAlt") }
        if (base & 0x08) != 0 { parts.append(isRight ? "RGui" : "LGui") }
        return parts.isEmpty ? nil : parts.joined(separator: "+")
    }

    // For LT/MT style composed keycodes, use unshifted key names.
    nonisolated private static func tapKeyLabel(for keycode: UInt16) -> String? {
        if let named = specialNames[keycode] { return named }
        if keycode >= 0x0004, keycode <= 0x001D {
            let offset = Int(keycode - 0x0004)
            let scalar = UnicodeScalar(UInt8(ascii: "A") + UInt8(offset))
            return String(Character(scalar))
        }
        if let number = tapNumberNames[keycode] { return number }
        if let symbol = tapSymbolNames[keycode] { return symbol }
        if let function = functionNames[keycode] { return function }
        return nil
    }

    nonisolated private static func modsLabel(_ mods: Int) -> String {
        let isRight = (mods & 0x10) != 0
        let base = mods & 0x0F
        var names: [String] = []
        if (base & 0x01) != 0 { names.append(isRight ? "RCtrl" : "LCtrl") }
        if (base & 0x02) != 0 { names.append(isRight ? "RShift" : "LShift") }
        if (base & 0x04) != 0 { names.append(isRight ? "RAlt" : "LAlt") }
        if (base & 0x08) != 0 { names.append(isRight ? "RGui" : "LGui") }
        return names.isEmpty ? String(format: "MOD(0x%02X)", mods) : names.joined(separator: "+")
    }

    nonisolated private static func modTapMacroLabel(mods: Int, tapLabel: String) -> String {
        if let single = singleModName(mods) {
            return "\(single)_T(\(tapLabel))"
        }
        if mods == 0x07 { return "MEH_T(\(tapLabel))" }
        if mods == 0x0F { return "HYPR_T(\(tapLabel))" }
        return String(format: "MT(0x%02X,%@)", mods, tapLabel)
    }

    nonisolated private static func singleModName(_ mods: Int) -> String? {
        let isRight = (mods & 0x10) != 0
        let base = mods & 0x0F
        switch base {
        case 0x01: return isRight ? "RCtrl" : "LCtrl"
        case 0x02: return isRight ? "RShift" : "LShift"
        case 0x04: return isRight ? "RAlt" : "LAlt"
        case 0x08: return isRight ? "RGui" : "LGui"
        default: return nil
        }
    }

    nonisolated private static let specialNames: [UInt16: String] = [
        0x0000: "NO",
        0x0001: "TRNS",
        0x0028: "Enter",
        0x0029: "Esc",
        0x002A: "Backspace",
        0x002B: "Tab",
        0x002C: "Space",
        0x0039: "Caps",
        0x0040: "F7",
        0x0041: "F8",
        0x0042: "F9",
        0x0043: "F10",
        0x0044: "F11",
        0x0045: "F12",
        0x0046: "PrtSc",
        0x0047: "Scroll",
        0x0048: "Pause",
        0x0049: "Insert",
        0x004A: "Home",
        0x004B: "PgUp",
        0x004C: "Delete",
        0x004D: "End",
        0x004E: "PgDn",
        0x004F: "Right",
        0x0050: "Left",
        0x0051: "Down",
        0x0052: "Up",
        0x0053: "NumLock",
        0x0054: "KP /",
        0x0055: "KP *",
        0x0056: "KP -",
        0x0057: "KP +",
        0x0058: "KP Enter",
        0x0059: "KP 1",
        0x005A: "KP 2",
        0x005B: "KP 3",
        0x005C: "KP 4",
        0x005D: "KP 5",
        0x005E: "KP 6",
        0x005F: "KP 7",
        0x0060: "KP 8",
        0x0061: "KP 9",
        0x0062: "KP 0",
        0x0063: "KP .",
        0x0067: "KP =",
        0x0087: "_\n\\",
        0x0088: "カタカナ\nひらがな",
        0x0089: "|\n¥",
        0x008A: "変換",
        0x008B: "無変換",
        0x0090: "한영\nかな",
        0x0091: "漢字\n英数",
        0x5F10: "Fn1\n(Fn3)",
        0x5F11: "Fn2\n(Fn3)",
        0x00E0: "LCtrl",
        0x00E1: "LShift",
        0x00E2: "LAlt",
        0x00E3: "LGui",
        0x00E4: "RCtrl",
        0x00E5: "RShift",
        0x00E6: "RAlt",
        0x00E7: "RGui"
    ]

    nonisolated private static let numberNames: [UInt16: String] = [
        0x001E: "!\n1",
        0x001F: "@\n2",
        0x0020: "#\n3",
        0x0021: "$\n4",
        0x0022: "%\n5",
        0x0023: "^\n6",
        0x0024: "&\n7",
        0x0025: "*\n8",
        0x0026: "(\n9",
        0x0027: ")\n0"
    ]

    nonisolated private static let tapNumberNames: [UInt16: String] = [
        0x001E: "1",
        0x001F: "2",
        0x0020: "3",
        0x0021: "4",
        0x0022: "5",
        0x0023: "6",
        0x0024: "7",
        0x0025: "8",
        0x0026: "9",
        0x0027: "0"
    ]

    nonisolated private static let symbolNames: [UInt16: String] = [
        0x002D: "_\n-",
        0x002E: "+\n=",
        0x002F: "{\n[",
        0x0030: "}\n]",
        0x0031: "|\n\\",
        0x0033: ":\n;",
        0x0034: "\"\n'",
        0x0035: "~\n`",
        0x0036: "<\n,",
        0x0037: ">\n.",
        0x0038: "?\n/"
    ]

    nonisolated private static let tapSymbolNames: [UInt16: String] = [
        0x002D: "-",
        0x002E: "=",
        0x002F: "[",
        0x0030: "]",
        0x0031: "\\",
        0x0033: ";",
        0x0034: "'",
        0x0035: "`",
        0x0036: ",",
        0x0037: ".",
        0x0038: "/"
    ]

    nonisolated private static let functionNames: [UInt16: String] = [
        0x003A: "F1",
        0x003B: "F2",
        0x003C: "F3",
        0x003D: "F4",
        0x003E: "F5",
        0x003F: "F6"
    ]

    // Derived from vial-gui keycodes_v5.py masked entries.
    nonisolated private static let v5ModTapHoldNames: [UInt16: String] = [
        0x6100: "LCTL_T",
        0x6200: "LSFT_T",
        0x6400: "LALT_T",
        0x6800: "LGUI_T",
        0x6300: "LCS_T",
        0x6500: "LCA_T",
        0x6900: "LCG_T",
        0x6600: "LSA_T",
        0x6A00: "LSG_T",
        0x6C00: "LAG_T",
        0x6D00: "LCAG_T",
        0x6700: "MEH_T",
        0x6F00: "ALL_T",
        0x7100: "RCTL_T",
        0x7200: "RSFT_T",
        0x7400: "RALT_T",
        0x7800: "RGUI_T",
        0x7300: "RCS_T",
        0x7500: "RCA_T",
        0x7900: "RCG_T",
        0x7600: "RSA_T",
        0x7A00: "RSG_T",
        0x7C00: "RAG_T",
        0x7D00: "RCAG_T",
        0x7700: "RCSA_T",
        0x7F00: "RCAGS_T"
    ]
}
