import DataSource
import Observation

@MainActor @Observable
public final class RootStore: Composable {
    public struct AppPreferences: Sendable {
        public var targetKeyCode: Int
        public var longPressDuration: Double
        public var overlayShowAnimationDuration: Double
        public var overlayHideAnimationDuration: Double
        public var showSettingsOnLaunch: Bool
        public var ignoredDeviceIDs: [String]

        public init(
            targetKeyCode: Int,
            longPressDuration: Double,
            overlayShowAnimationDuration: Double,
            overlayHideAnimationDuration: Double,
            showSettingsOnLaunch: Bool,
            ignoredDeviceIDs: [String]
        ) {
            self.targetKeyCode = targetKeyCode
            self.longPressDuration = longPressDuration
            self.overlayShowAnimationDuration = overlayShowAnimationDuration
            self.overlayHideAnimationDuration = overlayHideAnimationDuration
            self.showSettingsOnLaunch = showSettingsOnLaunch
            self.ignoredDeviceIDs = ignoredDeviceIDs
        }
    }

    public struct StartupKeymapLoadResult: Sendable {
        public let matrixMessage: String
        public let matrixInfo: VialMatrixInfo?
        public let dumpResult: Result<VialKeymapDump, VialProbeError>

        public init(
            matrixMessage: String,
            matrixInfo: VialMatrixInfo?,
            dumpResult: Result<VialKeymapDump, VialProbeError>
        ) {
            self.matrixMessage = matrixMessage
            self.matrixInfo = matrixInfo
            self.dumpResult = dumpResult
        }
    }

    public struct StartupKeymapPresentation: Sendable {
        public let matrixDiagnosticMessage: String
        public let keymapStatusText: String
        public let completionDiagnosticMessage: String
        public let matrixRows: Int?
        public let matrixCols: Int?

        public init(
            matrixDiagnosticMessage: String,
            keymapStatusText: String,
            completionDiagnosticMessage: String,
            matrixRows: Int?,
            matrixCols: Int?
        ) {
            self.matrixDiagnosticMessage = matrixDiagnosticMessage
            self.keymapStatusText = keymapStatusText
            self.completionDiagnosticMessage = completionDiagnosticMessage
            self.matrixRows = matrixRows
            self.matrixCols = matrixCols
        }
    }

    public struct VialProbePresentation: Sendable {
        public let vialStatusText: String
        public let diagnosticMessage: String
        public let availableLayerCount: Int?

        public init(
            vialStatusText: String,
            diagnosticMessage: String,
            availableLayerCount: Int?
        ) {
            self.vialStatusText = vialStatusText
            self.diagnosticMessage = diagnosticMessage
            self.availableLayerCount = availableLayerCount
        }
    }

    public struct VialKeymapPresentation: Sendable {
        public let keymapStatusText: String
        public let diagnosticMessage: String
        public let availableLayerCount: Int?

        public init(
            keymapStatusText: String,
            diagnosticMessage: String,
            availableLayerCount: Int?
        ) {
            self.keymapStatusText = keymapStatusText
            self.diagnosticMessage = diagnosticMessage
            self.availableLayerCount = availableLayerCount
        }
    }

    public struct VialMatrixPresentation: Sendable {
        public let keymapStatusText: String
        public let diagnosticMessage: String
        public let matrixRows: Int?
        public let matrixCols: Int?

        public init(
            keymapStatusText: String,
            diagnosticMessage: String,
            matrixRows: Int?,
            matrixCols: Int?
        ) {
            self.keymapStatusText = keymapStatusText
            self.diagnosticMessage = diagnosticMessage
            self.matrixRows = matrixRows
            self.matrixCols = matrixCols
        }
    }

    public struct VialDefinitionPresentation: Sendable {
        public let keymapStatusText: String
        public let diagnosticMessage: String

        public init(
            keymapStatusText: String,
            diagnosticMessage: String
        ) {
            self.keymapStatusText = keymapStatusText
            self.diagnosticMessage = diagnosticMessage
        }
    }

    public struct KeyboardRefreshResult: Sendable {
        public let allDetectedKeyboards: [HIDKeyboardDevice]
        public let connectedKeyboards: [HIDKeyboardDevice]
        public let selectedKeyboardID: String
        public let keyboardStatusText: String
        public let ignoredDeviceCount: Int

