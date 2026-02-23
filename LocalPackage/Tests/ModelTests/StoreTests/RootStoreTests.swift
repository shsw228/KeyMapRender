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
}
