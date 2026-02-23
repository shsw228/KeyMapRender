import Foundation

public struct VialProbeResult {
    public let protocolVersion: String
    public let layerCount: Int
    public let keycodeL0R0C0: UInt16
    public let backend: String

    public init(protocolVersion: String, layerCount: Int, keycodeL0R0C0: UInt16, backend: String) {
        self.protocolVersion = protocolVersion
        self.layerCount = layerCount
        self.keycodeL0R0C0 = keycodeL0R0C0
        self.backend = backend
    }
}

public struct VialKeymapDump {
    public let protocolVersion: String
    public let layerCount: Int
    public let matrixRows: Int
    public let matrixCols: Int
    public let keycodes: [[[UInt16]]]
    public let layoutKeymapRows: [[Any]]?
    public let layoutLabels: [Any]?
    public let layoutOptions: UInt32?
    public let backend: String

    public init(
        protocolVersion: String,
        layerCount: Int,
        matrixRows: Int,
        matrixCols: Int,
        keycodes: [[[UInt16]]],
        layoutKeymapRows: [[Any]]?,
        layoutLabels: [Any]?,
        layoutOptions: UInt32?,
        backend: String
    ) {
        self.protocolVersion = protocolVersion
        self.layerCount = layerCount
        self.matrixRows = matrixRows
        self.matrixCols = matrixCols
        self.keycodes = keycodes
        self.layoutKeymapRows = layoutKeymapRows
        self.layoutLabels = layoutLabels
        self.layoutOptions = layoutOptions
        self.backend = backend
    }
}

public struct VialMatrixInfo {
    public let rows: Int
    public let cols: Int
    public let backend: String

    public init(rows: Int, cols: Int, backend: String) {
        self.rows = rows
        self.cols = cols
        self.backend = backend
    }
}

public struct VialSwitchMatrixState {
    public let rows: Int
    public let cols: Int
    public let pressed: [[Bool]]
    public let backend: String

    public init(rows: Int, cols: Int, pressed: [[Bool]], backend: String) {
        self.rows = rows
        self.cols = cols
        self.pressed = pressed
        self.backend = backend
    }
}

public enum VialProbeError: Error {
    case message(String)
}