        public init(
            allDetectedKeyboards: [HIDKeyboardDevice],
            connectedKeyboards: [HIDKeyboardDevice],
            selectedKeyboardID: String,
            keyboardStatusText: String,
            ignoredDeviceCount: Int
        ) {
            self.allDetectedKeyboards = allDetectedKeyboards
            self.connectedKeyboards = connectedKeyboards
            self.selectedKeyboardID = selectedKeyboardID
            self.keyboardStatusText = keyboardStatusText
            self.ignoredDeviceCount = ignoredDeviceCount
        }
    }

    private nonisolated let appDependencies: AppDependencies
    private var userDefaultsRepository: UserDefaultsRepository
    private var didConsumeInitialSettingsOpenRequest: Bool
    private var ignoredDeviceIDs: Set<String>

    public var showSettingsOnLaunch: Bool
    public let action: (Action) async -> Void

    public init(
        _ appDependencies: AppDependencies,
        showSettingsOnLaunch: Bool? = nil,
        didConsumeInitialSettingsOpenRequest: Bool = false,
        action: @escaping (Action) async -> Void = { _ in }
    ) {
        self.appDependencies = appDependencies
        let userDefaultsRepository = UserDefaultsRepository(appDependencies.userDefaultsClient)
        let initialShowSettingsOnLaunch = showSettingsOnLaunch ?? userDefaultsRepository.showSettingsOnLaunch
        let initialIgnoredDeviceIDs = Set(userDefaultsRepository.ignoredDeviceIDs)
        self.userDefaultsRepository = userDefaultsRepository
        self.showSettingsOnLaunch = initialShowSettingsOnLaunch
        self.ignoredDeviceIDs = initialIgnoredDeviceIDs
        self.didConsumeInitialSettingsOpenRequest = didConsumeInitialSettingsOpenRequest
        self.action = action
    }

    public func shouldOpenSettingsWindowOnLaunch() -> Bool {
        guard !didConsumeInitialSettingsOpenRequest else { return false }
        didConsumeInitialSettingsOpenRequest = true
        return showSettingsOnLaunch
    }

    public func setShowSettingsOnLaunch(_ enabled: Bool) {
        showSettingsOnLaunch = enabled
        userDefaultsRepository.showSettingsOnLaunch = enabled
    }

    public func loadAppPreferences() -> AppPreferences {
        AppPreferences(
            targetKeyCode: userDefaultsRepository.targetKeyCode,
            longPressDuration: userDefaultsRepository.longPressDuration,
            overlayShowAnimationDuration: userDefaultsRepository.overlayShowAnimationDuration,
            overlayHideAnimationDuration: userDefaultsRepository.overlayHideAnimationDuration,
            showSettingsOnLaunch: userDefaultsRepository.showSettingsOnLaunch,
            ignoredDeviceIDs: userDefaultsRepository.ignoredDeviceIDs
        )
    }

    public func saveAppPreferences(
        targetKeyCode: Int,
        longPressDuration: Double,
        overlayShowAnimationDuration: Double,
        overlayHideAnimationDuration: Double
    ) {
        userDefaultsRepository.targetKeyCode = targetKeyCode
        userDefaultsRepository.longPressDuration = longPressDuration
        userDefaultsRepository.overlayShowAnimationDuration = overlayShowAnimationDuration
        userDefaultsRepository.overlayHideAnimationDuration = overlayHideAnimationDuration
    }

    public func currentIgnoredDeviceIDs() -> Set<String> {
        ignoredDeviceIDs
    }

    public func addIgnoredDeviceID(_ id: String) {
        ignoredDeviceIDs.insert(id)
        userDefaultsRepository.ignoredDeviceIDs = Array(ignoredDeviceIDs).sorted()
    }

    public func clearIgnoredDeviceIDs() {
        ignoredDeviceIDs.removeAll()
        userDefaultsRepository.ignoredDeviceIDs = []
    }

    public func visibleKeyboards(from allDetected: [HIDKeyboardDevice]) -> [HIDKeyboardDevice] {
        allDetected.filter { !ignoredDeviceIDs.contains($0.id) }
    }

    public nonisolated func listKeyboards() -> [HIDKeyboardDevice] {
        appDependencies.hidKeyboardClient.listKeyboards()
    }

