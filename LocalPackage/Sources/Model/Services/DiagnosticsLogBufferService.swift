import Foundation

public struct DiagnosticsLogAppendResult: Sendable {
    public let updatedText: String
    public let line: String
    public let level: VialDiagnosticLogLevel

    public init(
        updatedText: String,
        line: String,
        level: VialDiagnosticLogLevel
    ) {
        self.updatedText = updatedText
        self.line = line
        self.level = level
    }
}

public struct DiagnosticsLogBufferService {
    private let diagnosticsService: VialDiagnosticsService

    public init(diagnosticsService: VialDiagnosticsService = .init()) {
        self.diagnosticsService = diagnosticsService
    }

    public func append(
        existingText: String,
        message: String
    ) -> DiagnosticsLogAppendResult {
        let line = diagnosticsService.timestampedLine(for: message)
        let updatedText: String
        if existingText == "-" {
            updatedText = line
        } else {
            updatedText = existingText + "\n" + line
        }
        return DiagnosticsLogAppendResult(
            updatedText: updatedText,
            line: line,
            level: diagnosticsService.logLevel(for: message)
        )
    }
}
