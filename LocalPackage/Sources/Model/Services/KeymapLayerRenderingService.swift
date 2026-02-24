import DataSource
import Foundation

public struct KeymapLayerRenderResult: Sendable {
    public let keymapPreviewText: String
    public let layout: KeyboardLayout
    public let diagnosticMessages: [String]

    public init(
        keymapPreviewText: String,
        layout: KeyboardLayout,
        diagnosticMessages: [String]
    ) {
        self.keymapPreviewText = keymapPreviewText
        self.layout = layout
        self.diagnosticMessages = diagnosticMessages
    }
}

public struct KeymapLayerRenderingService {
    private let vialPresentationService: VialPresentationService
    private let vialDiagnosticsService: VialDiagnosticsService

    public init(
        vialPresentationService: VialPresentationService = .init(),
        vialDiagnosticsService: VialDiagnosticsService = .init()
    ) {
        self.vialPresentationService = vialPresentationService
        self.vialDiagnosticsService = vialDiagnosticsService
    }

    public func render(
        dump: VialKeymapDump,
        requestedLayer: Int,
        selectedLayoutChoices: [VialLayoutChoiceValue],
        overlayName: String
    ) -> KeymapLayerRenderResult {
        let safeLayer = max(0, min(requestedLayer, max(0, dump.layerCount - 1)))
        let previewText = vialPresentationService.makePreview(
            from: dump,
            layer: safeLayer,
            maxRows: min(4, dump.matrixRows),
            maxCols: min(10, dump.matrixCols)
        )

        let selectedLayoutOptions = selectedLayoutChoices.reduce(into: [Int: Int]()) { result, item in
            result[item.id] = item.selected
        }

        let layout: KeyboardLayout
        if let keymapRows = dump.layoutKeymapRows {
            layout = KeyboardLayoutService.makePhysicalLayoutFromVialKeymap(
                keymapRows: keymapRows,
                keycodes: dump.keycodes,
                layer: safeLayer,
                selectedLayoutOptions: selectedLayoutOptions,
                fallbackRows: dump.matrixRows,
                fallbackCols: dump.matrixCols,
                name: overlayName
            )
        } else {
            layout = KeyboardLayoutService.makeMatrixLayout(
                rows: dump.matrixRows,
                cols: dump.matrixCols,
                keycodes: dump.keycodes,
                layer: safeLayer,
                name: overlayName
            )
        }

        let diagnosticKeys = layout.positionedKeys.map {
            VialDiagnosticsKey(
                label: $0.label,
                x: $0.x,
                y: $0.y,
                matrixRow: $0.matrixRow,
                matrixCol: $0.matrixCol,
                rawKeycode: $0.rawKeycode
            )
        }

        var diagnosticMessages: [String] = []
        if let message = vialDiagnosticsService.bottomLeftThirdKeyMessage(layer: safeLayer, keys: diagnosticKeys) {
            diagnosticMessages.append(message)
        }
        diagnosticMessages.append(contentsOf: vialDiagnosticsService.numericLabelMessages(layer: safeLayer, keys: diagnosticKeys))

        return KeymapLayerRenderResult(
            keymapPreviewText: previewText,
            layout: layout,
            diagnosticMessages: diagnosticMessages
        )
    }
}