    public func refreshKeyboardSnapshot(currentSelectedID: String) -> KeyboardRefreshResult {
        let allDetectedKeyboards = listKeyboards()
        let connectedKeyboards = visibleKeyboards(from: allDetectedKeyboards)
        let ignoredDeviceCount = ignoredDeviceIDs.count
        guard !connectedKeyboards.isEmpty else {
            return KeyboardRefreshResult(
                allDetectedKeyboards: allDetectedKeyboards,
                connectedKeyboards: connectedKeyboards,
                selectedKeyboardID: "",
                keyboardStatusText: keyboardStatusText(
                    allDetectedKeyboards: allDetectedKeyboards,
                    connectedKeyboards: connectedKeyboards,
                    selectedKeyboard: nil
                ),
                ignoredDeviceCount: ignoredDeviceCount
            )
        }

        let selectedKeyboardID = resolveSelectedKeyboardID(
            current: currentSelectedID,
            connectedKeyboards: connectedKeyboards
        )
        let selectedKeyboard = connectedKeyboards.first { $0.id == selectedKeyboardID }
        return KeyboardRefreshResult(
            allDetectedKeyboards: allDetectedKeyboards,
            connectedKeyboards: connectedKeyboards,
            selectedKeyboardID: selectedKeyboardID,
            keyboardStatusText: keyboardStatusText(
                allDetectedKeyboards: allDetectedKeyboards,
                connectedKeyboards: connectedKeyboards,
                selectedKeyboard: selectedKeyboard
            ),
            ignoredDeviceCount: ignoredDeviceCount
        )
    }

    public func resolveSelectedKeyboardID(
        current selectedID: String,
        connectedKeyboards: [HIDKeyboardDevice]
    ) -> String {
        guard !connectedKeyboards.isEmpty else { return "" }
        if connectedKeyboards.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return connectedKeyboards[0].id
    }

    public func keyboardStatusText(
        allDetectedKeyboards: [HIDKeyboardDevice],
        connectedKeyboards: [HIDKeyboardDevice],
        selectedKeyboard: HIDKeyboardDevice?
    ) -> String {
        let ignoredCount = ignoredDeviceIDs.count
        if connectedKeyboards.isEmpty {
            if allDetectedKeyboards.isEmpty {
                return "キーボード未検出"
            }
            return "表示対象なし（\(ignoredCount) 台を無視中）"
        }
        if let selectedKeyboard {
            return "検出: \(selectedKeyboard.manufacturerName) \(selectedKeyboard.productName) (VID:0x\(String(selectedKeyboard.vendorID, radix: 16, uppercase: true)) PID:0x\(String(selectedKeyboard.productID, radix: 16, uppercase: true))) / 無視: \(ignoredCount) 台"
        }
        return "検出: \(connectedKeyboards.count) 台 / 無視: \(ignoredCount) 台"
    }

    public nonisolated func probeVialAsync(on device: HIDKeyboardDevice) async -> Result<VialProbeResult, VialProbeError> {
        let client = appDependencies.vialRawHIDClient
        return await Task.detached(priority: .userInitiated) {
            client.probe(device)
        }.value
    }

    public nonisolated func readVialKeymapAsync(
        on device: HIDKeyboardDevice,
        rows: Int,
        cols: Int
    ) async -> Result<VialKeymapDump, VialProbeError> {
        let client = appDependencies.vialRawHIDClient
        return await Task.detached(priority: .userInitiated) {
            client.readKeymap(device, rows, cols)
        }.value
    }

    public nonisolated func inferVialMatrixAsync(on device: HIDKeyboardDevice) async -> Result<VialMatrixInfo, VialProbeError> {
        let client = appDependencies.vialRawHIDClient
        return await Task.detached(priority: .userInitiated) {
            client.inferMatrix(device)
        }.value
    }

    public nonisolated func readVialDefinitionAsync(on device: HIDKeyboardDevice) async -> Result<String, VialProbeError> {
        let client = appDependencies.vialRawHIDClient
        return await Task.detached(priority: .userInitiated) {
            client.readDefinition(device)
        }.value
    }

    public nonisolated func readVialSwitchMatrixStateAsync(
        on device: HIDKeyboardDevice,
        rows: Int,
        cols: Int
    ) async -> Result<VialSwitchMatrixState, VialProbeError> {
        let client = appDependencies.vialRawHIDClient
        return await Task.detached(priority: .userInitiated) {
            client.readSwitchMatrixState(device, rows, cols)
        }.value
    }

