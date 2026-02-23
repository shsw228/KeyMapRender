import DataSource
import Foundation

public struct VialLayoutChoiceValue: Sendable {
    public let id: Int
    public let title: String
    public let options: [String]
    public let selected: Int

    public init(id: Int, title: String, options: [String], selected: Int) {
        self.id = id
        self.title = title
        self.options = options
        self.selected = selected
    }
}

public struct VialPresentationService {
    public init() {}

    public func makePreview(from dump: VialKeymapDump, layer: Int, maxRows: Int, maxCols: Int) -> String {
        guard !dump.keycodes.isEmpty else { return "(empty)" }
        let safeLayer = max(0, min(layer, dump.keycodes.count - 1))
        let keyLayer = dump.keycodes[safeLayer]
        var lines: [String] = []
        for row in 0..<maxRows {
            let cols = (0..<maxCols).map { col -> String in
                let value = keyLayer[row][col]
                return String(format: "%04X", value)
            }
            lines.append("L\(safeLayer) R\(row): " + cols.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    public func makeLayoutChoices(from dump: VialKeymapDump) -> [VialLayoutChoiceValue] {
        guard
            let labels = dump.layoutLabels,
            !labels.isEmpty
        else {
            return []
        }
        let optionBits = dump.layoutOptions.map(UInt.init) ?? 0
        var choices: [VialLayoutChoiceValue] = []
        var widths: [Int] = []

        for (labelIndex, item) in labels.enumerated() {
            if let title = item as? String {
                choices.append(
                    VialLayoutChoiceValue(
                        id: labelIndex,
                        title: title,
                        options: ["Off", "On"],
                        selected: 0
                    )
                )
                widths.append(1)
                continue
            }
            guard let array = item as? [Any], let rawTitle = array.first else {
                continue
            }
            let title = String(describing: rawTitle)
            let values = array.dropFirst().map { String(describing: $0) }
            guard !values.isEmpty else { continue }
            choices.append(
                VialLayoutChoiceValue(
                    id: labelIndex,
                    title: title,
                    options: values,
                    selected: 0
                )
            )
            widths.append(bitsNeeded(forChoiceCount: values.count))
        }

        // Vial/VIA stores layout option bits in reverse order.
        var cursor = 0
        for choiceIndex in choices.indices.reversed() {
            let width = widths[choiceIndex]
            let mask = (1 << width) - 1
            let raw = Int((optionBits >> cursor) & UInt(mask))
            let resolved = min(raw, max(0, choices[choiceIndex].options.count - 1))
            let current = choices[choiceIndex]
            choices[choiceIndex] = VialLayoutChoiceValue(
                id: current.id,
                title: current.title,
                options: current.options,
                selected: resolved
            )
            cursor += width
        }

        return choices
    }

    private func bitsNeeded(forChoiceCount count: Int) -> Int {
        let maxValue = max(1, count - 1)
        var bits = 0
        var current = maxValue
        while current > 0 {
            bits += 1
            current >>= 1
        }
        return max(bits, 1)
    }
}
