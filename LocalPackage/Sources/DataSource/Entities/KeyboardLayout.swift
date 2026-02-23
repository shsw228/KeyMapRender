public struct KeyboardLayout: Sendable {
    public let name: String
    public let rows: [[KeyboardKey]]
    public let positionedKeys: [PositionedKey]
    public let positionedWidth: Double
    public let positionedHeight: Double

    public init(
        name: String,
        rows: [[KeyboardKey]],
        positionedKeys: [PositionedKey],
        positionedWidth: Double,
        positionedHeight: Double
    ) {
        self.name = name
        self.rows = rows
        self.positionedKeys = positionedKeys
        self.positionedWidth = positionedWidth
        self.positionedHeight = positionedHeight
    }
}

public struct KeyboardKey: Sendable {
    public let label: String
    public let width: Double
    public let height: Double
    public let isSpacer: Bool

    public init(
        label: String,
        width: Double,
        height: Double,
        isSpacer: Bool
    ) {
        self.label = label
        self.width = width
        self.height = height
        self.isSpacer = isSpacer
    }
}

public struct PositionedKey: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let matrixRow: Int?
    public let matrixCol: Int?
    public let rawKeycode: UInt16?

    public init(
        id: String,
        label: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        matrixRow: Int?,
        matrixCol: Int?,
        rawKeycode: UInt16?
    ) {
        self.id = id
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.matrixRow = matrixRow
        self.matrixCol = matrixCol
        self.rawKeycode = rawKeycode
    }
}
