import os
import Foundation
import Testing

@testable import DataSource
@testable import Model

struct RootStoreTests {
    private let device = HIDKeyboardDevice(
        id: "kbd-1",
        vendorID: 0x1234,
        productID: 0x5678,
        locationID: 1,
        productName: "Test Keyboard",
        manufacturerName: "Test"
    )

    private let dump = VialKeymapDump(
        protocolVersion: "0x0009",
        layerCount: 1,
        matrixRows: 4,
        matrixCols: 5,
        keycodes: [[[0x0029]]],
        layoutKeymapRows: nil,
        layoutLabels: nil,
        layoutOptions: nil,
        backend: "python"
    )

    private let device2 = HIDKeyboardDevice(
        id: "kbd-2",
        vendorID: 0x1111,
        productID: 0x2222,
        locationID: 2,
        productName: "Alt Keyboard",
        manufacturerName: "Alt"
    )

    @MainActor @Test
    func loadStartupKeymapAsync_usesInferredMatrixWhenAvailable() async {
        let requested = OSAllocatedUnfairLock(initialState: (rows: 0, cols: 0))
        let expectedDump = dump
        let sut = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.inferMatrix = { _ in
                    .success(.init(rows: 4, cols: 5, backend: "python"))
                }
                $0.readKeymap = { _, rows, cols in
                    requested.withLock { $0 = (rows: rows, cols: cols) }
                    return .success(expectedDump)
                }
            }
        ))

        let result = await sut.loadStartupKeymapAsync(on: device, initialRows: 6, initialCols: 17)

        let params = requested.withLock(\.self)
        #expect(params.rows == 4)
        #expect(params.cols == 5)
        #expect(result.matrixInfo?.rows == 4)
        #expect(result.matrixInfo?.cols == 5)
        #expect(result.matrixMessage.contains("成功"))
        switch result.dumpResult {
        case let .success(actualDump):
            #expect(actualDump.matrixRows == expectedDump.matrixRows)
            #expect(actualDump.matrixCols == expectedDump.matrixCols)
        case .failure:
            Issue.record("Expected successful dumpResult.")
        }
    }

    @MainActor @Test
    func loadStartupKeymapAsync_fallsBackToInitialMatrixOnInferFailure() async {
        let requested = OSAllocatedUnfairLock(initialState: (rows: 0, cols: 0))
        let expectedDump = dump
        let sut = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.inferMatrix = { _ in .failure(.message("infer failed")) }
                $0.readKeymap = { _, rows, cols in
                    requested.withLock { $0 = (rows: rows, cols: cols) }
                    return .success(expectedDump)
                }
            }
        ))

        let result = await sut.loadStartupKeymapAsync(on: device, initialRows: 6, initialCols: 17)

        let params = requested.withLock(\.self)
        #expect(params.rows == 6)
        #expect(params.cols == 17)
        #expect(result.matrixInfo == nil)
        #expect(result.matrixMessage.contains("失敗"))
    }

    @MainActor @Test
    func runStartupKeymapLoadAsync_returnsPresentationAndOptionalDump() async {
        let successSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.inferMatrix = { _ in .success(.init(rows: 4, cols: 5, backend: "python")) }
                $0.readKeymap = { _, _, _ in .success(dump) }
            }
        ))
        let success = await successSUT.runStartupKeymapLoadAsync(on: device, initialRows: 6, initialCols: 17)
        #expect(success.dump != nil)
        #expect(success.presentation.matrixDiagnosticMessage.contains("起動時自動読込"))
        #expect(success.presentation.keymapStatusText.contains("起動時読込成功"))
        #expect(success.presentation.completionDiagnosticMessage.contains("起動時全マップ読出し成功"))

        let failureSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.inferMatrix = { _ in .failure(.message("infer failed")) }
                $0.readKeymap = { _, _, _ in .failure(.message("decode error")) }
            }
        ))
        let failure = await failureSUT.runStartupKeymapLoadAsync(on: device, initialRows: 6, initialCols: 17)
        #expect(failure.dump == nil)
        #expect(failure.presentation.keymapStatusText == "起動時読込失敗: decode error")
        #expect(failure.presentation.completionDiagnosticMessage == "起動時全マップ読出し失敗: decode error")
    }

    @MainActor @Test
    func keymapPresentationWrappers_delegateToServices() async {
        let sut = RootStore(.testDependencies())
        let choiceDump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 1,
            matrixRows: 1,
            matrixCols: 1,
            keycodes: [[[0x0029]]],
            layoutKeymapRows: nil,
            layoutLabels: ["Split Space", ["Layout", "ANSI", "ISO"]],
            layoutOptions: 0b10,
            backend: "python"
        )

        let choices = sut.makeLayoutChoices(from: choiceDump)
        #expect(choices.count == 2)
        #expect(choices[0].title == "Split Space")
        #expect(choices[1].title == "Layout")

        let renderDump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 1,
            matrixRows: 2,
            matrixCols: 2,
            keycodes: [[[0x0029, 0x0004], [0x0005, 0x0006]]],
            layoutKeymapRows: nil,
            layoutLabels: nil,
            layoutOptions: nil,
            backend: "python"
        )
        let rendered = sut.renderKeymapLayer(
            dump: renderDump,
            requestedLayer: 0,
            selectedLayoutChoices: [],
            overlayName: "Overlay Test"
        )
        #expect(rendered.layout.name == "Overlay Test L0")
        #expect(rendered.keymapPreviewText.contains("L0 R0"))
    }

    @MainActor @Test
    func runAdoptKeymapDump_returnsLayoutChoicesAndLayerCount() async {
        let sut = RootStore(.testDependencies())
        let choiceDump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 0,
            matrixRows: 1,
            matrixCols: 1,
            keycodes: [[[0x0029]]],
            layoutKeymapRows: nil,
            layoutLabels: ["Split Space"],
            layoutOptions: 0,
            backend: "python"
        )

        let adopted = sut.runAdoptKeymapDump(choiceDump)

        #expect(adopted.layoutChoices.count == 1)
        #expect(adopted.layoutChoices[0].title == "Split Space")
        #expect(adopted.availableLayerCount == 1)
    }

    @MainActor @Test
    func runRenderSelectedLayer_buildsPreviewLayoutAndOverlayDiagnostic() async {
        let sut = RootStore(.testDependencies())
        let renderDump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 1,
            matrixRows: 1,
            matrixCols: 1,
            keycodes: [[[0x0029]]],
            layoutKeymapRows: nil,
            layoutLabels: nil,
            layoutOptions: nil,
            backend: "python"
        )

        let visible = sut.runRenderSelectedLayer(
            dump: renderDump,
            selectedLayerIndex: 0,
            availableLayerCount: 3,
            selectedLayoutChoices: [],
            overlayName: "Overlay",
            isOverlayVisible: true
        )
        #expect(visible.keymapPreviewText.contains("L0 R0"))
        #expect(visible.layout.name == "Overlay L0")
        #expect(visible.diagnosticMessages.first == "オーバーレイ更新: L0/2")

        let hidden = sut.runRenderSelectedLayer(
            dump: renderDump,
            selectedLayerIndex: 0,
            availableLayerCount: 3,
            selectedLayoutChoices: [],
            overlayName: "Overlay",
            isOverlayVisible: false
        )
        #expect(hidden.diagnosticMessages.first != "オーバーレイ更新: L0/2")
    }

    @MainActor @Test
    func visibleKeyboards_excludesIgnoredDevices() async {
        let sut = RootStore(.testDependencies())
        sut.addIgnoredDeviceID(device.id)
        let visible = sut.visibleKeyboards(from: [device, device2])
        #expect(visible.map(\.id) == [device2.id])
    }

    @MainActor @Test
    func resolveSelectedKeyboardID_fallsBackToFirstVisibleKeyboard() async {
        let sut = RootStore(.testDependencies())
        let resolved = sut.resolveSelectedKeyboardID(
            current: "unknown",
            connectedKeyboards: [device2, device]
        )
        #expect(resolved == device2.id)
    }

    @MainActor @Test
    func keyboardStatusText_showsIgnoredCountAndSelection() async {
        let sut = RootStore(.testDependencies())
        sut.addIgnoredDeviceID(device2.id)
        let message = sut.keyboardStatusText(
            allDetectedKeyboards: [device, device2],
            connectedKeyboards: [device],
            selectedKeyboard: device
        )
        #expect(message.contains("検出:"))
        #expect(message.contains("無視: 1 台"))
        #expect(message.contains("VID:0x1234"))
    }

    @MainActor @Test
    func refreshKeyboardSnapshot_selectsFirstVisibleKeyboardWhenCurrentMissing() async {
        let sut = RootStore(.testDependencies(
            hidKeyboardClient: testDependency(of: HIDKeyboardClient.self) {
                $0.listKeyboards = { [device2, device] }
            }
        ))

        let snapshot = sut.refreshKeyboardSnapshot(currentSelectedID: "missing")

        #expect(snapshot.connectedKeyboards.map(\.id) == [device2.id, device.id])
        #expect(snapshot.selectedKeyboardID == device2.id)
        #expect(snapshot.keyboardStatusText.contains("検出:"))
    }

    @MainActor @Test
    func refreshKeyboardSnapshot_returnsEmptySelectionWhenNoVisibleKeyboard() async {
        let sut = RootStore(.testDependencies(
            hidKeyboardClient: testDependency(of: HIDKeyboardClient.self) {
                $0.listKeyboards = { [device] }
            }
        ))
        sut.addIgnoredDeviceID(device.id)

        let snapshot = sut.refreshKeyboardSnapshot(currentSelectedID: device.id)

        #expect(snapshot.connectedKeyboards.isEmpty)
        #expect(snapshot.selectedKeyboardID.isEmpty)
        #expect(snapshot.keyboardStatusText.contains("表示対象なし"))
        #expect(snapshot.ignoredDeviceCount == 1)
    }

    @MainActor @Test
    func runIgnoreDeviceAndRefresh_updatesSnapshotAndMessage() async {
        let sut = RootStore(.testDependencies(
            hidKeyboardClient: testDependency(of: HIDKeyboardClient.self) {
                $0.listKeyboards = { [self.device, self.device2] }
            }
        ))

        let workflow = sut.runIgnoreDeviceAndRefresh(device, currentSelectedID: device.id)

        #expect(workflow.snapshot.connectedKeyboards.map(\.id) == [device2.id])
        #expect(workflow.snapshot.selectedKeyboardID == device2.id)
        #expect(workflow.snapshot.ignoredDeviceCount == 1)
        #expect(workflow.diagnosticMessage.contains("id=\(device.id)"))
    }

    @MainActor @Test
    func runClearIgnoredDevicesAndRefresh_restoresVisibleKeyboards() async {
        let sut = RootStore(.testDependencies(
            hidKeyboardClient: testDependency(of: HIDKeyboardClient.self) {
                $0.listKeyboards = { [self.device, self.device2] }
            }
        ))
        _ = sut.runIgnoreDeviceAndRefresh(device, currentSelectedID: device.id)

        let workflow = sut.runClearIgnoredDevicesAndRefresh(currentSelectedID: device2.id)

        #expect(workflow.snapshot.connectedKeyboards.map(\.id) == [device.id, device2.id])
        #expect(workflow.snapshot.ignoredDeviceCount == 0)
        #expect(workflow.diagnosticMessage == "デバイス無視リストを全解除")
    }

    @MainActor @Test
    func presentStartupKeymapLoadResult_buildsSuccessMessages() async {
        let sut = RootStore(.testDependencies())
        let loadResult = RootStore.StartupKeymapLoadResult(
            matrixMessage: "matrix自動取得成功(python): 4x5",
            matrixInfo: .init(rows: 4, cols: 5, backend: "python"),
            dumpResult: .success(dump)
        )

        let presentation = sut.presentStartupKeymapLoadResult(loadResult)

        #expect(presentation.matrixDiagnosticMessage.contains("起動時自動読込"))
        #expect(presentation.keymapStatusText.contains("起動時読込成功"))
        #expect(presentation.completionDiagnosticMessage.contains("起動時全マップ読出し成功"))
        #expect(presentation.matrixRows == 4)
        #expect(presentation.matrixCols == 5)
    }

    @MainActor @Test
    func presentStartupKeymapLoadResult_buildsFailureMessages() async {
        let sut = RootStore(.testDependencies())
        let loadResult = RootStore.StartupKeymapLoadResult(
            matrixMessage: "matrix自動取得失敗: timeout",
            matrixInfo: nil,
            dumpResult: .failure(.message("decode error"))
        )

        let presentation = sut.presentStartupKeymapLoadResult(loadResult)

        #expect(presentation.keymapStatusText == "起動時読込失敗: decode error")
        #expect(presentation.completionDiagnosticMessage == "起動時全マップ読出し失敗: decode error")
        #expect(presentation.matrixRows == nil)
        #expect(presentation.matrixCols == nil)
    }

    @MainActor @Test
    func presentVialProbeResult_buildsSuccessAndFailureMessages() async {
        let sut = RootStore(.testDependencies())
        let success = sut.presentVialProbeResult(
            .success(
                VialProbeResult(
                    protocolVersion: "0x0009",
                    layerCount: 8,
                    keycodeL0R0C0: 0x2B,
                    backend: "python"
                )
            )
        )
        #expect(success.vialStatusText.contains("Vial応答(python)"))
        #expect(success.diagnosticMessage.contains("Vial通信テスト成功"))
        #expect(success.availableLayerCount == 8)

        let failure = sut.presentVialProbeResult(.failure(.message("timeout")))
        #expect(failure.vialStatusText == "Vial応答なし: timeout")
        #expect(failure.diagnosticMessage == "Vial通信テスト失敗: timeout")
        #expect(failure.availableLayerCount == nil)
    }

    @MainActor @Test
    func runVialProbeAsync_returnsPresentationAndOptionalProbe() async {
        let successSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.probe = { _ in
                    .success(
                        VialProbeResult(
                            protocolVersion: "0x0009",
                            layerCount: 8,
                            keycodeL0R0C0: 0x2B,
                            backend: "python"
                        )
                    )
                }
            }
        ))
        let success = await successSUT.runVialProbeAsync(on: device)
        #expect(success.probe != nil)
        #expect(success.presentation.vialStatusText.contains("Vial応答(python)"))
        #expect(success.presentation.availableLayerCount == 8)

        let failureSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.probe = { _ in .failure(.message("timeout")) }
            }
        ))
        let failure = await failureSUT.runVialProbeAsync(on: device)
        #expect(failure.probe == nil)
        #expect(failure.presentation.vialStatusText == "Vial応答なし: timeout")
        #expect(failure.presentation.availableLayerCount == nil)
    }

    @MainActor @Test
    func presentVialKeymapReadResult_buildsSuccessAndFailureMessages() async {
        let sut = RootStore(.testDependencies())
        let success = sut.presentVialKeymapReadResult(.success(dump))
        #expect(success.keymapStatusText.contains("取得成功(python)"))
        #expect(success.diagnosticMessage.contains("全マップ読出し成功"))
        #expect(success.availableLayerCount == 1)

        let failure = sut.presentVialKeymapReadResult(.failure(.message("decode error")))
        #expect(failure.keymapStatusText == "取得失敗: decode error")
        #expect(failure.diagnosticMessage == "全マップ読出し失敗: decode error")
        #expect(failure.availableLayerCount == nil)
    }

    @MainActor @Test
    func runReadVialKeymapAsync_returnsPresentationAndOptionalDump() async {
        let successSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.readKeymap = { _, _, _ in .success(dump) }
            }
        ))
        let success = await successSUT.runReadVialKeymapAsync(on: device, rows: 4, cols: 5)
        #expect(success.dump != nil)
        #expect(success.presentation.keymapStatusText.contains("取得成功(python)"))
        #expect(success.presentation.availableLayerCount == 1)

        let failureSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.readKeymap = { _, _, _ in .failure(.message("decode error")) }
            }
        ))
        let failure = await failureSUT.runReadVialKeymapAsync(on: device, rows: 4, cols: 5)
        #expect(failure.dump == nil)
        #expect(failure.presentation.keymapStatusText == "取得失敗: decode error")
        #expect(failure.presentation.availableLayerCount == nil)
    }

    @MainActor @Test
    func presentVialMatrixInferenceResult_buildsSuccessAndFailureMessages() async {
        let sut = RootStore(.testDependencies())
        let success = sut.presentVialMatrixInferenceResult(
            .success(.init(rows: 14, cols: 8, backend: "python"))
        )
        #expect(success.keymapStatusText == "matrix自動取得成功(python): 14x8")
        #expect(success.diagnosticMessage == "matrix自動取得成功: 14x8")
        #expect(success.matrixRows == 14)
        #expect(success.matrixCols == 8)

        let failure = sut.presentVialMatrixInferenceResult(.failure(.message("unsupported")))
        #expect(failure.keymapStatusText == "matrix自動取得失敗: unsupported")
        #expect(failure.diagnosticMessage == "matrix自動取得失敗: unsupported")
        #expect(failure.matrixRows == nil)
        #expect(failure.matrixCols == nil)
    }

    @MainActor @Test
    func runInferVialMatrixAsync_returnsMatrixPresentation() async {
        let successSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.inferMatrix = { _ in .success(.init(rows: 14, cols: 8, backend: "python")) }
            }
        ))
        let success = await successSUT.runInferVialMatrixAsync(on: device)
        #expect(success.presentation.keymapStatusText == "matrix自動取得成功(python): 14x8")
        #expect(success.presentation.matrixRows == 14)
        #expect(success.presentation.matrixCols == 8)

        let failureSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.inferMatrix = { _ in .failure(.message("unsupported")) }
            }
        ))
        let failure = await failureSUT.runInferVialMatrixAsync(on: device)
        #expect(failure.presentation.keymapStatusText == "matrix自動取得失敗: unsupported")
        #expect(failure.presentation.matrixRows == nil)
        #expect(failure.presentation.matrixCols == nil)
    }

    @MainActor @Test
    func presentVialDefinitionPresentations_buildExpectedMessages() async {
        let sut = RootStore(.testDependencies())
        #expect(sut.suggestedVialDefinitionFileName(for: device) == "vial-1234-5678.json")

        let validation = sut.presentVialDefinitionValidationFailure("invalid matrix")
        #expect(validation.keymapStatusText == "vial.json検証失敗: invalid matrix")
        #expect(validation.diagnosticMessage == "vial.json検証失敗: invalid matrix")

        let readFailure = sut.presentVialDefinitionReadFailure("timeout")
        #expect(readFailure.keymapStatusText == "vial.json取得失敗: timeout")
        #expect(readFailure.diagnosticMessage == "vial.json取得失敗: timeout")

        let saved = sut.presentVialDefinitionSaveResult(.success(.saved(path: "/tmp/vial.json")))
        #expect(saved.keymapStatusText == "vial.json保存完了: /tmp/vial.json")
        #expect(saved.diagnosticMessage == "vial.json保存完了: /tmp/vial.json")

        let cancelled = sut.presentVialDefinitionSaveResult(.success(.cancelled))
        #expect(cancelled.keymapStatusText == "vial.json保存をキャンセルしました。")
        #expect(cancelled.diagnosticMessage == "vial.json保存キャンセル")

        let saveFailure = sut.presentVialDefinitionSaveResult(.failure(.message("no permission")))
        #expect(saveFailure.keymapStatusText == "vial.json保存失敗: no permission")
        #expect(saveFailure.diagnosticMessage == "vial.json保存失敗: no permission")
    }

    @MainActor @Test
    func runReadVialDefinitionAsync_returnsWorkflowResult() async {
        let successSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.readDefinition = { _ in .success("{\"layouts\":{}}") }
            }
        ))
        let success = await successSUT.runReadVialDefinitionAsync(on: device)
        switch success {
        case let .success(prettyJSON, suggestedFileName):
            #expect(prettyJSON == "{\"layouts\":{}}")
            #expect(suggestedFileName == "vial-1234-5678.json")
        case .failure:
            Issue.record("Expected runReadVialDefinitionAsync success.")
        }

        let failureSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.readDefinition = { _ in .failure(.message("timeout")) }
            }
        ))
        let failure = await failureSUT.runReadVialDefinitionAsync(on: device)
        switch failure {
        case .success:
            Issue.record("Expected runReadVialDefinitionAsync failure.")
        case let .failure(presentation):
            #expect(presentation.keymapStatusText == "vial.json取得失敗: timeout")
            #expect(presentation.diagnosticMessage == "vial.json取得失敗: timeout")
        }
    }

    @MainActor @Test
    func runExportVialDefinitionAsync_handlesSuccessAndFailures() async {
        let savedContent = OSAllocatedUnfairLock(initialState: "")
        let successSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.readDefinition = { _ in
                    .success("""
                    {"layouts":{"keymap":[[]]},"matrix":{"rows":4,"cols":5}}
                    """)
                }
            },
            fileSaveClient: testDependency(of: FileSaveClient.self) {
                $0.saveText = { request in
                    savedContent.withLock { $0 = request.content }
                    return .success(.saved(path: "/tmp/vial.json"))
                }
            }
        ))
        let success = await successSUT.runExportVialDefinitionAsync(on: device)
        #expect(success.keymapStatusText == "vial.json保存完了: /tmp/vial.json")
        #expect(savedContent.withLock(\.self).contains("\"layouts\""))

        let readFailureSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.readDefinition = { _ in .failure(.message("timeout")) }
            }
        ))
        let readFailure = await readFailureSUT.runExportVialDefinitionAsync(on: device)
        #expect(readFailure.keymapStatusText == "vial.json取得失敗: timeout")

        let validationFailureSUT = RootStore(.testDependencies(
            vialRawHIDClient: testDependency(of: VialRawHIDClient.self) {
                $0.readDefinition = { _ in .success("{\"matrix\":{\"rows\":4,\"cols\":5}}") }
            }
        ))
        let validationFailure = await validationFailureSUT.runExportVialDefinitionAsync(on: device)
        #expect(validationFailure.keymapStatusText.contains("vial.json検証失敗"))
    }

    @MainActor @Test
    func launchAtLogin_wrappersDelegateToDependencyClient() async {
        let sut = RootStore(.testDependencies(
            launchAtLoginClient: testDependency(of: LaunchAtLoginClient.self) {
                $0.status = { .success(true) }
                $0.setEnabled = { enabled in .success(enabled) }
            }
        ))

        let status = sut.launchAtLoginStatus()
        switch status {
        case let .success(enabled):
            #expect(enabled)
        case .failure:
            Issue.record("Expected success from launchAtLoginStatus.")
        }

        let update = sut.setLaunchAtLoginEnabled(false)
        switch update {
        case let .success(enabled):
            #expect(enabled == false)
        case .failure:
            Issue.record("Expected success from setLaunchAtLoginEnabled.")
        }
    }

    @MainActor @Test
    func runSetLaunchAtLogin_returnsWorkflowMessageAndResolvedState() async {
        let successSUT = RootStore(.testDependencies(
            launchAtLoginClient: testDependency(of: LaunchAtLoginClient.self) {
                $0.status = { .success(false) }
                $0.setEnabled = { enabled in .success(enabled) }
            }
        ))
        let success = successSUT.runSetLaunchAtLogin(true)
        #expect(success.enabled)
        #expect(success.diagnosticMessage == "自動起動設定を更新: ON")

        let failureSUT = RootStore(.testDependencies(
            launchAtLoginClient: testDependency(of: LaunchAtLoginClient.self) {
                $0.status = { .success(true) }
                $0.setEnabled = { _ in .failure(.message("denied")) }
            }
        ))
        let failure = failureSUT.runSetLaunchAtLogin(false)
        #expect(failure.enabled)
        #expect(failure.diagnosticMessage == "自動起動設定の更新失敗: denied")
    }

    @MainActor @Test
    func runRefreshLaunchAtLoginStatus_returnsWorkflowResult() async {
        let successSUT = RootStore(.testDependencies(
            launchAtLoginClient: testDependency(of: LaunchAtLoginClient.self) {
                $0.status = { .success(true) }
            }
        ))
        let success = successSUT.runRefreshLaunchAtLoginStatus()
        #expect(success.enabled)
        #expect(success.diagnosticMessage == nil)

        let failureSUT = RootStore(.testDependencies(
            launchAtLoginClient: testDependency(of: LaunchAtLoginClient.self) {
                $0.status = { .failure(.message("unavailable")) }
            }
        ))
        let failure = failureSUT.runRefreshLaunchAtLoginStatus()
        #expect(failure.enabled == false)
        #expect(failure.diagnosticMessage == "自動起動状態の取得失敗: unavailable")
    }

    @MainActor @Test
    func runStartGlobalMonitoring_returnsSessionAndStatusText() async {
        let successSUT = RootStore(.testDependencies(
            globalKeyMonitorClient: testDependency(of: GlobalKeyMonitorClient.self) {
                $0.start = { _, _, _ in .success(.init(id: UUID())) }
                $0.stop = { _ in }
            }
        ))
        let success = successSUT.runStartGlobalMonitoring(
            configuration: .init(targetKeyCode: 60, longPressThreshold: 0.4),
            onLongPressStart: {},
            onLongPressEnd: {}
        )
        #expect(success.session != nil)
        #expect(success.permissionStatusText.contains("監視中: keyCode 60"))

        let failureSUT = RootStore(.testDependencies(
            globalKeyMonitorClient: testDependency(of: GlobalKeyMonitorClient.self) {
                $0.start = { _, _, _ in .failure(.message("failed")) }
                $0.stop = { _ in }
            }
        ))
        let failure = failureSUT.runStartGlobalMonitoring(
            configuration: .init(targetKeyCode: 60, longPressThreshold: 0.4),
            onLongPressStart: {},
            onLongPressEnd: {}
        )
        #expect(failure.session == nil)
        #expect(failure.permissionStatusText == "キー監視を開始できませんでした。Accessibility / Input Monitoring を確認してください。")
    }

    @MainActor @Test
    func runPrepareApplySettings_validatesAndPersistsPreferences() async {
        let sut = RootStore(.testDependencies())
        let failure = sut.runPrepareApplySettings(
            targetKeyCodeText: "abc",
            longPressDuration: 0.5,
            overlayShowAnimationDuration: 0.2,
            overlayHideAnimationDuration: 0.2,
            showSettingsOnLaunch: true
        )
        switch failure {
        case .success:
            Issue.record("Expected invalid key code failure.")
        case let .failure(permissionStatusText):
            #expect(permissionStatusText == "キーコードは 0-127 の整数で入力してください。")
        }

        let success = sut.runPrepareApplySettings(
            targetKeyCodeText: "61",
            longPressDuration: 0.6,
            overlayShowAnimationDuration: 0.3,
            overlayHideAnimationDuration: 0.4,
            showSettingsOnLaunch: false
        )
        switch success {
        case let .success(configuration):
            #expect(configuration.targetKeyCode == 61)
            #expect(configuration.longPressThreshold == 0.6)
        case .failure:
            Issue.record("Expected runPrepareApplySettings success.")
        }
    }

    @MainActor @Test
    func runRestartGlobalMonitoring_stopsExistingSessionAndStartsNewOne() async {
        let stopped = OSAllocatedUnfairLock(initialState: false)
        let expectedSession = GlobalKeyMonitorSession(id: UUID())
        let sut = RootStore(.testDependencies(
            globalKeyMonitorClient: testDependency(of: GlobalKeyMonitorClient.self) {
                $0.start = { _, _, _ in .success(expectedSession) }
                $0.stop = { _ in stopped.withLock { $0 = true } }
            }
        ))

        let workflow = sut.runRestartGlobalMonitoring(
            existingSession: .init(id: UUID()),
            configuration: .init(targetKeyCode: 60, longPressThreshold: 0.4),
            onLongPressStart: {},
            onLongPressEnd: {}
        )

        #expect(stopped.withLock { $0 })
        #expect(workflow.session?.id == expectedSession.id)
        #expect(workflow.permissionStatusText.contains("監視中: keyCode 60"))
    }

    @MainActor @Test
    func runStartKeyboardHotplugMonitoring_returnsSessionAndDiagnostic() async {
        let successSUT = RootStore(.testDependencies(
            hidKeyboardHotplugClient: testDependency(of: HIDKeyboardHotplugClient.self) {
                $0.start = { _ in .success(.init(id: UUID())) }
                $0.stop = { _ in }
            }
        ))
        let success = successSUT.runStartKeyboardHotplugMonitoring(onChanged: {})
        #expect(success.session != nil)
        #expect(success.diagnosticMessage == nil)

        let failureSUT = RootStore(.testDependencies(
            hidKeyboardHotplugClient: testDependency(of: HIDKeyboardHotplugClient.self) {
                $0.start = { _ in .failure(.message("failed")) }
                $0.stop = { _ in }
            }
        ))
        let failure = failureSUT.runStartKeyboardHotplugMonitoring(onChanged: {})
        #expect(failure.session == nil)
        #expect(failure.diagnosticMessage == "キーボード接続監視の開始に失敗しました。")
    }

    @MainActor @Test
    func shouldOpenSettingsWindowOnLaunch_returnsTrueOnlyFirstTime() async {
        let sut = RootStore(.testDependencies(), showSettingsOnLaunch: true)
        #expect(sut.shouldOpenSettingsWindowOnLaunch())
        #expect(sut.shouldOpenSettingsWindowOnLaunch() == false)
    }

    @MainActor @Test
    func runStartupLifecycle_returnsStartFlagAndPermissionText() async {
        let sut = RootStore(.testDependencies(
            inputAccessClient: testDependency(of: InputAccessClient.self) {
                $0.checkStatus = { _, _ in
                    .init(accessibilityTrusted: true, inputMonitoringTrusted: true)
                }
            }
        ))

        let blocked = sut.runStartupLifecycle(hasStarted: true, isShuttingDown: false)
        #expect(blocked.shouldStart == false)
        #expect(blocked.permissionStatusText == nil)

        let ready = sut.runStartupLifecycle(hasStarted: false, isShuttingDown: false)
        #expect(ready.shouldStart)
        #expect(ready.permissionStatusText == "権限: Accessibility/Input Monitoring 許可済み")
    }

    @MainActor @Test
    func runPrepareStartupAutoLoad_returnsWorkflowByConditions() async {
        let sut = RootStore(.testDependencies())

        let alreadyLoaded = sut.runPrepareStartupAutoLoad(
            hasAutoLoadedOnStartup: true,
            hasSelectedKeyboard: true,
            isDiagnosticsRunning: false,
            rowsText: "14",
            colsText: "8"
        )
        #expect(alreadyLoaded.shouldRun == false)
        #expect(alreadyLoaded.nextHasAutoLoadedOnStartup)

        let blocked = sut.runPrepareStartupAutoLoad(
            hasAutoLoadedOnStartup: false,
            hasSelectedKeyboard: false,
            isDiagnosticsRunning: false,
            rowsText: "14",
            colsText: "8"
        )
        #expect(blocked.shouldRun == false)
        #expect(blocked.nextHasAutoLoadedOnStartup == false)

        let ready = sut.runPrepareStartupAutoLoad(
            hasAutoLoadedOnStartup: false,
            hasSelectedKeyboard: true,
            isDiagnosticsRunning: false,
            rowsText: "x",
            colsText: "y"
        )
        #expect(ready.shouldRun)
        #expect(ready.nextHasAutoLoadedOnStartup)
        #expect(ready.statusText == "起動時自動読込中...")
        #expect(ready.initialRows == 6)
        #expect(ready.initialCols == 17)
    }

    @MainActor @Test
    func inputAccessStatus_delegatesToDependencyClient() async {
        let sut = RootStore(.testDependencies(
            inputAccessClient: testDependency(of: InputAccessClient.self) {
                $0.checkStatus = { promptAccessibility, requestInputMonitoring in
                    #expect(promptAccessibility)
                    #expect(requestInputMonitoring)
                    return .init(accessibilityTrusted: true, inputMonitoringTrusted: false)
                }
            }
        ))
        let status = sut.inputAccessStatus(
            promptAccessibility: true,
            requestInputMonitoring: true
        )
        #expect(status.accessibilityTrusted)
        #expect(status.inputMonitoringTrusted == false)
    }

    @MainActor @Test
    func permissionAndMonitoringPresentation_buildsExpectedMessages() async {
        let sut = RootStore(.testDependencies())
        let granted = sut.permissionStatusText(
            for: .init(accessibilityTrusted: true, inputMonitoringTrusted: true)
        )
        #expect(granted == "権限: Accessibility/Input Monitoring 許可済み")

        let denied = sut.permissionStatusText(
            for: .init(accessibilityTrusted: true, inputMonitoringTrusted: false)
        )
        #expect(denied == "権限不足: Accessibility と Input Monitoring を許可してください。")

        let monitoring = sut.monitoringStatusText(targetKeyCode: 60, longPressDuration: 0.5)
        #expect(monitoring.contains("監視中: keyCode 60"))
        #expect(monitoring.contains("0.50"))
        #expect(sut.monitoringStartFailureStatusText().contains("キー監視を開始できませんでした"))
    }

    @MainActor @Test
    func parseTargetKeyCode_validatesRangeAndFormat() async {
        let sut = RootStore(.testDependencies())
        #expect(sut.parseTargetKeyCode("42") == 42)
        #expect(sut.parseTargetKeyCode("128") == nil)
        #expect(sut.parseTargetKeyCode("abc") == nil)
        #expect(sut.invalidTargetKeyCodeMessage() == "キーコードは 0-127 の整数で入力してください。")
    }

    @MainActor @Test
    func parseMatrixSize_andResolveInitialMatrixSize_behaveAsExpected() async {
        let sut = RootStore(.testDependencies())
        let parsed = sut.parseMatrixSize(rowsText: "14", colsText: "8")
        #expect(parsed?.rows == 14)
        #expect(parsed?.cols == 8)
        #expect(sut.parseMatrixSize(rowsText: "0", colsText: "8") == nil)
        #expect(sut.parseMatrixSize(rowsText: "x", colsText: "8") == nil)

        let fallback = sut.resolveInitialMatrixSize(rowsText: "x", colsText: "y")
        #expect(fallback.rows == 6)
        #expect(fallback.cols == 17)
    }

    @MainActor @Test
    func commonStatusMessages_returnExpectedValues() async {
        let sut = RootStore(.testDependencies())
        #expect(sut.keyboardSelectionRequiredMessage() == "キーボードを選択してください。")
        #expect(sut.ignoredKeyboardSelectionRequiredMessage() == "無視対象のキーボードを選択してください。")
        #expect(sut.matrixInputValidationFailureMessage() == "Rows/Cols は 1 以上の整数で入力してください。")
        #expect(sut.vialProbeInProgressStatusText() == "Vial通信テスト中...")
        #expect(sut.keymapReadInProgressStatusText() == "全マップ読出し中...")
        #expect(sut.matrixInferenceInProgressStatusText() == "matrix自動取得中...")
        #expect(sut.vialDefinitionReadInProgressStatusText() == "vial.json取得中...")
        #expect(sut.startupAutoLoadInProgressStatusText() == "起動時自動読込中...")
        #expect(sut.keyboardHotplugStartFailureDiagnosticMessage() == "キーボード接続監視の開始に失敗しました。")
        #expect(sut.overlayShownDiagnosticMessage(currentLayer: 2, totalLayers: 8) == "オーバーレイ表示: L2/7")
        #expect(sut.overlayUpdatedDiagnosticMessage(currentLayer: 3, totalLayers: 8) == "オーバーレイ更新: L3/7")
        #expect(sut.displayLayerChangedDiagnosticMessage(reason: "手動", currentLayer: 1, totalLayers: 4) == "表示レイヤー変更(手動): L1/3")
        #expect(sut.activeLayerTrackingStartedDiagnosticMessage() == "アクティブレイヤー追従開始")
        #expect(sut.activeLayerTrackingFailureDiagnosticMessage("timeout") == "アクティブレイヤー追従失敗: timeout")
        #expect(sut.ignoredDeviceAddedDiagnosticMessage(device).contains("id=kbd-1"))
        #expect(sut.ignoredDevicesClearedDiagnosticMessage() == "デバイス無視リストを全解除")
        #expect(sut.launchAtLoginUpdatedDiagnosticMessage(enabled: true) == "自動起動設定を更新: ON")
        #expect(sut.launchAtLoginUpdatedDiagnosticMessage(enabled: false) == "自動起動設定を更新: OFF")
        #expect(sut.launchAtLoginUpdateFailureDiagnosticMessage("denied") == "自動起動設定の更新失敗: denied")
        #expect(sut.launchAtLoginStatusFailureDiagnosticMessage("denied") == "自動起動状態の取得失敗: denied")
        #expect(sut.overlayKeyboardName(for: device) == "Test Test Keyboard")
        let blankDevice = HIDKeyboardDevice(
            id: "blank",
            vendorID: 0,
            productID: 0,
            locationID: 0,
            productName: " ",
            manufacturerName: " "
        )
        #expect(sut.overlayKeyboardName(for: blankDevice) == "Keyboard")
        #expect(sut.overlayKeyboardName(for: nil) == "Keyboard")
    }

    @MainActor @Test
    func appendDiagnosticsLog_buildsTimestampedBuffer() async {
        let sut = RootStore(.testDependencies())
        let first = sut.appendDiagnosticsLog(existingText: "-", message: "hello")
        #expect(first.updatedText.contains("hello"))
        #expect(first.level == .debug)

        let second = sut.appendDiagnosticsLog(existingText: first.updatedText, message: "失敗")
        #expect(second.updatedText.contains("hello"))
        #expect(second.updatedText.contains("失敗"))
        #expect(second.level == .error)
    }

    @MainActor @Test
    func layerTrackingWrappers_delegateToServices() async {
        let sut = RootStore(.testDependencies())
        #expect(sut.clampLayerIndex(5, totalLayers: 2) == 1)
        #expect(sut.resolveLayerSelectionUpdate(
            current: 1,
            requested: 1,
            totalLayers: 2,
            forceApply: false
        ) == nil)

        let singleLayerDump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 1,
            matrixRows: 1,
            matrixCols: 1,
            keycodes: [[[0x0029]]],
            layoutKeymapRows: nil,
            layoutLabels: nil,
            layoutOptions: nil,
            backend: "python"
        )
        let tracked = sut.deriveTrackedLayer(from: [[false]], dump: singleLayerDump, baseLayer: 3)
        #expect(tracked == 0)
    }

    @MainActor @Test
    func runResolveDisplayedLayerSelection_returnsLayerAndOptionalDiagnostic() async {
        let sut = RootStore(.testDependencies())

        let noChange = sut.runResolveDisplayedLayerSelection(
            current: 1,
            requested: 1,
            totalLayers: 3,
            forceApply: false,
            reason: "手動",
            emitLog: true
        )
        #expect(noChange == nil)

        let changed = sut.runResolveDisplayedLayerSelection(
            current: 0,
            requested: 2,
            totalLayers: 3,
            forceApply: false,
            reason: "手動",
            emitLog: true
        )
        #expect(changed?.clampedLayer == 2)
        #expect(changed?.diagnosticMessage == "表示レイヤー変更(手動): L2/2")

        let silent = sut.runResolveDisplayedLayerSelection(
            current: 0,
            requested: 2,
            totalLayers: 3,
            forceApply: false,
            reason: "押下追従",
            emitLog: false
        )
        #expect(silent?.clampedLayer == 2)
        #expect(silent?.diagnosticMessage == nil)
    }

    @MainActor @Test
    func runResolveActiveLayerPollResult_returnsTrackedLayerOnSuccess() async {
        let sut = RootStore(.testDependencies())
        let twoLayerDump = VialKeymapDump(
            protocolVersion: "0x0009",
            layerCount: 2,
            matrixRows: 1,
            matrixCols: 1,
            keycodes: [[[0x0029]], [[0x5001]]],
            layoutKeymapRows: nil,
            layoutLabels: nil,
            layoutOptions: nil,
            backend: "python"
        )

        let result = sut.runResolveActiveLayerPollResult(
            .success(.init(rows: 1, cols: 1, pressed: [[true]], backend: "python")),
            dump: twoLayerDump,
            baseLayer: 0,
            failureCount: 4
        )

        #expect(result.trackedLayer == 0)
        #expect(result.isAnyKeyPressed)
        #expect(result.nextFailureCount == 0)
        #expect(result.diagnosticMessage == nil)
    }

    @MainActor @Test
    func runResolveActiveLayerPollResult_emitsDiagnosticOnFirstAndPeriodicFailure() async {
        let sut = RootStore(.testDependencies())
        let failure: Result<VialSwitchMatrixState, VialProbeError> = .failure(.message("timeout"))

        let first = sut.runResolveActiveLayerPollResult(
            failure,
            dump: dump,
            baseLayer: 0,
            failureCount: 0
        )
        #expect(first.trackedLayer == nil)
        #expect(first.isAnyKeyPressed == false)
        #expect(first.nextFailureCount == 1)
        #expect(first.diagnosticMessage == "アクティブレイヤー追従失敗: timeout")

        let skip = sut.runResolveActiveLayerPollResult(
            failure,
            dump: dump,
            baseLayer: 0,
            failureCount: 1
        )
        #expect(skip.nextFailureCount == 2)
        #expect(skip.diagnosticMessage == nil)

        let twentieth = sut.runResolveActiveLayerPollResult(
            failure,
            dump: dump,
            baseLayer: 0,
            failureCount: 19
        )
        #expect(twentieth.nextFailureCount == 20)
        #expect(twentieth.diagnosticMessage == "アクティブレイヤー追従失敗: timeout")
    }

    @MainActor @Test
    func copyToClipboard_delegatesToDependencyClient() async {
        let copied = OSAllocatedUnfairLock(initialState: "")
        let sut = RootStore(.testDependencies(
            clipboardClient: testDependency(of: ClipboardClient.self) {
                $0.copyString = { text in copied.withLock { $0 = text } }
            }
        ))
        sut.copyToClipboard("hello")
        #expect(copied.withLock(\.self) == "hello")
    }

    @MainActor @Test
    func saveTextFile_delegatesToDependencyClient() async {
        let received = OSAllocatedUnfairLock(initialState: "")
        let sut = RootStore(.testDependencies(
            fileSaveClient: testDependency(of: FileSaveClient.self) {
                $0.saveText = { request in
                    received.withLock { $0 = request.content }
                    return .success(.saved(path: "/tmp/sample.json"))
                }
            }
        ))
        let result = sut.saveTextFile(
            SaveFileRequest(
                suggestedFileName: "sample.json",
                allowedExtensions: ["json"],
                title: "save",
                content: "{\"k\":1}"
            )
        )
        #expect(received.withLock(\.self) == "{\"k\":1}")
        switch result {
        case let .success(value):
            switch value {
            case let .saved(path):
                #expect(path == "/tmp/sample.json")
            case .cancelled:
                Issue.record("Expected saved result.")
            }
        case .failure:
            Issue.record("Expected saveTextFile success.")
        }
    }

    @MainActor @Test
    func keyboardHotplug_wrappersDelegateToDependencyClient() async {
        let started = OSAllocatedUnfairLock(initialState: false)
        let stopped = OSAllocatedUnfairLock(initialState: false)
        let session = HIDKeyboardHotplugSession(id: UUID())
        let sut = RootStore(.testDependencies(
            hidKeyboardHotplugClient: testDependency(of: HIDKeyboardHotplugClient.self) {
                $0.start = { onChanged in
                    started.withLock { $0 = true }
                    onChanged()
                    return .success(session)
                }
                $0.stop = { _ in
                    stopped.withLock { $0 = true }
                }
            }
        ))

        let start = sut.startKeyboardHotplugMonitoring(onChanged: {})
        switch start {
        case let .success(value):
            #expect(value == session)
            sut.stopKeyboardHotplugMonitoring(value)
        case .failure:
            Issue.record("Expected startKeyboardHotplugMonitoring success.")
        }

        #expect(started.withLock { $0 })
        #expect(stopped.withLock { $0 })
    }

    @MainActor @Test
    func globalKeyMonitor_wrappersDelegateToDependencyClient() async {
        let started = OSAllocatedUnfairLock(initialState: false)
        let stopped = OSAllocatedUnfairLock(initialState: false)
        let configuration = OSAllocatedUnfairLock(initialState: GlobalKeyMonitorConfiguration(
            targetKeyCode: 0,
            longPressThreshold: 0
        ))
        let session = GlobalKeyMonitorSession(id: UUID())
        let sut = RootStore(.testDependencies(
            globalKeyMonitorClient: testDependency(of: GlobalKeyMonitorClient.self) {
                $0.start = { config, onLongPressStart, onLongPressEnd in
                    started.withLock { $0 = true }
                    configuration.withLock { $0 = config }
                    onLongPressStart()
                    onLongPressEnd()
                    return .success(session)
                }
                $0.stop = { _ in
                    stopped.withLock { $0 = true }
                }
            }
        ))

        let startResult = sut.startGlobalKeyMonitoring(
            .init(targetKeyCode: 59, longPressThreshold: 0.3),
            onLongPressStart: {},
            onLongPressEnd: {}
        )
        switch startResult {
        case let .success(value):
            #expect(value == session)
            sut.stopGlobalKeyMonitoring(value)
        case .failure:
            Issue.record("Expected startGlobalKeyMonitoring success.")
        }

        #expect(started.withLock { $0 })
        #expect(stopped.withLock { $0 })
        let actual = configuration.withLock { $0 }
        #expect(actual.targetKeyCode == 59)
        #expect(actual.longPressThreshold == 0.3)
    }

    @MainActor @Test
    func overlayWindow_wrappersDelegateToDependencyClient() async {
        let updated = OSAllocatedUnfairLock(initialState: (show: 0.0, hide: 0.0))
        let shown = OSAllocatedUnfairLock(initialState: false)
        let hidden = OSAllocatedUnfairLock(initialState: false)
        let sut = RootStore(.testDependencies(
            overlayWindowClient: testDependency(of: OverlayWindowClient.self) {
                $0.updateAnimationDurations = { show, hide in
                    updated.withLock { $0 = (show: show, hide: hide) }
                }
                $0.show = { layout, currentLayer, totalLayers in
                    #expect(layout.name == "Test Layout")
                    #expect(currentLayer == 2)
                    #expect(totalLayers == 6)
                    shown.withLock { $0 = true }
                }
                $0.hide = {
                    hidden.withLock { $0 = true }
                }
            }
        ))

        sut.updateOverlayAnimationDurations(show: 0.4, hide: 0.2)
        sut.showOverlay(
            layout: KeyboardLayout(
                name: "Test Layout",
                rows: [],
                positionedKeys: [],
                positionedWidth: 0,
                positionedHeight: 0
            ),
            currentLayer: 2,
            totalLayers: 6
        )
        sut.hideOverlay()

        let durations = updated.withLock { $0 }
        #expect(durations.show == 0.4)
        #expect(durations.hide == 0.2)
        #expect(shown.withLock { $0 })
        #expect(hidden.withLock { $0 })
    }
}
