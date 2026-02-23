import Testing

@testable import Model

struct LayerSelectionServiceTests {
    @Test
    func resolveUpdate_returnsNilWhenNoChangeAndNotForced() {
        let sut = LayerSelectionService()

        let result = sut.resolveUpdate(
            current: 1,
            requested: 1,
            totalLayers: 4,
            forceApply: false
        )

        #expect(result == nil)
    }

    @Test
    func resolveUpdate_clampsRequestedLayer() {
        let sut = LayerSelectionService()

        let result = sut.resolveUpdate(
            current: 0,
            requested: 9,
            totalLayers: 3,
            forceApply: false
        )

        #expect(result?.clampedValue == 2)
        #expect(result?.changed == true)
    }

    @Test
    func resolveUpdate_returnsValueWhenForcedWithoutChange() {
        let sut = LayerSelectionService()

        let result = sut.resolveUpdate(
            current: 2,
            requested: 2,
            totalLayers: 4,
            forceApply: true
        )

        #expect(result?.clampedValue == 2)
        #expect(result?.changed == false)
    }
}
