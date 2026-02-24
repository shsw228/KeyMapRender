public struct LayerSelectionUpdate: Sendable, Equatable {
    public let clampedValue: Int
    public let changed: Bool

    public init(clampedValue: Int, changed: Bool) {
        self.clampedValue = clampedValue
        self.changed = changed
    }
}

public struct LayerSelectionService {
    public init() {}

    public func clamp(_ value: Int, totalLayers: Int) -> Int {
        max(0, min(value, max(0, totalLayers - 1)))
    }

    public func resolveUpdate(
        current: Int,
        requested: Int,
        totalLayers: Int,
        forceApply: Bool
    ) -> LayerSelectionUpdate? {
        let clamped = clamp(requested, totalLayers: totalLayers)
        let changed = (current != clamped)
        if !changed, !forceApply {
            return nil
        }
        return LayerSelectionUpdate(clampedValue: clamped, changed: changed)
    }
}
