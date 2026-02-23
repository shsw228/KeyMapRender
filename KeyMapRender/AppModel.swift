import Combine
import DataSource
import Model
import OSLog
import SwiftUI

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
    @Published var layoutChoices: [VialLayoutChoiceValue] = []
    @Published var launchAtLoginEnabled = false
    @Published var showSettingsOnLaunch: Bool

    private var allDetectedKeyboards: [HIDKeyboardDevice] = []
    private var latestKeymapDump: VialKeymapDump?
    private var hasAutoLoadedOnStartup = false
    private var isShuttingDown = false
    private var manualSelectedLayerIndex = 0
    private var activeLayerTrackingTask: Task<Void, Never>?
    private var activeLayerTrackingGeneration: UInt64 = 0
    private var matrixPollFailureCount = 0
    private var hasStarted = false
    private var keyboardHotplugSession: HIDKeyboardHotplugSession?
    private var globalKeyMonitorSession: GlobalKeyMonitorSession?
    private let rootStore: RootStore
    private let activeLayerTrackingService = ActiveLayerTrackingService()
    private let activeLayerPollingService = ActiveLayerPollingService()
    private let layerSelectionService = LayerSelectionService()
    private let vialPresentationService = VialPresentationService()
    private let vialDiagnosticsService = VialDiagnosticsService()
    private let diagnosticsLogBufferService = DiagnosticsLogBufferService()
    private let vialDefinitionValidationService = VialDefinitionValidationService()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.shsw228.KeyMapRender",
        category: "AppModel"
    )

    func shouldOpenSettingsWindowOnLaunch() -> Bool {
        rootStore.shouldOpenSettingsWindowOnLaunch()
    }

    init(appDependencies: AppDependencies = .keyMapRenderLive) {
        self.rootStore = RootStore(appDependencies)
        let preferences = rootStore.loadAppPreferences()
        self.targetKeyCodeText = "\(preferences.targetKeyCode)"
        self.longPressDuration = preferences.longPressDuration
        self.overlayShowAnimationDuration = preferences.overlayShowAnimationDuration
        self.overlayHideAnimationDuration = preferences.overlayHideAnimationDuration
        self.showSettingsOnLaunch = preferences.showSettingsOnLaunch
        self.layout = KeyboardLayoutLoader.loadDefaultLayout()
        self.matrixRowsText = "6"
        self.matrixColsText = "17"
        self.ignoredDeviceCount = self.rootStore.currentIgnoredDeviceIDs().count
        self.rootStore.updateOverlayAnimationDurations(
            show: preferences.overlayShowAnimationDuration,
            hide: preferences.overlayHideAnimationDuration
        )
    }

    func start() {
        guard !hasStarted else { return }
        guard !isShuttingDown else { return }
        hasStarted = true
        let accessStatus = rootStore.inputAccessStatus(
            promptAccessibility: true,
            requestInputMonitoring: true
        )

        if accessStatus.accessibilityTrusted && accessStatus.inputMonitoringTrusted {
            permissionStatusText = "権限: Accessibility/Input Monitoring 許可済み"
        } else {
            permissionStatusText = "権限不足: Accessibility と Input Monitoring を許可してください。"
        }
        refreshKeyboards()
        startKeyboardHotplugMonitor()
        refreshLaunchAtLoginStatus()
        applySettings()
        autoLoadKeymapIfPossibleOnStartup()
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        stopActiveLayerTracking()
        if let keyboardHotplugSession {
            rootStore.stopKeyboardHotplugMonitoring(keyboardHotplugSession)
            self.keyboardHotplugSession = nil
        }
        if let globalKeyMonitorSession {
            rootStore.stopGlobalKeyMonitoring(globalKeyMonitorSession)
            self.globalKeyMonitorSession = nil
        }
        rootStore.hideOverlay()
        isOverlayVisible = false
    }

    func refreshLaunchAtLoginStatus() {
        switch rootStore.launchAtLoginStatus() {
        case let .success(enabled):
            launchAtLoginEnabled = enabled
        case .failure:
            launchAtLoginEnabled = false
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        switch rootStore.setLaunchAtLoginEnabled(enabled) {
        case let .success(updated):
            launchAtLoginEnabled = updated
            appendDiagnostics("自動起動設定を更新: \(updated ? "ON" : "OFF")")
        case let .failure(.message(message)):
            refreshLaunchAtLoginStatus()
            appendDiagnostics("自動起動設定の更新失敗: \(message)")
        }
    }

    func setShowSettingsOnLaunch(_ enabled: Bool) {
        rootStore.setShowSettingsOnLaunch(enabled)
        showSettingsOnLaunch = enabled
    }

    func applySettings() {
        guard !isShuttingDown else { return }
        guard let keyCodeValue = UInt16(targetKeyCodeText), keyCodeValue <= 127 else {
            permissionStatusText = "キーコードは 0-127 の整数で入力してください。"
            return
        }

        rootStore.saveAppPreferences(
            targetKeyCode: Int(keyCodeValue),
            longPressDuration: longPressDuration,
            overlayShowAnimationDuration: overlayShowAnimationDuration,
            overlayHideAnimationDuration: overlayHideAnimationDuration
        )
        rootStore.setShowSettingsOnLaunch(showSettingsOnLaunch)
        rootStore.updateOverlayAnimationDurations(
            show: overlayShowAnimationDuration,
            hide: overlayHideAnimationDuration
        )

        if let globalKeyMonitorSession {
            rootStore.stopGlobalKeyMonitoring(globalKeyMonitorSession)
            self.globalKeyMonitorSession = nil
        }
        let monitorResult = rootStore.startGlobalKeyMonitoring(
            GlobalKeyMonitorConfiguration(
                targetKeyCode: keyCodeValue,
                longPressThreshold: longPressDuration
            ),
            onLongPressStart: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isOverlayVisible = true
                    self.rootStore.showOverlay(
                        layout: self.layout,
                        currentLayer: self.selectedLayerIndex,
                        totalLayers: self.availableLayerCount
                    )
                    self.startActiveLayerTrackingIfNeeded()
                    self.appendDiagnostics("オーバーレイ表示: L\(self.selectedLayerIndex)/\(max(0, self.availableLayerCount - 1))")
                }
            },
            onLongPressEnd: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isOverlayVisible = false
                    self.stopActiveLayerTracking()
                    self.setDisplayedLayerIndex(self.manualSelectedLayerIndex, reason: "長押し終了", emitLog: false)
                    self.rootStore.hideOverlay()
                }
            }
        )

        switch monitorResult {
        case let .success(session):
            globalKeyMonitorSession = session
            permissionStatusText = "監視中: keyCode \(keyCodeValue), 長押し \(longPressDuration.formatted(.number.precision(.fractionLength(2)))) 秒"
        case .failure:
            permissionStatusText = "キー監視を開始できませんでした。Accessibility / Input Monitoring を確認してください。"
        }
    }

    func refreshKeyboards() {
        let snapshot = rootStore.refreshKeyboardSnapshot(
            currentSelectedID: selectedKeyboardID
        )
        allDetectedKeyboards = snapshot.allDetectedKeyboards
        connectedKeyboards = snapshot.connectedKeyboards
        selectedKeyboardID = snapshot.selectedKeyboardID
        keyboardStatusText = snapshot.keyboardStatusText
        ignoredDeviceCount = snapshot.ignoredDeviceCount
        if connectedKeyboards.isEmpty { return }
        autoLoadKeymapIfPossibleOnStartup()
    }

    func probeVialOnSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            vialStatusText = "キーボードを選択してください。"
            return
        }
        isDiagnosticsRunning = true
        vialStatusText = "Vial通信テスト中..."
        Task { [weak self] in
            guard let self else { return }
            let result = await self.rootStore.probeVialAsync(on: selected)
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
        Task { [weak self] in
            guard let self else { return }
            let result = await self.rootStore.readVialKeymapAsync(on: selected, rows: rows, cols: cols)
            guard !self.isShuttingDown else { return }
                    self.isDiagnosticsRunning = false
                    switch result {
                    case let .success(dump):
                        self.latestKeymapDump = dump
                        self.layoutChoices = self.vialPresentationService.makeLayoutChoices(from: dump)
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

    func applySelectedLayerToLatestDump() {
        guard let dump = latestKeymapDump else { return }
        let layer = max(0, min(selectedLayerIndex, dump.layerCount - 1))
        let overlayName = currentOverlayKeyboardName()
        keymapPreviewText = makePreview(
            dump: dump,
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
            rootStore.showOverlay(
                layout: layout,
                currentLayer: selectedLayerIndex,
                totalLayers: availableLayerCount
            )
            appendDiagnostics("オーバーレイ更新: L\(selectedLayerIndex)/\(max(0, availableLayerCount - 1))")
        }
        let diagnosticKeys = layout.positionedKeys.map {
            VialDiagnosticsKey(
                label: $0.label,
                x: $0.x,
                y: $0.y,
                matrixRow: $0.matrixRow,
                matrixCol: $0.matrixCol,
                rawKeycode: $0.rawKeycode
            )
        }
        if let message = vialDiagnosticsService.bottomLeftThirdKeyMessage(layer: layer, keys: diagnosticKeys) {
            appendDiagnostics(message)
        }
        for message in vialDiagnosticsService.numericLabelMessages(layer: layer, keys: diagnosticKeys) {
            appendDiagnostics(message)
        }
    }

    func setSelectedLayerIndex(_ newValue: Int) {
        let clamped = layerSelectionService.clamp(
            newValue,
            totalLayers: availableLayerCount
        )
        manualSelectedLayerIndex = clamped
        setDisplayedLayerIndex(clamped, reason: "手動", forceApply: true)
    }

    private func setDisplayedLayerIndex(
        _ newValue: Int,
        reason: String,
        emitLog: Bool = true,
        forceApply: Bool = false
    ) {
        guard let update = layerSelectionService.resolveUpdate(
            current: selectedLayerIndex,
            requested: newValue,
            totalLayers: availableLayerCount,
            forceApply: forceApply
        ) else { return }
        selectedLayerIndex = update.clampedValue
        applySelectedLayerToLatestDump()
        if isOverlayVisible {
            rootStore.showOverlay(
                layout: layout,
                currentLayer: selectedLayerIndex,
                totalLayers: availableLayerCount
            )
        }
        if update.changed, emitLog {
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
        Task { [weak self] in
            guard let self else { return }
            let result = await self.rootStore.inferVialMatrixAsync(on: selected)
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

    func exportVialDefinitionOnSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keymapStatusText = "キーボードを選択してください。"
            return
        }
        isDiagnosticsRunning = true
        keymapStatusText = "vial.json取得中..."
        Task { [weak self] in
            guard let self else { return }
            let result = await self.rootStore.readVialDefinitionAsync(on: selected)
            guard !self.isShuttingDown else { return }
            self.isDiagnosticsRunning = false
            switch result {
            case let .success(prettyJSON):
                do {
                    try vialDefinitionValidationService.validate(prettyJSON)
                } catch {
                    self.keymapStatusText = "vial.json検証失敗: \(error.localizedDescription)"
                    self.appendDiagnostics("vial.json検証失敗: \(error.localizedDescription)")
                    return
                }
                let suggestedName = String(
                    format: "vial-%04X-%04X.json",
                    selected.vendorID,
                    selected.productID
                )
                let saveResult = self.rootStore.saveTextFile(
                    SaveFileRequest(
                        suggestedFileName: suggestedName,
                        allowedExtensions: ["json"],
                        title: "vial.json を保存",
                        content: prettyJSON
                    )
                )
                switch saveResult {
                case let .success(result):
                    switch result {
                    case let .saved(path):
                        self.keymapStatusText = "vial.json保存完了: \(path)"
                        self.appendDiagnostics("vial.json保存完了: \(path)")
                    case .cancelled:
                        self.keymapStatusText = "vial.json保存をキャンセルしました。"
                        self.appendDiagnostics("vial.json保存キャンセル")
                    }
                case let .failure(.message(message)):
                    self.keymapStatusText = "vial.json保存失敗: \(message)"
                    self.appendDiagnostics("vial.json保存失敗: \(message)")
                }
            case let .failure(.message(message)):
                self.keymapStatusText = "vial.json取得失敗: \(message)"
                self.appendDiagnostics("vial.json取得失敗: \(message)")
            }
        }
    }

    func copyDiagnosticsLog() {
        rootStore.copyToClipboard(diagnosticsLogText)
    }

    func ignoreSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keyboardStatusText = "無視対象のキーボードを選択してください。"
            return
        }
        rootStore.addIgnoredDeviceID(selected.id)
        persistIgnoredDeviceCount()
        appendDiagnostics("デバイス無視追加: \(selected.manufacturerName) \(selected.productName) id=\(selected.id)")
        refreshKeyboards()
    }

    func clearIgnoredKeyboards() {
        rootStore.clearIgnoredDeviceIDs()
        persistIgnoredDeviceCount()
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
        activeLayerTrackingTask = activeLayerPollingService.makePollingTask { [weak self] in
            guard let self else { return false }
            return await self.pollActiveLayerFromKeyboard(generation: generation)
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
            let trackedLayer = activeLayerTrackingService.deriveTrackedLayer(
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
        await rootStore.readVialSwitchMatrixStateAsync(on: device, rows: matrixRows, cols: matrixCols)
    }

    private func makePreview(dump: VialKeymapDump, layer: Int, maxRows: Int, maxCols: Int) -> String {
        vialPresentationService.makePreview(from: dump, layer: layer, maxRows: maxRows, maxCols: maxCols)
    }

    private func appendDiagnostics(_ message: String) {
        let result = diagnosticsLogBufferService.append(
            existingText: diagnosticsLogText,
            message: message
        )
        diagnosticsLogText = result.updatedText
        switch result.level {
        case .debug:
            logger.debug("\(result.line, privacy: .public)")
        case .info:
            logger.info("\(result.line, privacy: .public)")
        case .notice:
            logger.notice("\(result.line, privacy: .public)")
        case .warning:
            logger.warning("\(result.line, privacy: .public)")
        case .error:
            logger.error("\(result.line, privacy: .public)")
        case .fault:
            logger.fault("\(result.line, privacy: .public)")
        }
    }

    private func persistIgnoredDeviceCount() {
        ignoredDeviceCount = rootStore.currentIgnoredDeviceIDs().count
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

    private var selectedKeyboard: HIDKeyboardDevice? {
        connectedKeyboards.first(where: { $0.id == selectedKeyboardID })
    }

    private func startKeyboardHotplugMonitor() {
        guard keyboardHotplugSession == nil else { return }
        let result = rootStore.startKeyboardHotplugMonitoring { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isShuttingDown else { return }
                self.refreshKeyboards()
            }
        }
        switch result {
        case let .success(session):
            keyboardHotplugSession = session
        case .failure:
            appendDiagnostics("キーボード接続監視の開始に失敗しました。")
        }
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
        Task { [weak self] in
            guard let self else { return }
            let startupLoad = await self.rootStore.loadStartupKeymapAsync(
                on: selected,
                initialRows: initialRows,
                initialCols: initialCols
            )
            guard !self.isShuttingDown else { return }
            self.isDiagnosticsRunning = false
            self.appendDiagnostics("起動時自動読込: \(startupLoad.matrixMessage)")
            if let info = startupLoad.matrixInfo {
                self.matrixRowsText = "\(info.rows)"
                self.matrixColsText = "\(info.cols)"
            }

            switch startupLoad.dumpResult {
            case let .success(dump):
                self.latestKeymapDump = dump
                self.layoutChoices = self.vialPresentationService.makeLayoutChoices(from: dump)
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
