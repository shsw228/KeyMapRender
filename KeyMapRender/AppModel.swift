import Combine
import DataSource
import Model
import OSLog
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private struct ActiveLayerPollingContext {
        let selected: HIDKeyboardDevice
        let dump: VialKeymapDump
        let baseLayer: Int
    }

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
        applyPermissionStatusTextIfPresent(workflow.permissionStatusText)
        refreshKeyboards()
        startKeyboardHotplugMonitor()
        refreshLaunchAtLoginStatus()
        applySettings()
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        stopMonitoringSessions()
        hideOverlayAndStopTracking(restoreManualLayer: false)
    }

    func refreshLaunchAtLoginStatus() {
        let workflow = rootStore.runRefreshLaunchAtLoginStatus()
        applyLaunchAtLoginState(
            enabled: workflow.enabled,
            diagnosticMessage: workflow.diagnosticMessage
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let workflow = rootStore.runSetLaunchAtLogin(enabled)
        applyLaunchAtLoginState(
            enabled: workflow.enabled,
            diagnosticMessage: workflow.diagnosticMessage
        )
    }

    func setShowSettingsOnLaunch(_ enabled: Bool) {
        rootStore.setShowSettingsOnLaunch(enabled)
        showSettingsOnLaunch = enabled
    }

    func applySettings() {
        guard !isShuttingDown else { return }
        guard let configuration = resolveMonitoringConfiguration() else { return }
        let callbacks = makeLongPressCallbacks()
        let workflow = rootStore.runRestartGlobalMonitoring(
            existingSession: globalKeyMonitorSession,
            configuration: configuration,
            onLongPressStart: callbacks.onStart,
            onLongPressEnd: callbacks.onEnd
        )
        applyRestartMonitoringWorkflow(workflow)
    }

    func refreshKeyboards() {
        let snapshot = rootStore.refreshKeyboardSnapshot(currentSelectedID: selectedKeyboardID)
        applyKeyboardSnapshotAndAutoLoadIfNeeded(snapshot)
    }

    func probeVialOnSelectedKeyboard() {
        runSelectedKeyboardWorkflow(
            statusKeyPath: \.vialStatusText,
            initialStatusText: rootStore.vialProbeInProgressStatusText()
        ) { model, selected in
            await model.rootStore.runVialProbeAsync(on: selected)
        } apply: { model, workflow in
            model.applyVialPresentation(
                statusText: workflow.presentation.vialStatusText,
                diagnosticMessage: workflow.presentation.diagnosticMessage
            )
            if workflow.probe != nil {
                model.applyAvailableLayerCountIfPresent(workflow.presentation.availableLayerCount)
                model.setSelectedLayerIndex(model.selectedLayerIndex)
            }
        }
    }

    func readFullVialKeymapOnSelectedKeyboard() {
        guard let matrix = rootStore.parseMatrixSize(rowsText: matrixRowsText, colsText: matrixColsText) else {
            keymapStatusText = rootStore.matrixInputValidationFailureMessage()
            return
        }
        runSelectedKeyboardWorkflow(
            initialStatusText: rootStore.keymapReadInProgressStatusText()
        ) { model, selected in
            await model.rootStore.runReadVialKeymapAsync(
                on: selected,
                rows: matrix.rows,
                cols: matrix.cols
            )
        } apply: { model, workflow in
            model.applyKeymapPresentationResult(
                statusText: workflow.presentation.keymapStatusText,
                diagnosticMessage: workflow.presentation.diagnosticMessage,
                dump: workflow.dump,
                availableLayerCountOverride: workflow.presentation.availableLayerCount
            )
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
        applySelectedLayerRenderWorkflow(workflow)
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
        applySelectedLayerToLatestDumpIfNeeded()
        appendDiagnosticsIfPresent(workflow.diagnosticMessage)
    }

    func updateLayoutChoice(index: Int, selected: Int) {
        guard let pos = layoutChoices.firstIndex(where: { $0.id == index }) else { return }
        let range = 0..<layoutChoices[pos].options.count
        guard range.contains(selected) else { return }
        layoutChoices[pos].selected = selected
        applySelectedLayerToLatestDumpIfNeeded()
    }

    func autoDetectMatrixOnSelectedKeyboard() {
        runSelectedKeyboardWorkflow(
            initialStatusText: rootStore.matrixInferenceInProgressStatusText()
        ) { model, selected in
            await model.rootStore.runInferVialMatrixAsync(on: selected)
        } apply: { model, workflow in
            model.applyKeymapPresentationResult(
                statusText: workflow.presentation.keymapStatusText,
                diagnosticMessage: workflow.presentation.diagnosticMessage,
                rows: workflow.presentation.matrixRows,
                cols: workflow.presentation.matrixCols
            )
        }
    }

    func exportVialDefinitionOnSelectedKeyboard() {
        runSelectedKeyboardWorkflow(
            initialStatusText: rootStore.vialDefinitionReadInProgressStatusText()
        ) { model, selected in
            await model.rootStore.runExportVialDefinitionAsync(on: selected)
        } apply: { model, presentation in
            model.applyKeymapPresentationResult(
                statusText: presentation.keymapStatusText,
                diagnosticMessage: presentation.diagnosticMessage
            )
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
        applyKeyboardIgnoreWorkflow(workflow)
    }

    func clearIgnoredKeyboards() {
        let workflow = rootStore.runClearIgnoredDevicesAndRefresh(
            currentSelectedID: selectedKeyboardID
        )
        applyKeyboardIgnoreWorkflow(workflow)
    }

    private func startActiveLayerTrackingIfNeeded() {
        guard canStartActiveLayerTracking else { return }

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
        guard let context = makeActiveLayerPollingContext(generation: generation) else { return false }

        let result = await rootStore.readVialSwitchMatrixStateAsync(
            on: context.selected,
            rows: context.dump.matrixRows,
            cols: context.dump.matrixCols
        )

        guard isActiveLayerPollingContextValid(generation: generation) else { return false }

        let workflow = rootStore.runResolveActiveLayerPollResult(
            result,
            dump: context.dump,
            baseLayer: context.baseLayer,
            failureCount: matrixPollFailureCount
        )
        return applyActiveLayerPollWorkflow(workflow)
    }

    private func isActiveLayerPollingContextValid(generation: UInt64) -> Bool {
        guard generation == activeLayerTrackingGeneration else { return false }
        guard !Task.isCancelled else { return false }
        guard !isShuttingDown else { return false }
        guard isOverlayVisible else { return false }
        return true
    }

    private var canStartActiveLayerTracking: Bool {
        guard isOverlayVisible else { return false }
        guard latestKeymapDump != nil else { return false }
        guard selectedKeyboard != nil else { return false }
        return activeLayerTrackingTask == nil
    }

    private func makeActiveLayerPollingContext(generation: UInt64) -> ActiveLayerPollingContext? {
        guard isActiveLayerPollingContextValid(generation: generation) else { return nil }
        guard let selected = selectedKeyboard else { return nil }
        guard let dump = latestKeymapDump else { return nil }
        return ActiveLayerPollingContext(
            selected: selected,
            dump: dump,
            baseLayer: manualSelectedLayerIndex
        )
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

    private func appendDiagnostics(_ messages: [String]) {
        for message in messages {
            appendDiagnostics(message)
        }
    }

    private func appendDiagnosticsIfPresent(_ message: String?) {
        guard let message else { return }
        appendDiagnostics(message)
    }

    private func applyKeymapPresentation(statusText: String, diagnosticMessage: String) {
        applyStatusAndDiagnostics(
            statusKeyPath: \.keymapStatusText,
            statusText: statusText,
            diagnosticMessage: diagnosticMessage
        )
    }

    private func applyVialPresentation(statusText: String, diagnosticMessage: String) {
        applyStatusAndDiagnostics(
            statusKeyPath: \.vialStatusText,
            statusText: statusText,
            diagnosticMessage: diagnosticMessage
        )
    }

    private func applyStatusAndDiagnostics(
        statusKeyPath: ReferenceWritableKeyPath<AppModel, String>,
        statusText: String,
        diagnosticMessage: String
    ) {
        self[keyPath: statusKeyPath] = statusText
        appendDiagnostics(diagnosticMessage)
    }

    private func applySelectedLayerRenderWorkflow(_ workflow: RootStore.SelectedLayerRenderWorkflowResult) {
        keymapPreviewText = workflow.keymapPreviewText
        layout = workflow.layout
        refreshOverlayIfVisible()
        appendDiagnostics(workflow.diagnosticMessages)
    }

    private func applyActiveLayerPollWorkflow(_ workflow: RootStore.ActiveLayerPollWorkflowResult) -> Bool {
        matrixPollFailureCount = workflow.nextFailureCount
        if let trackedLayer = workflow.trackedLayer {
            setDisplayedLayerIndex(trackedLayer, reason: "押下追従", emitLog: false)
        }
        appendDiagnosticsIfPresent(workflow.diagnosticMessage)
        return workflow.isAnyKeyPressed
    }

    private func applyKeymapPresentationResult(
        statusText: String,
        diagnosticMessage: String,
        rows: Int? = nil,
        cols: Int? = nil,
        dump: VialKeymapDump? = nil,
        availableLayerCountOverride: Int? = nil
    ) {
        applyKeymapPresentation(statusText: statusText, diagnosticMessage: diagnosticMessage)
        applyMatrixSizeIfPresent(rows: rows, cols: cols)
        adoptKeymapDumpIfPresent(dump, availableLayerCountOverride: availableLayerCountOverride)
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

    private func applyKeyboardIgnoreWorkflow(_ workflow: RootStore.KeyboardIgnoreWorkflowResult) {
        applyKeyboardSnapshotAndAutoLoadIfNeeded(workflow.snapshot)
        appendDiagnostics(workflow.diagnosticMessage)
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
            self?.runMainActorTask { model in
                guard !model.isShuttingDown else { return }
                model.refreshKeyboards()
            }
        }
        if let session = workflow.session {
            keyboardHotplugSession = session
        } else {
            appendDiagnosticsIfPresent(workflow.diagnosticMessage)
        }
    }

    private func autoLoadKeymapIfPossibleOnStartup() {
        guard let context = prepareStartupAutoLoadContext() else { return }
        keymapStatusText = context.statusText
        runDiagnosticsTask { model in
            let workflow = await model.rootStore.runStartupKeymapLoadAsync(
                on: context.selected,
                initialRows: context.initialRows,
                initialCols: context.initialCols
            )
            model.applyIfNotShuttingDown {
                model.applyStartupKeymapPresentation(workflow.presentation, dump: workflow.dump)
            }
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
        hideOverlayAndStopTracking(restoreManualLayer: true)
    }

    private func restoreManualDisplayedLayerOnOverlayEnd() {
        setDisplayedLayerIndex(manualSelectedLayerIndex, reason: "長押し終了", emitLog: false)
    }

    private func hideOverlayAndStopTracking(restoreManualLayer: Bool) {
        isOverlayVisible = false
        stopActiveLayerTracking()
        if restoreManualLayer {
            restoreManualDisplayedLayerOnOverlayEnd()
        }
        rootStore.hideOverlay()
    }

    private func applySelectedLayerToLatestDumpIfNeeded() {
        guard latestKeymapDump != nil else { return }
        applySelectedLayerToLatestDump()
    }

    private func applyMatrixSize(rows: Int, cols: Int) {
        matrixRowsText = "\(rows)"
        matrixColsText = "\(cols)"
    }

    private func applyMatrixSizeIfPresent(rows: Int?, cols: Int?) {
        guard let rows, let cols else { return }
        applyMatrixSize(rows: rows, cols: cols)
    }

    private func applyAvailableLayerCountIfPresent(_ count: Int?) {
        guard let count else { return }
        availableLayerCount = count
    }

    private func adoptKeymapDumpIfPresent(
        _ dump: VialKeymapDump?,
        availableLayerCountOverride: Int? = nil
    ) {
        guard let dump else { return }
        adoptKeymapDump(dump, availableLayerCountOverride: availableLayerCountOverride)
    }

    private func applyStartupKeymapPresentation(
        _ presentation: RootStore.StartupKeymapPresentation,
        dump: VialKeymapDump?
    ) {
        appendDiagnostics(presentation.matrixDiagnosticMessage)
        applyKeymapPresentationResult(
            statusText: presentation.keymapStatusText,
            diagnosticMessage: presentation.completionDiagnosticMessage,
            rows: presentation.matrixRows,
            cols: presentation.matrixCols,
            dump: dump
        )
    }

    private func prepareStartupAutoLoadContext() -> (selected: HIDKeyboardDevice, initialRows: Int, initialCols: Int, statusText: String)? {
        let preparation = rootStore.runPrepareStartupAutoLoad(
            hasAutoLoadedOnStartup: hasAutoLoadedOnStartup,
            hasSelectedKeyboard: selectedKeyboard != nil,
            isDiagnosticsRunning: isDiagnosticsRunning,
            rowsText: matrixRowsText,
            colsText: matrixColsText
        )
        guard preparation.shouldRun else {
            hasAutoLoadedOnStartup = preparation.nextHasAutoLoadedOnStartup
            return nil
        }
        guard let selected = selectedKeyboard,
              let initialRows = preparation.initialRows,
              let initialCols = preparation.initialCols,
              let statusText = preparation.statusText
        else { return nil }
        hasAutoLoadedOnStartup = preparation.nextHasAutoLoadedOnStartup
        return (selected, initialRows, initialCols, statusText)
    }

    private func applyPermissionStatusTextIfPresent(_ statusText: String?) {
        guard let statusText else { return }
        permissionStatusText = statusText
    }

    private func resolveMonitoringConfiguration() -> GlobalKeyMonitorConfiguration? {
        let preparation = rootStore.runPrepareApplySettings(
            targetKeyCodeText: targetKeyCodeText,
            longPressDuration: longPressDuration,
            overlayShowAnimationDuration: overlayShowAnimationDuration,
            overlayHideAnimationDuration: overlayHideAnimationDuration,
            showSettingsOnLaunch: showSettingsOnLaunch
        )
        switch preparation {
        case let .success(configuration):
            return configuration
        case let .failure(permissionStatusText):
            self.permissionStatusText = permissionStatusText
            return nil
        }
    }

    private func applyRestartMonitoringWorkflow(_ workflow: RootStore.RestartGlobalMonitoringWorkflowResult) {
        globalKeyMonitorSession = workflow.session
        permissionStatusText = workflow.permissionStatusText
    }

    private func makeLongPressCallbacks() -> (onStart: @Sendable () -> Void, onEnd: @Sendable () -> Void) {
        let onStart: @Sendable () -> Void = { [weak self] in
            self?.runMainActorTask { model in
                model.handleOverlayLongPressStart()
            }
        }
        let onEnd: @Sendable () -> Void = { [weak self] in
            self?.runMainActorTask { model in
                model.handleOverlayLongPressEnd()
            }
        }
        return (onStart, onEnd)
    }

    private func applyLaunchAtLoginState(enabled: Bool, diagnosticMessage: String?) {
        launchAtLoginEnabled = enabled
        appendDiagnosticsIfPresent(diagnosticMessage)
    }

    private func applyIfNotShuttingDown(_ operation: () -> Void) {
        guard !isShuttingDown else { return }
        operation()
    }

    private func stopMonitoringSessions() {
        if let keyboardHotplugSession {
            rootStore.stopKeyboardHotplugMonitoring(keyboardHotplugSession)
            self.keyboardHotplugSession = nil
        }
        if let globalKeyMonitorSession {
            rootStore.stopGlobalKeyMonitoring(globalKeyMonitorSession)
            self.globalKeyMonitorSession = nil
        }
    }

    private func runDiagnosticsTask(_ operation: @escaping @MainActor (AppModel) async -> Void) {
        isDiagnosticsRunning = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDiagnosticsRunning = false }
            await operation(self)
        }
    }

    private func runSelectedKeyboardWorkflow<Workflow>(
        statusKeyPath: ReferenceWritableKeyPath<AppModel, String> = \.keymapStatusText,
        initialStatusText: String,
        missingMessage: String? = nil,
        operation: @escaping @MainActor (AppModel, HIDKeyboardDevice) async -> Workflow,
        apply: @escaping @MainActor (AppModel, Workflow) -> Void
    ) {
        guard let selected = requireSelectedKeyboard(
            statusKeyPath: statusKeyPath,
            missingMessage: missingMessage
        ) else { return }
        self[keyPath: statusKeyPath] = initialStatusText
        runDiagnosticsTask { model in
            let workflow = await operation(model, selected)
            model.applyIfNotShuttingDown {
                apply(model, workflow)
            }
        }
    }

    private nonisolated func runMainActorTask(_ operation: @escaping @MainActor (AppModel) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            operation(self)
        }
    }
}
