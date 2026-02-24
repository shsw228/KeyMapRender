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
    private let keymapLayerRenderingService = KeymapLayerRenderingService()
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
        permissionStatusText = rootStore.permissionStatusText(for: accessStatus)
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
            appendDiagnostics(rootStore.launchAtLoginUpdatedDiagnosticMessage(enabled: updated))
        case let .failure(.message(message)):
            refreshLaunchAtLoginStatus()
            appendDiagnostics(rootStore.launchAtLoginUpdateFailureDiagnosticMessage(message))
        }
    }

    func setShowSettingsOnLaunch(_ enabled: Bool) {
        rootStore.setShowSettingsOnLaunch(enabled)
        showSettingsOnLaunch = enabled
    }

    func applySettings() {
        guard !isShuttingDown else { return }
        guard let keyCodeValue = rootStore.parseTargetKeyCode(targetKeyCodeText) else {
            permissionStatusText = rootStore.invalidTargetKeyCodeMessage()
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
                    self.appendDiagnostics(
                        self.rootStore.overlayShownDiagnosticMessage(
                            currentLayer: self.selectedLayerIndex,
                            totalLayers: self.availableLayerCount
                        )
                    )
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
            permissionStatusText = rootStore.monitoringStatusText(
                targetKeyCode: keyCodeValue,
                longPressDuration: longPressDuration
            )
        case .failure:
            permissionStatusText = rootStore.monitoringStartFailureStatusText()
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
            vialStatusText = rootStore.keyboardSelectionRequiredMessage()
            return
        }
        isDiagnosticsRunning = true
        vialStatusText = rootStore.vialProbeInProgressStatusText()
        Task { [weak self] in
            guard let self else { return }
            let result = await self.rootStore.probeVialAsync(on: selected)
            let presentation = self.rootStore.presentVialProbeResult(result)
            guard !self.isShuttingDown else { return }
            self.isDiagnosticsRunning = false
            self.vialStatusText = presentation.vialStatusText
            self.appendDiagnostics(presentation.diagnosticMessage)
            switch result {
            case .success:
                if let availableLayerCount = presentation.availableLayerCount {
                    self.availableLayerCount = availableLayerCount
                }
                self.setSelectedLayerIndex(self.selectedLayerIndex)
            case .failure:
                break
            }
        }
    }

    func readFullVialKeymapOnSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keymapStatusText = rootStore.keyboardSelectionRequiredMessage()
            return
        }
        guard let rows = Int(matrixRowsText), let cols = Int(matrixColsText), rows > 0, cols > 0 else {
            keymapStatusText = rootStore.matrixInputValidationFailureMessage()
            return
        }
        isDiagnosticsRunning = true
        keymapStatusText = rootStore.keymapReadInProgressStatusText()
        Task { [weak self] in
            guard let self else { return }
            let result = await self.rootStore.readVialKeymapAsync(on: selected, rows: rows, cols: cols)
            let presentation = self.rootStore.presentVialKeymapReadResult(result)
            guard !self.isShuttingDown else { return }
            self.isDiagnosticsRunning = false
            self.keymapStatusText = presentation.keymapStatusText
            self.appendDiagnostics(presentation.diagnosticMessage)
            switch result {
            case let .success(dump):
                self.latestKeymapDump = dump
                self.layoutChoices = self.vialPresentationService.makeLayoutChoices(from: dump)
                if let availableLayerCount = presentation.availableLayerCount {
                    self.availableLayerCount = availableLayerCount
                }
                self.setSelectedLayerIndex(self.selectedLayerIndex)
                self.startActiveLayerTrackingIfNeeded()
            case .failure:
                break
            }
        }
    }

    func applySelectedLayerToLatestDump() {
        guard let dump = latestKeymapDump else { return }
        let layer = max(0, min(selectedLayerIndex, dump.layerCount - 1))
        let renderResult = keymapLayerRenderingService.render(
            dump: dump,
            requestedLayer: layer,
            selectedLayoutChoices: layoutChoices,
            overlayName: currentOverlayKeyboardName()
        )
        keymapPreviewText = renderResult.keymapPreviewText
        layout = renderResult.layout
        if isOverlayVisible {
            rootStore.showOverlay(
                layout: layout,
                currentLayer: selectedLayerIndex,
                totalLayers: availableLayerCount
            )
            appendDiagnostics(
                rootStore.overlayUpdatedDiagnosticMessage(
                    currentLayer: selectedLayerIndex,
                    totalLayers: availableLayerCount
                )
            )
        }
        for message in renderResult.diagnosticMessages {
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
            appendDiagnostics(
                rootStore.displayLayerChangedDiagnosticMessage(
                    reason: reason,
                    currentLayer: selectedLayerIndex,
                    totalLayers: availableLayerCount
                )
            )
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
            keymapStatusText = rootStore.keyboardSelectionRequiredMessage()
            return
        }
        isDiagnosticsRunning = true
        keymapStatusText = rootStore.matrixInferenceInProgressStatusText()
        Task { [weak self] in
            guard let self else { return }
            let result = await self.rootStore.inferVialMatrixAsync(on: selected)
            let presentation = self.rootStore.presentVialMatrixInferenceResult(result)
            guard !self.isShuttingDown else { return }
            self.isDiagnosticsRunning = false
            self.keymapStatusText = presentation.keymapStatusText
            self.appendDiagnostics(presentation.diagnosticMessage)
            if let rows = presentation.matrixRows, let cols = presentation.matrixCols {
                self.matrixRowsText = "\(rows)"
                self.matrixColsText = "\(cols)"
            }
        }
    }

    func exportVialDefinitionOnSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keymapStatusText = rootStore.keyboardSelectionRequiredMessage()
            return
        }
        isDiagnosticsRunning = true
        keymapStatusText = rootStore.vialDefinitionReadInProgressStatusText()
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
                    let presentation = self.rootStore.presentVialDefinitionValidationFailure(error.localizedDescription)
                    self.keymapStatusText = presentation.keymapStatusText
                    self.appendDiagnostics(presentation.diagnosticMessage)
                    return
                }
                let suggestedName = self.rootStore.suggestedVialDefinitionFileName(for: selected)
                let saveResult = self.rootStore.saveTextFile(
                    SaveFileRequest(
                        suggestedFileName: suggestedName,
                        allowedExtensions: ["json"],
                        title: "vial.json を保存",
                        content: prettyJSON
                    )
                )
                let presentation = self.rootStore.presentVialDefinitionSaveResult(saveResult)
                self.keymapStatusText = presentation.keymapStatusText
                self.appendDiagnostics(presentation.diagnosticMessage)
            case let .failure(.message(message)):
                let presentation = self.rootStore.presentVialDefinitionReadFailure(message)
                self.keymapStatusText = presentation.keymapStatusText
                self.appendDiagnostics(presentation.diagnosticMessage)
            }
        }
    }

    func copyDiagnosticsLog() {
        rootStore.copyToClipboard(diagnosticsLogText)
    }

    func ignoreSelectedKeyboard() {
        guard let selected = selectedKeyboard else {
            keyboardStatusText = rootStore.ignoredKeyboardSelectionRequiredMessage()
            return
        }
        rootStore.addIgnoredDeviceID(selected.id)
        persistIgnoredDeviceCount()
        appendDiagnostics(rootStore.ignoredDeviceAddedDiagnosticMessage(selected))
        refreshKeyboards()
    }

    func clearIgnoredKeyboards() {
        rootStore.clearIgnoredDeviceIDs()
        persistIgnoredDeviceCount()
        appendDiagnostics(rootStore.ignoredDevicesClearedDiagnosticMessage())
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
                appendDiagnostics(rootStore.activeLayerTrackingFailureDiagnosticMessage(message))
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
        rootStore.overlayKeyboardName(for: selectedKeyboard)
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
            appendDiagnostics(rootStore.keyboardHotplugStartFailureDiagnosticMessage())
        }
    }

    private func autoLoadKeymapIfPossibleOnStartup() {
        guard !hasAutoLoadedOnStartup else { return }
        guard let selected = selectedKeyboard else { return }
        guard !isDiagnosticsRunning else { return }
        hasAutoLoadedOnStartup = true

        isDiagnosticsRunning = true
        keymapStatusText = rootStore.startupAutoLoadInProgressStatusText()
        let initialRows = Int(matrixRowsText) ?? 6
        let initialCols = Int(matrixColsText) ?? 17
        Task { [weak self] in
            guard let self else { return }
            let startupLoad = await self.rootStore.loadStartupKeymapAsync(
                on: selected,
                initialRows: initialRows,
                initialCols: initialCols
            )
            let presentation = self.rootStore.presentStartupKeymapLoadResult(startupLoad)
            guard !self.isShuttingDown else { return }
            self.isDiagnosticsRunning = false
            self.appendDiagnostics(presentation.matrixDiagnosticMessage)
            if let rows = presentation.matrixRows, let cols = presentation.matrixCols {
                self.matrixRowsText = "\(rows)"
                self.matrixColsText = "\(cols)"
            }

            switch startupLoad.dumpResult {
            case let .success(dump):
                self.latestKeymapDump = dump
                self.layoutChoices = self.vialPresentationService.makeLayoutChoices(from: dump)
                self.availableLayerCount = max(1, dump.layerCount)
                self.setSelectedLayerIndex(self.selectedLayerIndex)
                self.startActiveLayerTrackingIfNeeded()
                self.keymapStatusText = presentation.keymapStatusText
                self.appendDiagnostics(presentation.completionDiagnosticMessage)
            case .failure:
                self.keymapStatusText = presentation.keymapStatusText
                self.appendDiagnostics(presentation.completionDiagnosticMessage)
            }
        }
    }
}
