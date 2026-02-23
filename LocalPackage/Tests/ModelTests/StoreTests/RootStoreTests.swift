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
    func shouldOpenSettingsWindowOnLaunch_returnsTrueOnlyFirstTime() async {
        let sut = RootStore(.testDependencies(), showSettingsOnLaunch: true)
        #expect(sut.shouldOpenSettingsWindowOnLaunch())
        #expect(sut.shouldOpenSettingsWindowOnLaunch() == false)
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
