import Foundation
import Testing

@testable import Model

struct VialDiagnosticsServiceTests {
    private let sut = VialDiagnosticsService()

    @Test
    func logLevel_mapsKnownMessages() {
        #expect(sut.logLevel(for: "通信失敗") == .error)
        #expect(sut.logLevel(for: "設定更新") == .notice)
        #expect(sut.logLevel(for: "保存完了") == .info)
        #expect(sut.logLevel(for: "保存キャンセル") == .warning)
        #expect(sut.logLevel(for: "fatal: crash") == .fault)
    }

    @Test
    func bottomLeftThirdKeyMessage_returnsExpectedMessage() {
        let keys: [VialDiagnosticsKey] = [
            .init(label: "A", x: 0.0, y: 2.0, matrixRow: 3, matrixCol: 0, rawKeycode: 0x0004),
            .init(label: "B", x: 1.0, y: 2.0, matrixRow: 3, matrixCol: 1, rawKeycode: 0x0005),
            .init(label: "LT1(Space)", x: 2.0, y: 2.0, matrixRow: 3, matrixCol: 2, rawKeycode: 0x412C),
            .init(label: "C", x: 3.0, y: 1.0, matrixRow: 2, matrixCol: 3, rawKeycode: 0x0006),
        ]

        let message = sut.bottomLeftThirdKeyMessage(layer: 0, keys: keys)
        #expect(message?.contains("最下段左3") == true)
        #expect(message?.contains("rc=3,2") == true)
        #expect(message?.contains("raw=0x412C") == true)
        #expect(message?.contains("label=LT1(Space)") == true)
    }

    @Test
    func numericLabelMessages_returnsOnlyNumericLabels() {
        let keys: [VialDiagnosticsKey] = [
            .init(label: "6129", x: 0.0, y: 0.0, matrixRow: 0, matrixCol: 1, rawKeycode: 0x6129),
            .init(label: "Esc", x: 1.0, y: 0.0, matrixRow: 0, matrixCol: 2, rawKeycode: 0x0029),
        ]
        let messages = sut.numericLabelMessages(layer: 0, keys: keys)
        #expect(messages.count == 1)
        #expect(messages.first?.contains("label=6129") == true)
    }
}
