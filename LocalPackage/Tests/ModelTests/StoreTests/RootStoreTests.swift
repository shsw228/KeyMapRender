import os
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
}
