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

    public struct StartupKeymapWorkflowResult: Sendable {
        public let presentation: StartupKeymapPresentation
        public let dump: VialKeymapDump?

        public init(
            presentation: StartupKeymapPresentation,
            dump: VialKeymapDump?
        ) {
            self.presentation = presentation
            self.dump = dump
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

    public struct VialProbeWorkflowResult: Sendable {
        public let presentation: VialProbePresentation
        public let probe: VialProbeResult?

        public init(
            presentation: VialProbePresentation,
            probe: VialProbeResult?
        ) {
            self.presentation = presentation
            self.probe = probe
        }
    }

    public struct VialKeymapWorkflowResult: Sendable {
        public let presentation: VialKeymapPresentation
        public let dump: VialKeymapDump?

        public init(
            presentation: VialKeymapPresentation,
            dump: VialKeymapDump?
        ) {
            self.presentation = presentation
            self.dump = dump
        }
    }

    public struct VialMatrixWorkflowResult: Sendable {
        public let presentation: VialMatrixPresentation

        public init(presentation: VialMatrixPresentation) {
            self.presentation = presentation
        }
    }

    public struct LaunchAtLoginWorkflowResult: Sendable {
        public let enabled: Bool
        public let diagnosticMessage: String

        public init(enabled: Bool, diagnosticMessage: String) {
            self.enabled = enabled
            self.diagnosticMessage = diagnosticMessage
        }
    }

    public struct LaunchAtLoginStatusWorkflowResult: Sendable {
        public let enabled: Bool
        public let diagnosticMessage: String?

        public init(enabled: Bool, diagnosticMessage: String?) {
            self.enabled = enabled
            self.diagnosticMessage = diagnosticMessage
        }
    }

    public struct StartupLifecycleWorkflowResult: Sendable {
        public let shouldStart: Bool
        public let permissionStatusText: String?

        public init(shouldStart: Bool, permissionStatusText: String?) {
            self.shouldStart = shouldStart
            self.permissionStatusText = permissionStatusText
        }
    }

    public struct StartupAutoLoadPreparationResult: Sendable {
        public let shouldRun: Bool
        public let nextHasAutoLoadedOnStartup: Bool
        public let statusText: String?
        public let initialRows: Int?
        public let initialCols: Int?

        public init(
            shouldRun: Bool,
            nextHasAutoLoadedOnStartup: Bool,
            statusText: String?,
            initialRows: Int?,
            initialCols: Int?
        ) {
            self.shouldRun = shouldRun
            self.nextHasAutoLoadedOnStartup = nextHasAutoLoadedOnStartup
            self.statusText = statusText
            self.initialRows = initialRows
            self.initialCols = initialCols
        }
    }

    public struct KeymapDumpAdoptionResult: Sendable {
        public let layoutChoices: [VialLayoutChoiceValue]
        public let availableLayerCount: Int

        public init(layoutChoices: [VialLayoutChoiceValue], availableLayerCount: Int) {
            self.layoutChoices = layoutChoices
            self.availableLayerCount = availableLayerCount
        }
    }

    public enum ApplySettingsPreparationResult: Sendable {
        case success(configuration: GlobalKeyMonitorConfiguration)
        case failure(permissionStatusText: String)
    }

    public struct RestartGlobalMonitoringWorkflowResult: Sendable {
        public let session: GlobalKeyMonitorSession?
        public let permissionStatusText: String

        public init(session: GlobalKeyMonitorSession?, permissionStatusText: String) {
            self.session = session
            self.permissionStatusText = permissionStatusText
        }
    }

    public struct GlobalMonitoringWorkflowResult: Sendable {
        public let session: GlobalKeyMonitorSession?
        public let permissionStatusText: String

        public init(session: GlobalKeyMonitorSession?, permissionStatusText: String) {
            self.session = session
            self.permissionStatusText = permissionStatusText
        }
    }

    public struct KeyboardHotplugWorkflowResult: Sendable {
        public let session: HIDKeyboardHotplugSession?
        public let diagnosticMessage: String?

        public init(session: HIDKeyboardHotplugSession?, diagnosticMessage: String?) {
            self.session = session
            self.diagnosticMessage = diagnosticMessage
        }
    }

    public struct ActiveLayerPollWorkflowResult: Sendable {
        public let trackedLayer: Int?
        public let isAnyKeyPressed: Bool
        public let nextFailureCount: Int
        public let diagnosticMessage: String?

        public init(
            trackedLayer: Int?,
            isAnyKeyPressed: Bool,
            nextFailureCount: Int,
            diagnosticMessage: String?
        ) {
            self.trackedLayer = trackedLayer
            self.isAnyKeyPressed = isAnyKeyPressed
            self.nextFailureCount = nextFailureCount
            self.diagnosticMessage = diagnosticMessage
        }
    }

    public struct KeyboardIgnoreWorkflowResult: Sendable {
        public let snapshot: KeyboardRefreshResult
        public let diagnosticMessage: String

        public init(snapshot: KeyboardRefreshResult, diagnosticMessage: String) {
            self.snapshot = snapshot
            self.diagnosticMessage = diagnosticMessage
        }
    }

    public enum VialDefinitionWorkflowResult: Sendable {
        case success(prettyJSON: String, suggestedFileName: String)
        case failure(VialDefinitionPresentation)
    }

    private nonisolated let appDependencies: AppDependencies
    private var userDefaultsRepository: UserDefaultsRepository
    private var didConsumeInitialSettingsOpenRequest: Bool
    private var ignoredDeviceIDs: Set<String>
    private let vialPresentationService: VialPresentationService
    private let keymapLayerRenderingService: KeymapLayerRenderingService
    private let diagnosticsLogBufferService: DiagnosticsLogBufferService
    private let vialDefinitionValidationService: VialDefinitionValidationService
    private let activeLayerTrackingService: ActiveLayerTrackingService
    private let activeLayerPollingService: ActiveLayerPollingService
    private let layerSelectionService: LayerSelectionService

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
        self.vialPresentationService = VialPresentationService()
        self.keymapLayerRenderingService = KeymapLayerRenderingService()
        self.diagnosticsLogBufferService = DiagnosticsLogBufferService()
        self.vialDefinitionValidationService = VialDefinitionValidationService()
        self.activeLayerTrackingService = ActiveLayerTrackingService()
        self.activeLayerPollingService = ActiveLayerPollingService()
        self.layerSelectionService = LayerSelectionService()
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

    public func runIgnoreDeviceAndRefresh(
        _ device: HIDKeyboardDevice,
        currentSelectedID: String
    ) -> KeyboardIgnoreWorkflowResult {
        addIgnoredDeviceID(device.id)
        let snapshot = refreshKeyboardSnapshot(currentSelectedID: currentSelectedID)
        return KeyboardIgnoreWorkflowResult(
            snapshot: snapshot,
            diagnosticMessage: ignoredDeviceAddedDiagnosticMessage(device)
        )
    }

    public func runClearIgnoredDevicesAndRefresh(currentSelectedID: String) -> KeyboardIgnoreWorkflowResult {
        clearIgnoredDeviceIDs()
        let snapshot = refreshKeyboardSnapshot(currentSelectedID: currentSelectedID)
        return KeyboardIgnoreWorkflowResult(
            snapshot: snapshot,
            diagnosticMessage: ignoredDevicesClearedDiagnosticMessage()
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

    public nonisolated func runStartupKeymapLoadAsync(
        on device: HIDKeyboardDevice,
        initialRows: Int,
        initialCols: Int
    ) async -> StartupKeymapWorkflowResult {
        let result = await loadStartupKeymapAsync(
            on: device,
            initialRows: initialRows,
            initialCols: initialCols
        )
        let presentation = await MainActor.run { presentStartupKeymapLoadResult(result) }
        switch result.dumpResult {
        case let .success(dump):
            return StartupKeymapWorkflowResult(presentation: presentation, dump: dump)
        case .failure:
            return StartupKeymapWorkflowResult(presentation: presentation, dump: nil)
        }
    }

    public func makeLayoutChoices(from dump: VialKeymapDump) -> [VialLayoutChoiceValue] {
        vialPresentationService.makeLayoutChoices(from: dump)
    }

    public func runAdoptKeymapDump(_ dump: VialKeymapDump) -> KeymapDumpAdoptionResult {
        KeymapDumpAdoptionResult(
            layoutChoices: makeLayoutChoices(from: dump),
            availableLayerCount: max(1, dump.layerCount)
        )
    }

    public func renderKeymapLayer(
        dump: VialKeymapDump,
        requestedLayer: Int,
        selectedLayoutChoices: [VialLayoutChoiceValue],
        overlayName: String
    ) -> KeymapLayerRenderResult {
        keymapLayerRenderingService.render(
            dump: dump,
            requestedLayer: requestedLayer,
            selectedLayoutChoices: selectedLayoutChoices,
            overlayName: overlayName
        )
    }

    public func appendDiagnosticsLog(
        existingText: String,
        message: String
    ) -> DiagnosticsLogAppendResult {
        diagnosticsLogBufferService.append(
            existingText: existingText,
            message: message
        )
    }

    public func clampLayerIndex(_ value: Int, totalLayers: Int) -> Int {
        layerSelectionService.clamp(value, totalLayers: totalLayers)
    }

    public func resolveLayerSelectionUpdate(
        current: Int,
        requested: Int,
        totalLayers: Int,
        forceApply: Bool
    ) -> LayerSelectionUpdate? {
        layerSelectionService.resolveUpdate(
            current: current,
            requested: requested,
            totalLayers: totalLayers,
            forceApply: forceApply
        )
    }

    public func deriveTrackedLayer(
        from pressed: [[Bool]],
        dump: VialKeymapDump,
        baseLayer: Int
    ) -> Int {
        activeLayerTrackingService.deriveTrackedLayer(
            from: pressed,
            dump: dump,
            baseLayer: baseLayer
        )
    }

    public func makeActiveLayerPollingTask(
        poll: @escaping @Sendable () async -> Bool
    ) -> Task<Void, Never> {
        activeLayerPollingService.makePollingTask(poll: poll)
    }

    public func runResolveActiveLayerPollResult(
        _ result: Result<VialSwitchMatrixState, VialProbeError>,
        dump: VialKeymapDump,
        baseLayer: Int,
        failureCount: Int
    ) -> ActiveLayerPollWorkflowResult {
        switch result {
        case let .success(state):
            let trackedLayer = deriveTrackedLayer(
                from: state.pressed,
                dump: dump,
                baseLayer: baseLayer
            )
            let isAnyKeyPressed = state.pressed.contains { row in row.contains(true) }
            return ActiveLayerPollWorkflowResult(
                trackedLayer: trackedLayer,
                isAnyKeyPressed: isAnyKeyPressed,
                nextFailureCount: 0,
                diagnosticMessage: nil
            )
        case let .failure(.message(message)):
            let nextFailureCount = failureCount + 1
            let shouldEmit = nextFailureCount == 1 || nextFailureCount.isMultiple(of: 20)
            return ActiveLayerPollWorkflowResult(
                trackedLayer: nil,
                isAnyKeyPressed: false,
                nextFailureCount: nextFailureCount,
                diagnosticMessage: shouldEmit
                    ? activeLayerTrackingFailureDiagnosticMessage(message)
                    : nil
            )
        }
    }

    public nonisolated func runVialProbeAsync(on device: HIDKeyboardDevice) async -> VialProbeWorkflowResult {
        let result = await probeVialAsync(on: device)
        let presentation = await MainActor.run { presentVialProbeResult(result) }
        switch result {
        case let .success(probe):
            return VialProbeWorkflowResult(
                presentation: presentation,
                probe: probe
            )
        case .failure:
            return VialProbeWorkflowResult(
                presentation: presentation,
                probe: nil
            )
        }
    }

    public nonisolated func runReadVialKeymapAsync(
        on device: HIDKeyboardDevice,
        rows: Int,
        cols: Int
    ) async -> VialKeymapWorkflowResult {
        let result = await readVialKeymapAsync(on: device, rows: rows, cols: cols)
        let presentation = await MainActor.run { presentVialKeymapReadResult(result) }
        switch result {
        case let .success(dump):
            return VialKeymapWorkflowResult(
                presentation: presentation,
                dump: dump
            )
        case .failure:
            return VialKeymapWorkflowResult(
                presentation: presentation,
                dump: nil
            )
        }
    }

    public nonisolated func runInferVialMatrixAsync(on device: HIDKeyboardDevice) async -> VialMatrixWorkflowResult {
        let result = await inferVialMatrixAsync(on: device)
        let presentation = await MainActor.run { presentVialMatrixInferenceResult(result) }
        return VialMatrixWorkflowResult(presentation: presentation)
    }

    public nonisolated func runReadVialDefinitionAsync(on device: HIDKeyboardDevice) async -> VialDefinitionWorkflowResult {
        let result = await readVialDefinitionAsync(on: device)
        switch result {
        case let .success(prettyJSON):
            let suggestedFileName = await MainActor.run { suggestedVialDefinitionFileName(for: device) }
            return .success(prettyJSON: prettyJSON, suggestedFileName: suggestedFileName)
        case let .failure(.message(message)):
            let presentation = await MainActor.run { presentVialDefinitionReadFailure(message) }
            return .failure(presentation)
        }
    }

    public func runExportVialDefinitionAsync(on device: HIDKeyboardDevice) async -> VialDefinitionPresentation {
        let workflow = await runReadVialDefinitionAsync(on: device)
        switch workflow {
        case let .success(prettyJSON, suggestedFileName):
            do {
                try vialDefinitionValidationService.validate(prettyJSON)
            } catch {
                return presentVialDefinitionValidationFailure(error.localizedDescription)
            }
            let saveResult = saveTextFile(
                SaveFileRequest(
                    suggestedFileName: suggestedFileName,
                    allowedExtensions: ["json"],
                    title: "vial.json を保存",
                    content: prettyJSON
                )
            )
            return presentVialDefinitionSaveResult(saveResult)
        case let .failure(presentation):
            return presentation
        }
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

    public func runSetLaunchAtLogin(_ enabled: Bool) -> LaunchAtLoginWorkflowResult {
        switch setLaunchAtLoginEnabled(enabled) {
        case let .success(updated):
            return LaunchAtLoginWorkflowResult(
                enabled: updated,
                diagnosticMessage: launchAtLoginUpdatedDiagnosticMessage(enabled: updated)
            )
        case let .failure(.message(message)):
            let fallbackEnabled: Bool
            switch launchAtLoginStatus() {
            case let .success(status):
                fallbackEnabled = status
            case .failure:
                fallbackEnabled = false
            }
            return LaunchAtLoginWorkflowResult(
                enabled: fallbackEnabled,
                diagnosticMessage: launchAtLoginUpdateFailureDiagnosticMessage(message)
            )
        }
    }

    public func runRefreshLaunchAtLoginStatus() -> LaunchAtLoginStatusWorkflowResult {
        switch launchAtLoginStatus() {
        case let .success(enabled):
            return LaunchAtLoginStatusWorkflowResult(
                enabled: enabled,
                diagnosticMessage: nil
            )
        case let .failure(.message(message)):
            return LaunchAtLoginStatusWorkflowResult(
                enabled: false,
                diagnosticMessage: launchAtLoginStatusFailureDiagnosticMessage(message)
            )
        }
    }

    public func runStartupLifecycle(
        hasStarted: Bool,
        isShuttingDown: Bool
    ) -> StartupLifecycleWorkflowResult {
        guard !hasStarted, !isShuttingDown else {
            return StartupLifecycleWorkflowResult(
                shouldStart: false,
                permissionStatusText: nil
            )
        }
        let accessStatus = inputAccessStatus(
            promptAccessibility: true,
            requestInputMonitoring: true
        )
        return StartupLifecycleWorkflowResult(
            shouldStart: true,
            permissionStatusText: permissionStatusText(for: accessStatus)
        )
    }

    public func runPrepareStartupAutoLoad(
        hasAutoLoadedOnStartup: Bool,
        hasSelectedKeyboard: Bool,
        isDiagnosticsRunning: Bool,
        rowsText: String,
        colsText: String
    ) -> StartupAutoLoadPreparationResult {
        guard !hasAutoLoadedOnStartup else {
            return StartupAutoLoadPreparationResult(
                shouldRun: false,
                nextHasAutoLoadedOnStartup: true,
                statusText: nil,
                initialRows: nil,
                initialCols: nil
            )
        }
        guard hasSelectedKeyboard, !isDiagnosticsRunning else {
            return StartupAutoLoadPreparationResult(
                shouldRun: false,
                nextHasAutoLoadedOnStartup: false,
                statusText: nil,
                initialRows: nil,
                initialCols: nil
            )
        }
        let initialMatrix = resolveInitialMatrixSize(
            rowsText: rowsText,
            colsText: colsText
        )
        return StartupAutoLoadPreparationResult(
            shouldRun: true,
            nextHasAutoLoadedOnStartup: true,
            statusText: startupAutoLoadInProgressStatusText(),
            initialRows: initialMatrix.rows,
            initialCols: initialMatrix.cols
        )
    }

    public func runPrepareApplySettings(
        targetKeyCodeText: String,
        longPressDuration: Double,
        overlayShowAnimationDuration: Double,
        overlayHideAnimationDuration: Double,
        showSettingsOnLaunch: Bool
    ) -> ApplySettingsPreparationResult {
        guard let keyCodeValue = parseTargetKeyCode(targetKeyCodeText) else {
            return .failure(permissionStatusText: invalidTargetKeyCodeMessage())
        }

        saveAppPreferences(
            targetKeyCode: Int(keyCodeValue),
            longPressDuration: longPressDuration,
            overlayShowAnimationDuration: overlayShowAnimationDuration,
            overlayHideAnimationDuration: overlayHideAnimationDuration
        )
        setShowSettingsOnLaunch(showSettingsOnLaunch)
        updateOverlayAnimationDurations(
            show: overlayShowAnimationDuration,
            hide: overlayHideAnimationDuration
        )
        return .success(
            configuration: GlobalKeyMonitorConfiguration(
                targetKeyCode: keyCodeValue,
                longPressThreshold: longPressDuration
            )
        )
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

    public func parseMatrixSize(rowsText: String, colsText: String) -> (rows: Int, cols: Int)? {
        guard
            let rows = Int(rowsText),
            let cols = Int(colsText),
            rows > 0,
            cols > 0
        else {
            return nil
        }
        return (rows, cols)
    }

    public func resolveInitialMatrixSize(
        rowsText: String,
        colsText: String,
        defaultRows: Int = 6,
        defaultCols: Int = 17
    ) -> (rows: Int, cols: Int) {
        guard let parsed = parseMatrixSize(rowsText: rowsText, colsText: colsText) else {
            return (rows: defaultRows, cols: defaultCols)
        }
        return parsed
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

    public func launchAtLoginUpdatedDiagnosticMessage(enabled: Bool) -> String {
        "自動起動設定を更新: \(enabled ? "ON" : "OFF")"
    }

    public func launchAtLoginUpdateFailureDiagnosticMessage(_ detail: String) -> String {
        "自動起動設定の更新失敗: \(detail)"
    }

    public func launchAtLoginStatusFailureDiagnosticMessage(_ detail: String) -> String {
        "自動起動状態の取得失敗: \(detail)"
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

    public func runStartGlobalMonitoring(
        configuration: GlobalKeyMonitorConfiguration,
        onLongPressStart: @escaping @Sendable () -> Void,
        onLongPressEnd: @escaping @Sendable () -> Void
    ) -> GlobalMonitoringWorkflowResult {
        switch startGlobalKeyMonitoring(
            configuration,
            onLongPressStart: onLongPressStart,
            onLongPressEnd: onLongPressEnd
        ) {
        case let .success(session):
            return GlobalMonitoringWorkflowResult(
                session: session,
                permissionStatusText: monitoringStatusText(
                    targetKeyCode: configuration.targetKeyCode,
                    longPressDuration: configuration.longPressThreshold
                )
            )
        case .failure:
            return GlobalMonitoringWorkflowResult(
                session: nil,
                permissionStatusText: monitoringStartFailureStatusText()
            )
        }
    }

    public func runRestartGlobalMonitoring(
        existingSession: GlobalKeyMonitorSession?,
        configuration: GlobalKeyMonitorConfiguration,
        onLongPressStart: @escaping @Sendable () -> Void,
        onLongPressEnd: @escaping @Sendable () -> Void
    ) -> RestartGlobalMonitoringWorkflowResult {
        if let existingSession {
            stopGlobalKeyMonitoring(existingSession)
        }
        let workflow = runStartGlobalMonitoring(
            configuration: configuration,
            onLongPressStart: onLongPressStart,
            onLongPressEnd: onLongPressEnd
        )
        return RestartGlobalMonitoringWorkflowResult(
            session: workflow.session,
            permissionStatusText: workflow.permissionStatusText
        )
    }

    public func runStartKeyboardHotplugMonitoring(
        onChanged: @escaping @Sendable () -> Void
    ) -> KeyboardHotplugWorkflowResult {
        switch startKeyboardHotplugMonitoring(onChanged: onChanged) {
        case let .success(session):
            return KeyboardHotplugWorkflowResult(
                session: session,
                diagnosticMessage: nil
            )
        case .failure:
            return KeyboardHotplugWorkflowResult(
                session: nil,
                diagnosticMessage: keyboardHotplugStartFailureDiagnosticMessage()
            )
        }
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
