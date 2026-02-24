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
        let workflow = rootStore.runStartupLifecycle(
            hasStarted: hasStarted,
            isShuttingDown: isShuttingDown
        )
        guard workflow.shouldStart else { return }
        hasStarted = true
        if let permissionStatusText = workflow.permissionStatusText {
            self.permissionStatusText = permissionStatusText
        }
        refreshKeyboards()
        startKeyboardHotplugMonitor()
        refreshLaunchAtLoginStatus()
        applySettings()
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
        let workflow = rootStore.runRefreshLaunchAtLoginStatus()
        launchAtLoginEnabled = workflow.enabled
        if let diagnosticMessage = workflow.diagnosticMessage {
            appendDiagnostics(diagnosticMessage)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let workflow = rootStore.runSetLaunchAtLogin(enabled)
        launchAtLoginEnabled = workflow.enabled
        appendDiagnostics(workflow.diagnosticMessage)
    }

    func setShowSettingsOnLaunch(_ enabled: Bool) {
        rootStore.setShowSettingsOnLaunch(enabled)
        showSettingsOnLaunch = enabled
    }

    func applySettings() {
        guard !isShuttingDown else { return }
        let preparation = rootStore.runPrepareApplySettings(
            targetKeyCodeText: targetKeyCodeText,
            longPressDuration: longPressDuration,
            overlayShowAnimationDuration: overlayShowAnimationDuration,
            overlayHideAnimationDuration: overlayHideAnimationDuration,
            showSettingsOnLaunch: showSettingsOnLaunch
        )
        let configuration: GlobalKeyMonitorConfiguration
        switch preparation {
        case let .success(value):
            configuration = value
        case let .failure(permissionStatusText):
            self.permissionStatusText = permissionStatusText
            return
        }

        let monitorWorkflow = rootStore.runRestartGlobalMonitoring(
            existingSession: globalKeyMonitorSession,
            configuration: configuration,
            onLongPressStart: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.handleOverlayLongPressStart()
                }
            },
            onLongPressEnd: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.handleOverlayLongPressEnd()
                }
            }
        )
        globalKeyMonitorSession = monitorWorkflow.session
        permissionStatusText = monitorWorkflow.permissionStatusText
    }

    func refreshKeyboards() {
        let snapshot = rootStore.refreshKeyboardSnapshot(currentSelectedID: selectedKeyboardID)
        applyKeyboardSnapshotAndAutoLoadIfNeeded(snapshot)
    }

    func probeVialOnSelectedKeyboard() {
        guard let selected = requireSelectedKeyboard(statusKeyPath: \.vialStatusText) else { return }
        vialStatusText = rootStore.vialProbeInProgressStatusText()
        runDiagnosticsTask { model in
            let workflow = await model.rootStore.runVialProbeAsync(on: selected)
            guard !model.isShuttingDown else { return }
            model.vialStatusText = workflow.presentation.vialStatusText
            model.appendDiagnostics(workflow.presentation.diagnosticMessage)
            if workflow.probe != nil {
                if let availableLayerCount = workflow.presentation.availableLayerCount {
                    model.availableLayerCount = availableLayerCount
                }
                model.setSelectedLayerIndex(model.selectedLayerIndex)
            }
        }
    }

    func readFullVialKeymapOnSelectedKeyboard() {
        guard let selected = requireSelectedKeyboard(statusKeyPath: \.keymapStatusText) else { return }
        guard let matrix = rootStore.parseMatrixSize(rowsText: matrixRowsText, colsText: matrixColsText) else {
            keymapStatusText = rootStore.matrixInputValidationFailureMessage()
            return
        }
        keymapStatusText = rootStore.keymapReadInProgressStatusText()
        runDiagnosticsTask { model in
            let workflow = await model.rootStore.runReadVialKeymapAsync(
                on: selected,
                rows: matrix.rows,
                cols: matrix.cols
            )
            guard !model.isShuttingDown else { return }
            model.keymapStatusText = workflow.presentation.keymapStatusText
            model.appendDiagnostics(workflow.presentation.diagnosticMessage)
            if let dump = workflow.dump {
                model.adoptKeymapDump(
                    dump,
                    availableLayerCountOverride: workflow.presentation.availableLayerCount
                )
            }
        }
    }

    func applySelectedLayerToLatestDump() {
        guard let dump = latestKeymapDump else { return }
        let workflow = rootStore.runRenderSelectedLayer(
            dump: dump,
            selectedLayerIndex: selectedLayerIndex,
            availableLayerCount: availableLayerCount,
            selectedLayoutChoices: layoutChoices,
            overlayName: currentOverlayKeyboardName(),
            isOverlayVisible: isOverlayVisible
        )
        keymapPreviewText = workflow.keymapPreviewText
        layout = workflow.layout
        refreshOverlayIfVisible()
        for message in workflow.diagnosticMessages {
            appendDiagnostics(message)
        }
    }

    func setSelectedLayerIndex(_ newValue: Int) {
        let clamped = rootStore.clampLayerIndex(
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
        guard let workflow = rootStore.runResolveDisplayedLayerSelection(
            current: selectedLayerIndex,
            requested: newValue,
            totalLayers: availableLayerCount,
            forceApply: forceApply,
            reason: reason,
            emitLog: emitLog
        ) else { return }
        selectedLayerIndex = workflow.clampedLayer
        applySelectedLayerToLatestDump()
        if let diagnosticMessage = workflow.diagnosticMessage {
            appendDiagnostics(diagnosticMessage)
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
        guard let selected = requireSelectedKeyboard(statusKeyPath: \.keymapStatusText) else { return }
        keymapStatusText = rootStore.matrixInferenceInProgressStatusText()
        runDiagnosticsTask { model in
            let workflow = await model.rootStore.runInferVialMatrixAsync(on: selected)
            guard !model.isShuttingDown else { return }
            model.keymapStatusText = workflow.presentation.keymapStatusText
            model.appendDiagnostics(workflow.presentation.diagnosticMessage)
            if let rows = workflow.presentation.matrixRows, let cols = workflow.presentation.matrixCols {
                model.applyMatrixSize(rows: rows, cols: cols)
            }
        }
    }

    func exportVialDefinitionOnSelectedKeyboard() {
        guard let selected = requireSelectedKeyboard(statusKeyPath: \.keymapStatusText) else { return }
        keymapStatusText = rootStore.vialDefinitionReadInProgressStatusText()
        runDiagnosticsTask { model in
            let presentation = await model.rootStore.runExportVialDefinitionAsync(on: selected)
            guard !model.isShuttingDown else { return }
            model.keymapStatusText = presentation.keymapStatusText
            model.appendDiagnostics(presentation.diagnosticMessage)
        }
    }

    func copyDiagnosticsLog() {
        rootStore.copyToClipboard(diagnosticsLogText)
    }

    func ignoreSelectedKeyboard() {
        guard let selected = requireSelectedKeyboard(
            statusKeyPath: \.keyboardStatusText,
            missingMessage: rootStore.ignoredKeyboardSelectionRequiredMessage()
        ) else { return }
        let workflow = rootStore.runIgnoreDeviceAndRefresh(
            selected,
            currentSelectedID: selectedKeyboardID
        )
        applyKeyboardSnapshotAndAutoLoadIfNeeded(workflow.snapshot)
        appendDiagnostics(workflow.diagnosticMessage)
    }

    func clearIgnoredKeyboards() {
        let workflow = rootStore.runClearIgnoredDevicesAndRefresh(
            currentSelectedID: selectedKeyboardID
        )
        applyKeyboardSnapshotAndAutoLoadIfNeeded(workflow.snapshot)
        appendDiagnostics(workflow.diagnosticMessage)
    }

    private func startActiveLayerTrackingIfNeeded() {
        guard isOverlayVisible else { return }
        guard latestKeymapDump != nil else { return }
        guard selectedKeyboard != nil else { return }
        if activeLayerTrackingTask != nil { return }

        matrixPollFailureCount = 0
        activeLayerTrackingGeneration &+= 1
        let generation = activeLayerTrackingGeneration
        activeLayerTrackingTask = rootStore.makeActiveLayerPollingTask { [weak self] in
            guard let self else { return false }
            return await self.pollActiveLayerFromKeyboard(generation: generation)
        }
        appendDiagnostics(rootStore.activeLayerTrackingStartedDiagnosticMessage())
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

        let result = await rootStore.readVialSwitchMatrixStateAsync(
            on: selected,
            rows: dump.matrixRows,
            cols: dump.matrixCols
        )

        guard generation == activeLayerTrackingGeneration else { return false }
        guard !Task.isCancelled else { return false }
        guard isOverlayVisible else { return false }

        let workflow = rootStore.runResolveActiveLayerPollResult(
            result,
            dump: dump,
            baseLayer: baseLayer,
            failureCount: matrixPollFailureCount
        )
        matrixPollFailureCount = workflow.nextFailureCount
        if let trackedLayer = workflow.trackedLayer {
            setDisplayedLayerIndex(trackedLayer, reason: "押下追従", emitLog: false)
        }
        if let diagnosticMessage = workflow.diagnosticMessage {
            appendDiagnostics(diagnosticMessage)
        }
        return workflow.isAnyKeyPressed
    }

    private func appendDiagnostics(_ message: String) {
        let result = rootStore.appendDiagnosticsLog(
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

    private func applyKeyboardSnapshot(_ snapshot: RootStore.KeyboardRefreshResult) {
        connectedKeyboards = snapshot.connectedKeyboards
        selectedKeyboardID = snapshot.selectedKeyboardID
        keyboardStatusText = snapshot.keyboardStatusText
        ignoredDeviceCount = snapshot.ignoredDeviceCount
    }

    private func applyKeyboardSnapshotAndAutoLoadIfNeeded(_ snapshot: RootStore.KeyboardRefreshResult) {
        applyKeyboardSnapshot(snapshot)
        guard !connectedKeyboards.isEmpty else { return }
        autoLoadKeymapIfPossibleOnStartup()
    }

    private func currentOverlayKeyboardName() -> String {
        rootStore.overlayKeyboardName(for: selectedKeyboard)
    }

    private var selectedKeyboard: HIDKeyboardDevice? {
        connectedKeyboards.first(where: { $0.id == selectedKeyboardID })
    }

    private func requireSelectedKeyboard(
        statusKeyPath: ReferenceWritableKeyPath<AppModel, String>,
        missingMessage: String? = nil
    ) -> HIDKeyboardDevice? {
        guard let selected = selectedKeyboard else {
            self[keyPath: statusKeyPath] = missingMessage ?? rootStore.keyboardSelectionRequiredMessage()
            return nil
        }
        return selected
    }

    private func startKeyboardHotplugMonitor() {
        guard keyboardHotplugSession == nil else { return }
        let workflow = rootStore.runStartKeyboardHotplugMonitoring { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isShuttingDown else { return }
                self.refreshKeyboards()
            }
        }
        if let session = workflow.session {
            keyboardHotplugSession = session
        } else if let diagnosticMessage = workflow.diagnosticMessage {
            appendDiagnostics(diagnosticMessage)
        }
    }

    private func autoLoadKeymapIfPossibleOnStartup() {
        let preparation = rootStore.runPrepareStartupAutoLoad(
            hasAutoLoadedOnStartup: hasAutoLoadedOnStartup,
            hasSelectedKeyboard: selectedKeyboard != nil,
            isDiagnosticsRunning: isDiagnosticsRunning,
            rowsText: matrixRowsText,
            colsText: matrixColsText
        )
        guard preparation.shouldRun else {
            hasAutoLoadedOnStartup = preparation.nextHasAutoLoadedOnStartup
            return
        }
        guard let selected = selectedKeyboard else { return }
        guard let initialRows = preparation.initialRows,
              let initialCols = preparation.initialCols,
              let statusText = preparation.statusText
        else { return }

        hasAutoLoadedOnStartup = preparation.nextHasAutoLoadedOnStartup
        keymapStatusText = statusText
        runDiagnosticsTask { model in
            let workflow = await model.rootStore.runStartupKeymapLoadAsync(
                on: selected,
                initialRows: initialRows,
                initialCols: initialCols
            )
            guard !model.isShuttingDown else { return }
            model.appendDiagnostics(workflow.presentation.matrixDiagnosticMessage)
            if let rows = workflow.presentation.matrixRows, let cols = workflow.presentation.matrixCols {
                model.applyMatrixSize(rows: rows, cols: cols)
            }

            if let dump = workflow.dump {
                model.adoptKeymapDump(dump)
            }
            model.keymapStatusText = workflow.presentation.keymapStatusText
            model.appendDiagnostics(workflow.presentation.completionDiagnosticMessage)
        }
    }

    private func refreshOverlayIfVisible() {
        guard isOverlayVisible else { return }
        rootStore.showOverlay(
            layout: layout,
            currentLayer: selectedLayerIndex,
            totalLayers: availableLayerCount
        )
    }

    private func adoptKeymapDump(
        _ dump: VialKeymapDump,
        availableLayerCountOverride: Int? = nil
    ) {
        latestKeymapDump = dump
        let adoption = rootStore.runAdoptKeymapDump(dump)
        layoutChoices = adoption.layoutChoices
        availableLayerCount = availableLayerCountOverride ?? adoption.availableLayerCount
        setSelectedLayerIndex(selectedLayerIndex)
        startActiveLayerTrackingIfNeeded()
    }

    private func handleOverlayLongPressStart() {
        isOverlayVisible = true
        refreshOverlayIfVisible()
        startActiveLayerTrackingIfNeeded()
        appendDiagnostics(
            rootStore.overlayShownDiagnosticMessage(
                currentLayer: selectedLayerIndex,
                totalLayers: availableLayerCount
            )
        )
    }

    private func handleOverlayLongPressEnd() {
        isOverlayVisible = false
        stopActiveLayerTracking()
        setDisplayedLayerIndex(manualSelectedLayerIndex, reason: "長押し終了", emitLog: false)
        rootStore.hideOverlay()
    }

    private func applyMatrixSize(rows: Int, cols: Int) {
        matrixRowsText = "\(rows)"
        matrixColsText = "\(cols)"
    }

    private func runDiagnosticsTask(_ operation: @escaping @MainActor (AppModel) async -> Void) {
        isDiagnosticsRunning = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDiagnosticsRunning = false }
            await operation(self)
        }
    }
}
