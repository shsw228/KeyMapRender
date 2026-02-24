import Foundation

public struct VialDiagnosticsKey: Sendable {
    public let label: String
    public let x: Double
    public let y: Double
    public let matrixRow: Int?
    public let matrixCol: Int?
    public let rawKeycode: UInt16?

    public init(
        label: String,
        x: Double,
        y: Double,
        matrixRow: Int?,
        matrixCol: Int?,
        rawKeycode: UInt16?
    ) {
        self.label = label
        self.x = x
        self.y = y
        self.matrixRow = matrixRow
        self.matrixCol = matrixCol
        self.rawKeycode = rawKeycode
    }
}

public enum VialDiagnosticLogLevel: Sendable, Equatable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

public struct VialDiagnosticsService {
    public init() {}

    public func timestampedLine(for message: String, at date: Date = Date()) -> String {
        let timestamp = ISO8601DateFormatter().string(from: date)
        return "[\(timestamp)] \(message)"
    }

    public func logLevel(for message: String) -> VialDiagnosticLogLevel {
        let text = message.lowercased()
        if text.contains("crash") || text.contains("fatal") || message.contains("致命") {
            return .fault
        }
        if message.contains("失敗") || message.contains("応答なし") || text.contains("error") {
            return .error
        }
        if message.contains("不足") || message.contains("無効") || message.contains("キャンセル") {
            return .warning
        }
        if message.contains("開始") || message.contains("更新") {
            return .notice
        }
        if message.contains("成功") || message.contains("完了") {
            return .info
        }
        return .debug
    }

    public func bottomLeftThirdKeyMessage(layer: Int, keys: [VialDiagnosticsKey]) -> String? {
        guard !keys.isEmpty else { return nil }
        guard let bottomY = keys.map(\.y).max() else { return nil }
        let epsilon = 0.001
        let bottomRow = keys
            .filter { abs($0.y - bottomY) < epsilon }
            .sorted { $0.x < $1.x }
        guard bottomRow.count >= 3 else {
            return "キー検証 L\(layer): 最下段キー数不足 count=\(bottomRow.count)"
        }
        let target = bottomRow[2]
        let rc: String
        if let r = target.matrixRow, let c = target.matrixCol {
            rc = "\(r),\(c)"
        } else {
            rc = "n/a"
        }
        let raw: String
        if let rawCode = target.rawKeycode {
            raw = String(format: "0x%04X", rawCode)
        } else {
            raw = "n/a"
        }
        let rendered = target.label.replacingOccurrences(of: "\n", with: " / ")
        return "キー検証 L\(layer): 最下段左3 x=\(String(format: "%.2f", target.x)) rc=\(rc) raw=\(raw) label=\(rendered)"
    }

    public func numericLabelMessages(layer: Int, keys: [VialDiagnosticsKey]) -> [String] {
        let numericOnly = keys.filter { key in
            let text = key.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text.allSatisfy(\.isNumber)
        }
        guard !numericOnly.isEmpty else { return [] }
        return numericOnly.map { key in
            let rc: String
            if let r = key.matrixRow, let c = key.matrixCol {
                rc = "\(r),\(c)"
            } else {
                rc = "n/a"
            }
            let raw: String
            if let rawCode = key.rawKeycode {
                raw = String(format: "0x%04X", rawCode)
            } else {
                raw = "n/a"
            }
            return "数値ラベル検出 L\(layer): label=\(key.label) rc=\(rc) raw=\(raw) pos=(\(String(format: "%.2f", key.x)),\(String(format: "%.2f", key.y)))"
        }
    }
}