    public nonisolated func loadStartupKeymapAsync(
        on device: HIDKeyboardDevice,
        initialRows: Int,
        initialCols: Int
    ) async -> StartupKeymapLoadResult {
        let matrixResult = await inferVialMatrixAsync(on: device)
        var rows = initialRows
        var cols = initialCols
        var matrixMessage = "matrix自動取得未実行"
        var matrixInfo: VialMatrixInfo?

        switch matrixResult {
        case let .success(info):
            rows = info.rows
            cols = info.cols
            matrixInfo = info
            matrixMessage = "matrix自動取得成功(\(info.backend)): \(rows)x\(cols)"
        case let .failure(.message(message)):
            matrixMessage = "matrix自動取得失敗: \(message)"
        }

        let dumpResult = await readVialKeymapAsync(on: device, rows: rows, cols: cols)
        return StartupKeymapLoadResult(
            matrixMessage: matrixMessage,
            matrixInfo: matrixInfo,
            dumpResult: dumpResult
        )
    }

    public func presentStartupKeymapLoadResult(_ result: StartupKeymapLoadResult) -> StartupKeymapPresentation {
        let matrixRows = result.matrixInfo?.rows
        let matrixCols = result.matrixInfo?.cols

        switch result.dumpResult {
        case let .success(dump):
            let keymapStatusText = "起動時読込成功(\(dump.backend)): protocol=\(dump.protocolVersion), layers=\(dump.layerCount), matrix=\(dump.matrixRows)x\(dump.matrixCols)"
            return StartupKeymapPresentation(
                matrixDiagnosticMessage: "起動時自動読込: \(result.matrixMessage)",
                keymapStatusText: keymapStatusText,
                completionDiagnosticMessage: "起動時全マップ読出し成功: \(keymapStatusText)",
                matrixRows: matrixRows,
                matrixCols: matrixCols
            )
        case let .failure(.message(message)):
            let keymapStatusText = "起動時読込失敗: \(message)"
            return StartupKeymapPresentation(
                matrixDiagnosticMessage: "起動時自動読込: \(result.matrixMessage)",
                keymapStatusText: keymapStatusText,
                completionDiagnosticMessage: "起動時全マップ読出し失敗: \(message)",
                matrixRows: matrixRows,
                matrixCols: matrixCols
            )
        }
    }

    public func presentVialProbeResult(_ result: Result<VialProbeResult, VialProbeError>) -> VialProbePresentation {
        switch result {
        case let .success(probe):
            let statusText = "Vial応答(\(probe.backend)): protocol=\(probe.protocolVersion), layers=\(probe.layerCount), L0R0C0=0x\(String(probe.keycodeL0R0C0, radix: 16, uppercase: true))"
            return VialProbePresentation(
                vialStatusText: statusText,
                diagnosticMessage: "Vial通信テスト成功: \(statusText)",
                availableLayerCount: max(1, probe.layerCount)
            )
        case let .failure(.message(message)):
            return VialProbePresentation(
                vialStatusText: "Vial応答なし: \(message)",
                diagnosticMessage: "Vial通信テスト失敗: \(message)",
                availableLayerCount: nil
            )
        }
    }

    public func presentVialKeymapReadResult(_ result: Result<VialKeymapDump, VialProbeError>) -> VialKeymapPresentation {
        switch result {
        case let .success(dump):
            let statusText = "取得成功(\(dump.backend)): protocol=\(dump.protocolVersion), layers=\(dump.layerCount), matrix=\(dump.matrixRows)x\(dump.matrixCols)"
            return VialKeymapPresentation(
                keymapStatusText: statusText,
                diagnosticMessage: "全マップ読出し成功: \(statusText)",
                availableLayerCount: max(1, dump.layerCount)
            )
        case let .failure(.message(message)):
            return VialKeymapPresentation(
                keymapStatusText: "取得失敗: \(message)",
                diagnosticMessage: "全マップ読出し失敗: \(message)",
                availableLayerCount: nil
            )
        }
    }

