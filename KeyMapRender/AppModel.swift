import AppKit
import Combine
import OSLog
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct VialLayoutChoice: Identifiable {
    let id: Int
    let title: String
    let options: [String]
    var selected: Int
}

@MainActor
final class AppModel: ObservableObject {
    @Published var targetKeyCodeText: String
    @Published var longPressDuration: Double
    @Published var overlayShowAnimationDuration: Double
    @Published var overlayHideAnimationDuration: Double
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
    @Published var availableLayerCount = 1
    @Published var selectedLayerIndex = 0
    @Published var layoutChoices: [VialLayoutChoice] = []
    @Published var launchAtLoginEnabled = false
    @Published var showSettingsOnLaunch: Bool

    private let monitor = GlobalKeyLongPressMonitor()
    private let overlayWindowController = OverlayWindowController()
    private var allDetectedKeyboards: [HIDKeyboardDevice] = []
    private var ignoredDeviceIDs: Set<String> = []
    private var latestKeymapDump: VialKeymapDump?
    private var hasAutoLoadedOnStartup = false
    private var isShuttingDown = false
    private var manualSelectedLayerIndex = 0
    private var activeLayerTrackingTask: Task<Void, Never>?
    private var activeLayerTrackingGeneration: UInt64 = 0
    private var matrixPollFailureCount = 0
    private var hasStarted = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.shsw228.KeyMapRender",
        category: "AppModel"
    )

    private enum DefaultsKey {
        static let targetKeyCode = "targetKeyCode"
        static let longPressDuration = "longPressDuration"
        static let overlayShowAnimationDuration = "overlayShowAnimationDuration"
        static let overlayHideAnimationDuration = "overlayHideAnimationDuration"
        static let ignoredDeviceIDs = "ignoredDeviceIDs"
        static let showSettingsOnLaunch = "showSettingsOnLaunch"
    }

    static func shouldShowSettingsOnLaunchByDefault() -> Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.showSettingsOnLaunch) as? Bool ?? true
    }

    init() {
        let defaults = UserDefaults.standard
        let savedKey = defaults.object(forKey: DefaultsKey.targetKeyCode) as? Int ?? 49
        let savedDuration = defaults.object(forKey: DefaultsKey.longPressDuration) as? Double ?? 0.45
        let savedShowDuration = defaults.object(forKey: DefaultsKey.overlayShowAnimationDuration) as? Double ?? 0.24
        let savedHideDuration = defaults.object(forKey: DefaultsKey.overlayHideAnimationDuration) as? Double ?? 0.18
        let savedShowSettingsOnLaunch = defaults.object(forKey: DefaultsKey.showSettingsOnLaunch) as? Bool ?? true
        self.targetKeyCodeText = "\(savedKey)"
        self.longPressDuration = savedDuration
        self.overlayShowAnimationDuration = savedShowDuration
        self.overlayHideAnimationDuration = savedHideDuration
        self.showSettingsOnLaunch = savedShowSettingsOnLaunch
        self.layout = KeyboardLayoutLoader.loadDefaultLayout()
        self.matrixRowsText = "6"
        self.matrixColsText = "17"
        self.ignoredDeviceIDs = Set(defaults.stringArray(forKey: DefaultsKey.ignoredDeviceIDs) ?? [])
        self.ignoredDeviceCount = self.ignoredDeviceIDs.count
        self.overlayWindowController.updateAnimationDurations(
            show: savedShowDuration,
            hide: savedHideDuration
        )
    }

    func start() {
        guard !hasStarted else { return }
        guard !isShuttingDown else { return }
        hasStarted = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        let listenTrusted = CGPreflightListenEventAccess()
        _ = CGRequestListenEventAccess()

        if axTrusted && listenTrusted {
            permissionStatusText = "権限: Accessibility/Input Monitoring 許可済み"
        } else {
            permissionStatusText = "権限不足: Accessibility と Input Monitoring を許可してください。"
        }
        refreshKeyboards()
        refreshLaunchAtLoginStatus()
        applySettings()
        autoLoadKeymapIfPossibleOnStartup()
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        stopActiveLayerTracking()
        monitor.stop()
        monitor.onLongPressStart = nil
        monitor.onLongPressEnd = nil
        overlayWindowController.hide()
        isOverlayVisible = false
    }

    func refreshLaunchAtLoginStatus() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginEnabled = false
            return
        }
        launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            launchAtLoginEnabled = false
            appendDiagnostics("自動起動設定は macOS 13 以降で利用できます。")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
            appendDiagnostics("自動起動設定を更新: \(launchAtLoginEnabled ? "ON" : "OFF")")
        } catch {
            refreshLaunchAtLoginStatus()
            appendDiagnostics("自動起動設定の更新失敗: \(error.localizedDescription)")
        }
    }

    func setShowSettingsOnLaunch(_ enabled: Bool) {
        showSettingsOnLaunch = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.showSettingsOnLaunch)
    }

    func applySettings() {
        guard !isShuttingDown else { return }
        guard let keyCodeValue = UInt16(targetKeyCodeText), keyCodeValue <= 127 else {
            permissionStatusText = "キーコードは 0-127 の整数で入力してください。"
            return
        }

        UserDefaults.standard.set(Int(keyCodeValue), forKey: DefaultsKey.targetKeyCode)
        UserDefaults.standard.set(longPressDuration, forKey: DefaultsKey.longPressDuration)
        UserDefaults.standard.set(overlayShowAnimationDuration, forKey: DefaultsKey.overlayShowAnimationDuration)
        UserDefaults.standard.set(overlayHideAnimationDuration, forKey: DefaultsKey.overlayHideAnimationDuration)
        UserDefaults.standard.set(showSettingsOnLaunch, forKey: DefaultsKey.showSettingsOnLaunch)
        overlayWindowController.updateAnimationDurations(
            show: overlayShowAnimationDuration,
            hide: overlayHideAnimationDuration
        )

        monitor.stop()
        monitor.targetKeyCode = CGKeyCode(keyCodeValue)
        monitor.longPressThreshold = longPressDuration
        monitor.onLongPressStart = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isOverlayVisible = true
                self.overlayWindowController.show(
                    layout: self.layout,
                    currentLayer: self.selectedLayerIndex,
                    totalLayers: self.availableLayerCount
                )
                self.startActiveLayerTrackingIfNeeded()
                self.appendDiagnostics("オーバーレイ表示: L\(self.selectedLayerIndex)/\(max(0, self.availableLayerCount - 1))")
            }
        }
        monitor.onLongPressEnd = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isOverlayVisible = false
                self.stopActiveLayerTracking()
                self.setDisplayedLayerIndex(self.manualSelectedLayerIndex, reason: "長押し終了", emitLog: false)
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
        autoLoadKeymapIfPossibleOnStartup()
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
                guard !self.isShuttingDown else { return }
                self.isDiagnosticsRunning = false
                switch result {
                case let .success(probe):
                    self.vialStatusText = "Vial応答(\(probe.backend)): protocol=\(probe.protocolVersion), layers=\(probe.layerCount), L0R0C0=0x\(String(probe.keycodeL0R0C0, radix: 16, uppercase: true))"
                    self.availableLayerCount = max(1, probe.layerCount)
                    self.setSelectedLayerIndex(self.selectedLayerIndex)
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
                guard !self.isShuttingDown else { return }
                self.isDiagnosticsRunning = false
                switch result {
                case let .success(dump):
                    self.latestKeymapDump = dump
                    self.layoutChoices = self.makeLayoutChoices(from: dump)
                    self.availableLayerCount = max(1, dump.layerCount)
                    self.setSelectedLayerIndex(self.selectedLayerIndex)
                    self.startActiveLayerTrackingIfNeeded()
                    self.keymapStatusText = "取得成功(\(dump.backend)): protocol=\(dump.protocolVersion), layers=\(dump.layerCount), matrix=\(dump.matrixRows)x\(dump.matrixCols)"
                    self.appendDiagnostics("全マップ読出し成功: \(self.keymapStatusText)")
                case let .failure(.message(message)):
                    self.keymapStatusText = "取得失敗: \(message)"
                    self.appendDiagnostics("全マップ読出し失敗: \(message)")
                }
            }
        }
    }

    func applySelectedLayerToLatestDump() {
        guard let dump = latestKeymapDump else { return }
        let layer = max(0, min(selectedLayerIndex, dump.layerCount - 1))
        let overlayName = currentOverlayKeyboardName()
        keymapPreviewText = makePreview(
            from: dump,
            layer: layer,
            maxRows: min(4, dump.matrixRows),
            maxCols: min(10, dump.matrixCols)
        )
        if let keymapRows = dump.layoutKeymapRows {
            layout = KeyboardLayoutLoader.makePhysicalLayoutFromVialKeymap(
                keymapRows: keymapRows,
                keycodes: dump.keycodes,
                layer: layer,
                selectedLayoutOptions: selectedLayoutOptions(),
                fallbackRows: dump.matrixRows,
                fallbackCols: dump.matrixCols,
                name: overlayName
            )
        } else {
            layout = KeyboardLayoutLoader.makeMatrixLayout(
                rows: dump.matrixRows,
                cols: dump.matrixCols,
                keycodes: dump.keycodes,
                layer: layer,
                name: overlayName
            )
        }
        if isOverlayVisible {
            overlayWindowController.show(
                layout: layout,
                currentLayer: selectedLayerIndex,
                totalLayers: availableLayerCount
            )
            appendDiagnostics("オーバーレイ更新: L\(selectedLayerIndex)/\(max(0, availableLayerCount - 1))")
        }
        logBottomLeftThirdKey(layer: layer)
        logNumericLabelDiagnostics(layer: layer)
    }

    func setSelectedLayerIndex(_ newValue: Int) {
        let clamped = max(0, min(newValue, max(0, availableLayerCount - 1)))
        manualSelectedLayerIndex = clamped
        setDisplayedLayerIndex(clamped, reason: "手動", forceApply: true)
    }

    private func setDisplayedLayerIndex(
        _ newValue: Int,
        reason: String,
        emitLog: Bool = true,
        forceApply: Bool = false
    ) {
        let clamped = max(0, min(newValue, max(0, availableLayerCount - 1)))
        let changed = (selectedLayerIndex != clamped)
        if !changed, !forceApply { return }
        selectedLayerIndex = clamped
        applySelectedLayerToLatestDump()
        if isOverlayVisible {
            overlayWindowController.show(
                layout: layout,
                currentLayer: selectedLayerIndex,
                totalLayers: availableLayerCount
            )
        }
        if changed, emitLog {
            appendDiagnostics("表示レイヤー変更(\(reason)): L\(selectedLayerIndex)/\(max(0, availableLayerCount - 1))")
        }
    }

    func updateLayoutChoice(index: Int, selected: Int) {
        guard let pos = layoutChoices.firstIndex(where: { $0.id == index }) else { return }
        let range = 0..<layoutChoices[pos].options.count
        guard range.contains(selected) else { return }
        layoutChoices[pos].selected = selected
        applySelectedLayerToLatestDump()
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
                guard !self.isShuttingDown else { return }
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

    func exportVialDefinitionOnSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keymapStatusText = "キーボードを選択してください。"
            return
        }
        isDiagnosticsRunning = true
        keymapStatusText = "vial.json取得中..."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = VialRawHIDService.readDefinition(device: selected)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.isShuttingDown else { return }
                self.isDiagnosticsRunning = false
                switch result {
                case let .success(prettyJSON):
                    do {
                        try validateVialDefinitionJSON(prettyJSON)
                    } catch {
                        self.keymapStatusText = "vial.json検証失敗: \(error.localizedDescription)"
                        self.appendDiagnostics("vial.json検証失敗: \(error.localizedDescription)")
                        return
                    }
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = String(
                        format: "vial-%04X-%04X.json",
                        selected.vendorID,
                        selected.productID
                    )
                    panel.allowedContentTypes = [.json]
                    panel.canCreateDirectories = true
                    panel.title = "vial.json を保存"
                    let response = panel.runModal()
                    guard response == .OK, let url = panel.url else {
                        self.keymapStatusText = "vial.json保存をキャンセルしました。"
                        self.appendDiagnostics("vial.json保存キャンセル")
                        return
                    }
                    do {
                        try prettyJSON.write(to: url, atomically: true, encoding: .utf8)
                        self.keymapStatusText = "vial.json保存完了: \(url.path)"
                        self.appendDiagnostics("vial.json保存完了: \(url.path)")
                    } catch {
                        self.keymapStatusText = "vial.json保存失敗: \(error.localizedDescription)"
                        self.appendDiagnostics("vial.json保存失敗: \(error.localizedDescription)")
                    }
                case let .failure(.message(message)):
                    self.keymapStatusText = "vial.json取得失敗: \(message)"
                    self.appendDiagnostics("vial.json取得失敗: \(message)")
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

    private func startActiveLayerTrackingIfNeeded() {
        guard isOverlayVisible else { return }
        guard latestKeymapDump != nil else { return }
        guard selectedKeyboard != nil else { return }
        if activeLayerTrackingTask != nil { return }

        matrixPollFailureCount = 0
        activeLayerTrackingGeneration &+= 1
        let generation = activeLayerTrackingGeneration
        activeLayerTrackingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let hasActivity = await self.pollActiveLayerFromKeyboard(generation: generation)
                let delayMs = hasActivity ? 8 : 25
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
        }
        appendDiagnostics("アクティブレイヤー追従開始")
    }

    private func stopActiveLayerTracking() {
        activeLayerTrackingGeneration &+= 1
        activeLayerTrackingTask?.cancel()
        activeLayerTrackingTask = nil
    }

    private func pollActiveLayerFromKeyboard(generation: UInt64) async -> Bool {
        guard generation == activeLayerTrackingGeneration else { return false }
        guard !Task.isCancelled else { return false }
        guard !isShuttingDown else { return false }
        guard isOverlayVisible else { return false }
        guard let selected = selectedKeyboard else { return false }
        guard let dump = latestKeymapDump else { return false }
        let baseLayer = manualSelectedLayerIndex

        let result = await readSwitchMatrixStateAsync(
            device: selected,
            matrixRows: dump.matrixRows,
            matrixCols: dump.matrixCols
        )

        guard generation == activeLayerTrackingGeneration else { return false }
        guard !Task.isCancelled else { return false }
        guard isOverlayVisible else { return false }

        switch result {
        case let .success(state):
            matrixPollFailureCount = 0
            let trackedLayer = deriveTrackedLayer(
                from: state.pressed,
                dump: dump,
                baseLayer: baseLayer
            )
            setDisplayedLayerIndex(trackedLayer, reason: "押下追従", emitLog: false)
            return state.pressed.contains { row in row.contains(true) }
        case let .failure(.message(message)):
            matrixPollFailureCount += 1
            if matrixPollFailureCount == 1 || matrixPollFailureCount % 20 == 0 {
                appendDiagnostics("アクティブレイヤー追従失敗: \(message)")
            }
            return false
        }
    }

    private func readSwitchMatrixStateAsync(
        device: HIDKeyboardDevice,
        matrixRows: Int,
        matrixCols: Int
    ) async -> Result<VialSwitchMatrixState, VialProbeError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = VialRawHIDService.readSwitchMatrixState(
                    device: device,
                    matrixRows: matrixRows,
                    matrixCols: matrixCols
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func deriveTrackedLayer(from pressed: [[Bool]], dump: VialKeymapDump, baseLayer: Int) -> Int {
        guard !dump.keycodes.isEmpty else { return 0 }
        let maxLayer = max(0, min(dump.layerCount - 1, dump.keycodes.count - 1))
        var effective = max(0, min(baseLayer, maxLayer))

        // Resolve nested MO/LT/LM holds with a few fixed-point iterations.
        for _ in 0..<4 {
            var next = max(0, min(baseLayer, maxLayer))
            var hasFnMo13 = false
            var hasFnMo23 = false
            for row in 0..<min(pressed.count, dump.matrixRows) {
                for col in 0..<min(pressed[row].count, dump.matrixCols) where pressed[row][col] {
                    let activeKeycode = resolvedKeycodeAt(layer: effective, row: row, col: col, keycodes: dump.keycodes)
                    if isFnMo13(activeKeycode) {
                        hasFnMo13 = true
                        continue
                    }
                    if isFnMo23(activeKeycode) {
                        hasFnMo23 = true
                        continue
                    }
                    if let target = layerHoldTarget(for: activeKeycode) {
                        next = max(next, min(target, maxLayer))
                    }
                }
            }
            if hasFnMo13 && hasFnMo23 {
                next = max(next, min(3, maxLayer))
            } else if hasFnMo13 {
                next = max(next, min(1, maxLayer))
            } else if hasFnMo23 {
                next = max(next, min(2, maxLayer))
            }
            if next == effective { break }
            effective = next
        }
        return effective
    }

    private func resolvedKeycodeAt(layer: Int, row: Int, col: Int, keycodes: [[[UInt16]]]) -> UInt16 {
        let safeLayer = max(0, min(layer, keycodes.count - 1))
        for current in stride(from: safeLayer, through: 0, by: -1) {
            guard row >= 0, row < keycodes[current].count else { continue }
            guard col >= 0, col < keycodes[current][row].count else { continue }
            let code = keycodes[current][row][col]
            if code != 0x0001 {
                return code
            }
        }
        return 0x0001
    }

    private func layerHoldTarget(for keycode: UInt16) -> Int? {
        // LT(layer, kc)
        if keycode >= 0x4000, keycode <= 0x4FFF {
            return Int((keycode >> 8) & 0x0F)
        }

        // QMK v5/v6 MO(layer) families.
        if keycode >= 0x5100, keycode <= 0x51FF {
            return Int(keycode & 0x00FF) // v5 MO
        }
        if keycode >= 0x5220, keycode <= 0x523F {
            return Int(keycode & 0x001F) // v6 MO
        }

        // LM(layer, mod): layer-while-hold
        if keycode >= 0x5900, keycode <= 0x59FF {
            return Int((keycode >> 4) & 0x0F) // v5 LM
        }
        if keycode >= 0x5000, keycode <= 0x51FF {
            return Int((keycode >> 5) & 0x1F) // v6 LM
        }
        return nil
    }

    private func isFnMo13(_ keycode: UInt16) -> Bool {
        keycode == 0x5F10 || keycode == 0x7C77
    }

    private func isFnMo23(_ keycode: UInt16) -> Bool {
        keycode == 0x5F11 || keycode == 0x7C78
    }

    private func makePreview(from dump: VialKeymapDump, layer: Int, maxRows: Int, maxCols: Int) -> String {
        guard !dump.keycodes.isEmpty else { return "(empty)" }
        let safeLayer = max(0, min(layer, dump.keycodes.count - 1))
        var lines: [String] = []
        let keyLayer = dump.keycodes[safeLayer]
        for row in 0..<maxRows {
            let cols = (0..<maxCols).map { col -> String in
                let value = keyLayer[row][col]
                return String(format: "%04X", value)
            }
            lines.append("L\(safeLayer) R\(row): " + cols.joined(separator: " "))
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
        switch diagnosticLevel(for: message) {
        case .debug:
            logger.debug("\(line, privacy: .public)")
        case .info:
            logger.info("\(line, privacy: .public)")
        case .notice:
            logger.notice("\(line, privacy: .public)")
        case .warning:
            logger.warning("\(line, privacy: .public)")
        case .error:
            logger.error("\(line, privacy: .public)")
        case .fault:
            logger.fault("\(line, privacy: .public)")
        }
    }

    private enum DiagnosticLevel {
        case debug
        case info
        case notice
        case warning
        case error
        case fault
    }

    private func diagnosticLevel(for message: String) -> DiagnosticLevel {
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

    private func persistIgnoredDeviceIDs() {
        UserDefaults.standard.set(Array(ignoredDeviceIDs).sorted(), forKey: DefaultsKey.ignoredDeviceIDs)
        ignoredDeviceCount = ignoredDeviceIDs.count
    }

    private func currentOverlayKeyboardName() -> String {
        guard let keyboard = selectedKeyboard else { return "Keyboard" }
        let manufacturer = keyboard.manufacturerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = keyboard.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = "\(manufacturer) \(product)".trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "Keyboard" : joined
    }

    private func selectedLayoutOptions() -> [Int: Int] {
        layoutChoices.reduce(into: [Int: Int]()) { result, item in
            result[item.id] = item.selected
        }
    }

    private func makeLayoutChoices(from dump: VialKeymapDump) -> [VialLayoutChoice] {
        guard
            let labels = dump.layoutLabels,
            !labels.isEmpty
        else {
            return []
        }
        let optionBits = dump.layoutOptions.map(UInt.init) ?? 0
        var choices: [VialLayoutChoice] = []
        var widths: [Int] = []

        for (labelIndex, item) in labels.enumerated() {
            if let title = item as? String {
                choices.append(
                    VialLayoutChoice(
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
                VialLayoutChoice(
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
            choices[choiceIndex].selected = min(raw, max(0, choices[choiceIndex].options.count - 1))
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

    private func logBottomLeftThirdKey(layer: Int) {
        let keys = layout.positionedKeys
        guard !keys.isEmpty else { return }
        guard let bottomY = keys.map(\.y).max() else { return }
        let epsilon = 0.001
        let bottomRow = keys
            .filter { abs($0.y - bottomY) < epsilon }
            .sorted { $0.x < $1.x }
        guard bottomRow.count >= 3 else {
            appendDiagnostics("キー検証 L\(layer): 最下段キー数不足 count=\(bottomRow.count)")
            return
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
        appendDiagnostics("キー検証 L\(layer): 最下段左3 x=\(String(format: "%.2f", target.x)) rc=\(rc) raw=\(raw) label=\(rendered)")
    }

    private func logNumericLabelDiagnostics(layer: Int) {
        let numericOnly = layout.positionedKeys.filter { key in
            let text = key.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text.allSatisfy(\.isNumber)
        }
        guard !numericOnly.isEmpty else { return }
        for key in numericOnly {
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
            appendDiagnostics("数値ラベル検出 L\(layer): label=\(key.label) rc=\(rc) raw=\(raw) pos=(\(String(format: "%.2f", key.x)),\(String(format: "%.2f", key.y)))")
        }
    }

    private func validateVialDefinitionJSON(_ text: String) throws {
        enum ValidationError: LocalizedError {
            case notUTF8
            case invalidJSON
            case missingRootField(String)
            case missingNestedField(String)
            case invalidMatrix

            var errorDescription: String? {
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

        guard let data = text.data(using: .utf8) else { throw ValidationError.notUTF8 }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ValidationError.invalidJSON
        }

        guard object["layouts"] != nil else { throw ValidationError.missingRootField("layouts") }
        guard object["matrix"] != nil else { throw ValidationError.missingRootField("matrix") }
        guard let layouts = object["layouts"] as? [String: Any] else {
            throw ValidationError.missingNestedField("layouts.keymap")
        }
        guard layouts["keymap"] is [Any] else {
            throw ValidationError.missingNestedField("layouts.keymap")
        }
        guard let matrix = object["matrix"] as? [String: Any] else {
            throw ValidationError.missingNestedField("matrix.rows/matrix.cols")
        }
        let rows = matrix["rows"] as? Int ?? 0
        let cols = matrix["cols"] as? Int ?? 0
        guard rows > 0, cols > 0 else { throw ValidationError.invalidMatrix }
    }

    private var selectedKeyboard: HIDKeyboardDevice? {
        connectedKeyboards.first(where: { $0.id == selectedKeyboardID })
    }

    private func autoLoadKeymapIfPossibleOnStartup() {
        guard !hasAutoLoadedOnStartup else { return }
        guard let selected = selectedKeyboard else { return }
        guard !isDiagnosticsRunning else { return }
        hasAutoLoadedOnStartup = true

        isDiagnosticsRunning = true
        keymapStatusText = "起動時自動読込中..."
        let initialRows = Int(matrixRowsText) ?? 6
        let initialCols = Int(matrixColsText) ?? 17

        DispatchQueue.global(qos: .userInitiated).async {
            let matrixResult = VialRawHIDService.inferMatrix(device: selected)
            var rows = initialRows
            var cols = initialCols
            var matrixLog = "matrix自動取得未実行"

            if case let .success(info) = matrixResult {
                rows = info.rows
                cols = info.cols
                matrixLog = "matrix自動取得成功(\(info.backend)): \(rows)x\(cols)"
            } else if case let .failure(.message(message)) = matrixResult {
                matrixLog = "matrix自動取得失敗: \(message)"
            }

            let dumpResult = VialRawHIDService.readKeymap(device: selected, matrixRows: rows, matrixCols: cols)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.isShuttingDown else { return }
                self.isDiagnosticsRunning = false
                self.appendDiagnostics("起動時自動読込: \(matrixLog)")
                switch matrixResult {
                case let .success(info):
                    self.matrixRowsText = "\(info.rows)"
                    self.matrixColsText = "\(info.cols)"
                case .failure:
                    break
                }

                switch dumpResult {
                case let .success(dump):
                    self.latestKeymapDump = dump
                    self.layoutChoices = self.makeLayoutChoices(from: dump)
                    self.availableLayerCount = max(1, dump.layerCount)
                    self.setSelectedLayerIndex(self.selectedLayerIndex)
                    self.startActiveLayerTrackingIfNeeded()
                    self.keymapStatusText = "起動時読込成功(\(dump.backend)): protocol=\(dump.protocolVersion), layers=\(dump.layerCount), matrix=\(dump.matrixRows)x\(dump.matrixCols)"
                    self.appendDiagnostics("起動時全マップ読出し成功: \(self.keymapStatusText)")
                case let .failure(.message(message)):
                    self.keymapStatusText = "起動時読込失敗: \(message)"
                    self.appendDiagnostics("起動時全マップ読出し失敗: \(message)")
                }
            }
        }
    }
}
