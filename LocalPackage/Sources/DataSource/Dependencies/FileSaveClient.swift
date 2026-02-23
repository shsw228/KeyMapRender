import Foundation

public struct SaveFileRequest: Sendable {
    public let suggestedFileName: String
    public let allowedExtensions: [String]
    public let title: String
    public let content: String

    public init(
        suggestedFileName: String,
        allowedExtensions: [String],
        title: String,
        content: String
    ) {
        self.suggestedFileName = suggestedFileName
        self.allowedExtensions = allowedExtensions
        self.title = title
        self.content = content
    }
}

public enum SaveFileResult: Sendable {
    case saved(path: String)
    case cancelled
}

public enum SaveFileError: Error, Sendable {
    case message(String)
}

public struct FileSaveClient: DependencyClient {
    public var saveText: @Sendable (SaveFileRequest) -> Result<SaveFileResult, SaveFileError>

    public init(saveText: @escaping @Sendable (SaveFileRequest) -> Result<SaveFileResult, SaveFileError>) {
        self.saveText = saveText
    }

    public static let liveValue = Self(saveText: { _ in .failure(.message("liveValue is not bound")) })
    public static let testValue = Self(saveText: { _ in .failure(.message("testValue: saveText")) })
}