    public func presentVialMatrixInferenceResult(_ result: Result<VialMatrixInfo, VialProbeError>) -> VialMatrixPresentation {
        switch result {
        case let .success(info):
            return VialMatrixPresentation(
                keymapStatusText: "matrix自動取得成功(\(info.backend)): \(info.rows)x\(info.cols)",
                diagnosticMessage: "matrix自動取得成功: \(info.rows)x\(info.cols)",
                matrixRows: info.rows,
                matrixCols: info.cols
            )
        case let .failure(.message(message)):
            return VialMatrixPresentation(
                keymapStatusText: "matrix自動取得失敗: \(message)",
                diagnosticMessage: "matrix自動取得失敗: \(message)",
                matrixRows: nil,
                matrixCols: nil
            )
        }
    }

    public func suggestedVialDefinitionFileName(for device: HIDKeyboardDevice) -> String {
        String(
            format: "vial-%04X-%04X.json",
            device.vendorID,
            device.productID
        )
    }

    public func presentVialDefinitionValidationFailure(_ message: String) -> VialDefinitionPresentation {
        VialDefinitionPresentation(
            keymapStatusText: "vial.json検証失敗: \(message)",
            diagnosticMessage: "vial.json検証失敗: \(message)"
        )
    }

    public func presentVialDefinitionReadFailure(_ message: String) -> VialDefinitionPresentation {
        VialDefinitionPresentation(
            keymapStatusText: "vial.json取得失敗: \(message)",
            diagnosticMessage: "vial.json取得失敗: \(message)"
        )
    }

    public func presentVialDefinitionSaveResult(_ result: Result<SaveFileResult, SaveFileError>) -> VialDefinitionPresentation {
        switch result {
        case let .success(value):
            switch value {
            case let .saved(path):
                return VialDefinitionPresentation(
                    keymapStatusText: "vial.json保存完了: \(path)",
                    diagnosticMessage: "vial.json保存完了: \(path)"
                )
            case .cancelled:
                return VialDefinitionPresentation(
                    keymapStatusText: "vial.json保存をキャンセルしました。",
                    diagnosticMessage: "vial.json保存キャンセル"
                )
            }
        case let .failure(.message(message)):
            return VialDefinitionPresentation(
                keymapStatusText: "vial.json保存失敗: \(message)",
                diagnosticMessage: "vial.json保存失敗: \(message)"
            )
        }
    }

    public nonisolated func launchAtLoginStatus() -> Result<Bool, LaunchAtLoginError> {
        appDependencies.launchAtLoginClient.status()
    }

    public nonisolated func setLaunchAtLoginEnabled(_ enabled: Bool) -> Result<Bool, LaunchAtLoginError> {
        appDependencies.launchAtLoginClient.setEnabled(enabled)
    }

    public nonisolated func inputAccessStatus(
        promptAccessibility: Bool,
        requestInputMonitoring: Bool
    ) -> InputAccessStatus {
        appDependencies.inputAccessClient.checkStatus(promptAccessibility, requestInputMonitoring)
    }

    public func permissionStatusText(for status: InputAccessStatus) -> String {
        if status.accessibilityTrusted && status.inputMonitoringTrusted {
            return "権限: Accessibility/Input Monitoring 許可済み"
        }
        return "権限不足: Accessibility と Input Monitoring を許可してください。"
    }

    public func parseTargetKeyCode(_ text: String) -> UInt16? {
        guard let value = UInt16(text), value <= 127 else {
            return nil
        }
        return value
    }

    public func invalidTargetKeyCodeMessage() -> String {
        "キーコードは 0-127 の整数で入力してください。"
    }

    public func monitoringStatusText(targetKeyCode: UInt16, longPressDuration: Double) -> String {
        "監視中: keyCode \(targetKeyCode), 長押し \(longPressDuration.formatted(.number.precision(.fractionLength(2)))) 秒"
    }

    public func monitoringStartFailureStatusText() -> String {
        "キー監視を開始できませんでした。Accessibility / Input Monitoring を確認してください。"
    }

    public func keyboardSelectionRequiredMessage() -> String {
        "キーボードを選択してください。"
    }

    public func ignoredKeyboardSelectionRequiredMessage() -> String {
        "無視対象のキーボードを選択してください。"
    }

    public func matrixInputValidationFailureMessage() -> String {
        "Rows/Cols は 1 以上の整数で入力してください。"
    }

    public func vialProbeInProgressStatusText() -> String {
        "Vial通信テスト中..."
    }

