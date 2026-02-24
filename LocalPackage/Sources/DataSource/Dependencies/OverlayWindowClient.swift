public struct OverlayWindowClient: DependencyClient {
    public var updateAnimationDurations: @Sendable (_ show: Double, _ hide: Double) -> Void
    public var show: @Sendable (_ layout: KeyboardLayout, _ currentLayer: Int, _ totalLayers: Int) -> Void
    public var hide: @Sendable () -> Void

    public init(
        updateAnimationDurations: @escaping @Sendable (_ show: Double, _ hide: Double) -> Void,
        show: @escaping @Sendable (_ layout: KeyboardLayout, _ currentLayer: Int, _ totalLayers: Int) -> Void,
        hide: @escaping @Sendable () -> Void
    ) {
        self.updateAnimationDurations = updateAnimationDurations
        self.show = show
        self.hide = hide
    }

    public static let liveValue = Self(
        updateAnimationDurations: { _, _ in },
        show: { _, _, _ in },
        hide: {}
    )

    public static let testValue = Self(
        updateAnimationDurations: { _, _ in },
        show: { _, _, _ in },
        hide: {}
    )
}
