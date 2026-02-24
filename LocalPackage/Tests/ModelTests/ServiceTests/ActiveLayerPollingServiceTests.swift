import Testing

@testable import Model

struct ActiveLayerPollingServiceTests {
    @Test
    func delayMilliseconds_returnsFastIntervalWhenActive() {
        #expect(ActiveLayerPollingService.delayMilliseconds(hasActivity: true) == 8)
    }

    @Test
    func delayMilliseconds_returnsIdleIntervalWhenInactive() {
        #expect(ActiveLayerPollingService.delayMilliseconds(hasActivity: false) == 25)
    }
}
