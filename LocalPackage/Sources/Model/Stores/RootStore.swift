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

    public nonisolated func copyToClipboard(_ text: String) {
        appDependencies.clipboardClient.copyString(text)
    }

    public nonisolated func saveTextFile(_ request: SaveFileRequest) -> Result<SaveFileResult, SaveFileError> {
        appDependencies.fileSaveClient.saveText(request)
    }

    public enum Action: Sendable {
        case showSettingsOnLaunchToggleSwitched(Bool)
        case settingsWindowLaunchRequestConsumed
    }
}