    public func keymapReadInProgressStatusText() -> String {
        "全マップ読出し中..."
    }

    public func matrixInferenceInProgressStatusText() -> String {
        "matrix自動取得中..."
    }

    public func vialDefinitionReadInProgressStatusText() -> String {
        "vial.json取得中..."
    }

    public func startupAutoLoadInProgressStatusText() -> String {
        "起動時自動読込中..."
    }

    public func keyboardHotplugStartFailureDiagnosticMessage() -> String {
        "キーボード接続監視の開始に失敗しました。"
    }

    public func overlayKeyboardName(for keyboard: HIDKeyboardDevice?) -> String {
        guard let keyboard else { return "Keyboard" }
        let manufacturer = keyboard.manufacturerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = keyboard.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = "\(manufacturer) \(product)".trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "Keyboard" : joined
    }

    public func overlayShownDiagnosticMessage(currentLayer: Int, totalLayers: Int) -> String {
        "オーバーレイ表示: L\(currentLayer)/\(max(0, totalLayers - 1))"
    }

    public func overlayUpdatedDiagnosticMessage(currentLayer: Int, totalLayers: Int) -> String {
        "オーバーレイ更新: L\(currentLayer)/\(max(0, totalLayers - 1))"
    }

    public func displayLayerChangedDiagnosticMessage(reason: String, currentLayer: Int, totalLayers: Int) -> String {
        "表示レイヤー変更(\(reason)): L\(currentLayer)/\(max(0, totalLayers - 1))"
    }

    public func activeLayerTrackingStartedDiagnosticMessage() -> String {
        "アクティブレイヤー追従開始"
    }

    public func activeLayerTrackingFailureDiagnosticMessage(_ detail: String) -> String {
        "アクティブレイヤー追従失敗: \(detail)"
    }

    public func ignoredDeviceAddedDiagnosticMessage(_ device: HIDKeyboardDevice) -> String {
        "デバイス無視追加: \(device.manufacturerName) \(device.productName) id=\(device.id)"
    }

    public func ignoredDevicesClearedDiagnosticMessage() -> String {
        "デバイス無視リストを全解除"
    }

    public nonisolated func copyToClipboard(_ text: String) {
        appDependencies.clipboardClient.copyString(text)
    }

    public nonisolated func saveTextFile(_ request: SaveFileRequest) -> Result<SaveFileResult, SaveFileError> {
        appDependencies.fileSaveClient.saveText(request)
    }

    public nonisolated func startKeyboardHotplugMonitoring(
        onChanged: @escaping @Sendable () -> Void
    ) -> Result<HIDKeyboardHotplugSession, HIDKeyboardHotplugError> {
        appDependencies.hidKeyboardHotplugClient.start(onChanged)
    }

    public nonisolated func stopKeyboardHotplugMonitoring(_ session: HIDKeyboardHotplugSession) {
        appDependencies.hidKeyboardHotplugClient.stop(session)
    }

    public nonisolated func startGlobalKeyMonitoring(
        _ configuration: GlobalKeyMonitorConfiguration,
        onLongPressStart: @escaping @Sendable () -> Void,
        onLongPressEnd: @escaping @Sendable () -> Void
    ) -> Result<GlobalKeyMonitorSession, GlobalKeyMonitorError> {
        appDependencies.globalKeyMonitorClient.start(
            configuration,
            onLongPressStart,
            onLongPressEnd
        )
    }

    public nonisolated func stopGlobalKeyMonitoring(_ session: GlobalKeyMonitorSession) {
        appDependencies.globalKeyMonitorClient.stop(session)
    }

    public nonisolated func updateOverlayAnimationDurations(show: Double, hide: Double) {
        appDependencies.overlayWindowClient.updateAnimationDurations(show, hide)
    }

    public nonisolated func showOverlay(
        layout: KeyboardLayout,
        currentLayer: Int,
        totalLayers: Int
    ) {
        appDependencies.overlayWindowClient.show(layout, currentLayer, totalLayers)
    }

    public nonisolated func hideOverlay() {
        appDependencies.overlayWindowClient.hide()
    }

    public enum Action: Sendable {
        case showSettingsOnLaunchToggleSwitched(Bool)
        case settingsWindowLaunchRequestConsumed
    }
}
