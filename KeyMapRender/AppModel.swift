import AppKit
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var targetKeyCodeText: String
    @Published var longPressDuration: Double
    @Published var permissionStatusText = "権限確認中..."
    @Published var isOverlayVisible = false
    @Published var layout: KeyboardLayout
    @Published var connectedKeyboards: [HIDKeyboardDevice] = []
    @Published var selectedKeyboardID: String = ""
    @Published var keyboardStatusText = "未取得"
    @Published var vialStatusText = "未実行"
    @Published var matrixRowsText: String
    @Published var matrixColsText: String
    @Published var keymapStatusText = "未実行"
    @Published var keymapPreviewText = "-"
    @Published var diagnosticsLogText = "-"
    @Published var isDiagnosticsRunning = false
    @Published var ignoredDeviceCount = 0

    private let monitor = GlobalKeyLongPressMonitor()
    private let overlayWindowController = OverlayWindowController()
    private var allDetectedKeyboards: [HIDKeyboardDevice] = []
    private var ignoredDeviceIDs: Set<String> = []

    private enum DefaultsKey {
        static let targetKeyCode = "targetKeyCode"
        static let longPressDuration = "longPressDuration"
        static let ignoredDeviceIDs = "ignoredDeviceIDs"
    }

    init() {
        let defaults = UserDefaults.standard
        let savedKey = defaults.object(forKey: DefaultsKey.targetKeyCode) as? Int ?? 49
        let savedDuration = defaults.object(forKey: DefaultsKey.longPressDuration) as? Double ?? 0.45
        self.targetKeyCodeText = "\(savedKey)"
        self.longPressDuration = savedDuration
        self.layout = KeyboardLayoutLoader.loadDefaultLayout()
        self.matrixRowsText = "6"
        self.matrixColsText = "17"
        self.ignoredDeviceIDs = Set(defaults.stringArray(forKey: DefaultsKey.ignoredDeviceIDs) ?? [])
        self.ignoredDeviceCount = self.ignoredDeviceIDs.count
    }

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        let listenTrusted = CGPreflightListenEventAccess()
        _ = CGRequestListenEventAccess()

        if axTrusted && listenTrusted {
            permissionStatusText = "権限: Accessibility/Input Monitoring 許可済み"
        } else {
            permissionStatusText = "権限不足: Accessibility と Input Monitoring を許可してください。"
        }
        refreshKeyboards()
        applySettings()
    }

    func applySettings() {
        guard let keyCodeValue = UInt16(targetKeyCodeText), keyCodeValue <= 127 else {
            permissionStatusText = "キーコードは 0-127 の整数で入力してください。"
            return
        }

        UserDefaults.standard.set(Int(keyCodeValue), forKey: DefaultsKey.targetKeyCode)
        UserDefaults.standard.set(longPressDuration, forKey: DefaultsKey.longPressDuration)

        monitor.stop()
        monitor.targetKeyCode = CGKeyCode(keyCodeValue)
        monitor.longPressThreshold = longPressDuration
        monitor.onLongPressStart = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isOverlayVisible = true
                self.overlayWindowController.show(layout: self.layout)
            }
        }
        monitor.onLongPressEnd = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isOverlayVisible = false
                self.overlayWindowController.hide()
            }
        }

        if monitor.start() {
            permissionStatusText = "監視中: keyCode \(keyCodeValue), 長押し \(longPressDuration.formatted(.number.precision(.fractionLength(2)))) 秒"
        } else {
            permissionStatusText = "キー監視を開始できませんでした。Accessibility / Input Monitoring を確認してください。"
        }
    }

    func refreshKeyboards() {
        allDetectedKeyboards = HIDKeyboardService.listKeyboards()
        connectedKeyboards = allDetectedKeyboards.filter { !ignoredDeviceIDs.contains($0.id) }
        if connectedKeyboards.isEmpty {
            selectedKeyboardID = ""
            if allDetectedKeyboards.isEmpty {
                keyboardStatusText = "キーボード未検出"
            } else {
                keyboardStatusText = "表示対象なし（\(ignoredDeviceIDs.count) 台を無視中）"
            }
            return
        }

        if !connectedKeyboards.contains(where: { $0.id == selectedKeyboardID }) {
            selectedKeyboardID = connectedKeyboards[0].id
        }

        if let selected = selectedKeyboard {
            keyboardStatusText = "検出: \(selected.manufacturerName) \(selected.productName) (VID:0x\(String(selected.vendorID, radix: 16, uppercase: true)) PID:0x\(String(selected.productID, radix: 16, uppercase: true))) / 無視: \(ignoredDeviceIDs.count) 台"
        } else {
            keyboardStatusText = "検出: \(connectedKeyboards.count) 台 / 無視: \(ignoredDeviceIDs.count) 台"
        }
    }

    func probeVialOnSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            vialStatusText = "キーボードを選択してください。"
            return
        }
        isDiagnosticsRunning = true
        vialStatusText = "Vial通信テスト中..."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = VialRawHIDService.probe(device: selected)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDiagnosticsRunning = false
                switch result {
                case let .success(probe):
                    self.vialStatusText = "Vial応答(\(probe.backend)): protocol=\(probe.protocolVersion), layers=\(probe.layerCount), L0R0C0=0x\(String(probe.keycodeL0R0C0, radix: 16, uppercase: true))"
                    self.appendDiagnostics("Vial通信テスト成功: \(self.vialStatusText)")
                case let .failure(.message(message)):
                    self.vialStatusText = "Vial応答なし: \(message)"
                    self.appendDiagnostics("Vial通信テスト失敗: \(message)")
                }
            }
        }
    }

    func readFullVialKeymapOnSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keymapStatusText = "キーボードを選択してください。"
            return
        }
        guard let rows = Int(matrixRowsText), let cols = Int(matrixColsText), rows > 0, cols > 0 else {
            keymapStatusText = "Rows/Cols は 1 以上の整数で入力してください。"
            return
        }
        isDiagnosticsRunning = true
        keymapStatusText = "全マップ読出し中..."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = VialRawHIDService.readKeymap(device: selected, matrixRows: rows, matrixCols: cols)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDiagnosticsRunning = false
                switch result {
                case let .success(dump):
                    self.keymapStatusText = "取得成功(\(dump.backend)): protocol=\(dump.protocolVersion), layers=\(dump.layerCount), matrix=\(dump.matrixRows)x\(dump.matrixCols)"
                    self.keymapPreviewText = self.makePreview(from: dump, maxRows: min(4, dump.matrixRows), maxCols: min(10, dump.matrixCols))
                    self.appendDiagnostics("全マップ読出し成功: \(self.keymapStatusText)")
                case let .failure(.message(message)):
                    self.keymapStatusText = "取得失敗: \(message)"
                    self.appendDiagnostics("全マップ読出し失敗: \(message)")
                }
            }
        }
    }

    func autoDetectMatrixOnSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keymapStatusText = "キーボードを選択してください。"
            return
        }
        isDiagnosticsRunning = true
        keymapStatusText = "matrix自動取得中..."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = VialRawHIDService.inferMatrix(device: selected)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDiagnosticsRunning = false
                switch result {
                case let .success(info):
                    self.matrixRowsText = "\(info.rows)"
                    self.matrixColsText = "\(info.cols)"
                    self.keymapStatusText = "matrix自動取得成功(\(info.backend)): \(info.rows)x\(info.cols)"
                    self.appendDiagnostics("matrix自動取得成功: \(info.rows)x\(info.cols)")
                case let .failure(.message(message)):
                    self.keymapStatusText = "matrix自動取得失敗: \(message)"
                    self.appendDiagnostics("matrix自動取得失敗: \(message)")
                }
            }
        }
    }

    func copyDiagnosticsLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsLogText, forType: .string)
    }

    func ignoreSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keyboardStatusText = "無視対象のキーボードを選択してください。"
            return
        }
        ignoredDeviceIDs.insert(selected.id)
        persistIgnoredDeviceIDs()
        appendDiagnostics("デバイス無視追加: \(selected.manufacturerName) \(selected.productName) id=\(selected.id)")
        refreshKeyboards()
    }

    func clearIgnoredKeyboards() {
        ignoredDeviceIDs.removeAll()
        persistIgnoredDeviceIDs()
        appendDiagnostics("デバイス無視リストを全解除")
        refreshKeyboards()
    }

    private func makePreview(from dump: VialKeymapDump, maxRows: Int, maxCols: Int) -> String {
        guard !dump.keycodes.isEmpty else { return "(empty)" }
        var lines: [String] = []
        let layer0 = dump.keycodes[0]
        for row in 0..<maxRows {
            let cols = (0..<maxCols).map { col -> String in
                let value = layer0[row][col]
                return String(format: "%04X", value)
            }
            lines.append("L0 R\(row): " + cols.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    private func appendDiagnostics(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        if diagnosticsLogText == "-" {
            diagnosticsLogText = line
        } else {
            diagnosticsLogText = diagnosticsLogText + "\n" + line
        }
        NSLog("[KeyMapRender] %@", line)
    }

    private func persistIgnoredDeviceIDs() {
        UserDefaults.standard.set(Array(ignoredDeviceIDs).sorted(), forKey: DefaultsKey.ignoredDeviceIDs)
        ignoredDeviceCount = ignoredDeviceIDs.count
    }

    private var selectedKeyboard: HIDKeyboardDevice? {
        connectedKeyboards.first(where: { $0.id == selectedKeyboardID })
    }
}
