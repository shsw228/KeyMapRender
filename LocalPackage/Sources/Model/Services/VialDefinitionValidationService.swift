import Foundation

public enum VialDefinitionValidationError: LocalizedError, Sendable, Equatable {
    case notUTF8
    case invalidJSON
    case missingRootField(String)
    case missingNestedField(String)
    case invalidMatrix

    public var errorDescription: String? {
        switch self {
        case .notUTF8:
            return "UTF-8変換に失敗"
        case .invalidJSON:
            return "JSONとして不正"
        case let .missingRootField(name):
            return "必須フィールド欠落: \(name)"
        case let .missingNestedField(name):
            return "必須フィールド欠落: \(name)"
        case .invalidMatrix:
            return "matrix rows/cols が不正"
        }
    }
}

public struct VialDefinitionValidationService {
    public init() {}

    public func validate(_ text: String) throws {
        guard let data = text.data(using: .utf8) else { throw VialDefinitionValidationError.notUTF8 }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw VialDefinitionValidationError.invalidJSON
        }

        guard object["layouts"] != nil else { throw VialDefinitionValidationError.missingRootField("layouts") }
        guard object["matrix"] != nil else { throw VialDefinitionValidationError.missingRootField("matrix") }
        guard let layouts = object["layouts"] as? [String: Any] else {
            throw VialDefinitionValidationError.missingNestedField("layouts.keymap")
        }
        guard layouts["keymap"] is [Any] else {
            throw VialDefinitionValidationError.missingNestedField("layouts.keymap")
        }
        guard let matrix = object["matrix"] as? [String: Any] else {
            throw VialDefinitionValidationError.missingNestedField("matrix.rows/matrix.cols")
        }
        let rows = matrix["rows"] as? Int ?? 0
        let cols = matrix["cols"] as? Int ?? 0
        guard rows > 0, cols > 0 else { throw VialDefinitionValidationError.invalidMatrix }
    }
}
