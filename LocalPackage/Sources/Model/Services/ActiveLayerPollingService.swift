import Foundation

public struct ActiveLayerPollingService {
    public init() {}

    public static func delayMilliseconds(hasActivity: Bool) -> Int {
        hasActivity ? 8 : 25
    }

    public func makePollingTask(
        poll: @escaping @Sendable () async -> Bool
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                let hasActivity = await poll()
                let delayMs = Self.delayMilliseconds(hasActivity: hasActivity)
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
        }
    }
}
