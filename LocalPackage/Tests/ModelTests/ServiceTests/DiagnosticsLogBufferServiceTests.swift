import Testing

@testable import Model

struct DiagnosticsLogBufferServiceTests {
    @Test
    func append_replacesPlaceholderTextOnFirstLine() {
        let sut = DiagnosticsLogBufferService()

        let result = sut.append(existingText: "-", message: "テスト成功")

        #expect(result.updatedText == result.line)
        #expect(result.level == .info)
    }

    @Test
    func append_appendsNewLineWhenExistingTextIsPresent() {
        let sut = DiagnosticsLogBufferService()

        let result = sut.append(existingText: "[a] one", message: "更新")

        #expect(result.updatedText.hasPrefix("[a] one\n"))
        #expect(result.level == .notice)
    }
}
