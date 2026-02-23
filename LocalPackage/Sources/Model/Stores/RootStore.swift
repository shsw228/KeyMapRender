import DataSource
import Observation

@MainActor @Observable
public final class RootStore: Composable {
    public struct AppPreferences: Sendable {
        public var targetKeyCode: Int
        public var longPressDuration: Double
        public var overlayShowAnimationDuration: Double
        public var overlayHideAnimationDuration: Double
        public var showSettingsOnLaunch: Bool
        public var ignoredDeviceIDs: [String]

        public init(
            targetKeyCode: Int,
            longPressDuration: Double,
            overlayShowAnimationDuration: Double,
            overlayHideAnimationDuration: Double,
            showSettingsOnLaunch: Bool,
            ignoredDeviceIDs: [String]
        ) {
            self.targetKeyCode = targetKeyCode
            self.longPressDuration = longPressDuration
            self.overlayShowAnimationDuration = overlayShowAnimationDuration
            self.overlayHideAnimationDuration = overlayHideAnimationDuration
            self.showSettingsOnLaunch = showSettingsOnLaunch
            self.ignoredDeviceIDs = ignoredDeviceIDs
        }
    }

    private var userDefaultsRepository: UserDefaultsRepository
    private var didConsumeInitialSettingsOpenRequest: Bool

    public var showSettingsOnLaunch: Bool
    public let action: (Action) async -> Void

    public init(
        _ appDependencies: AppDependencies,
        showSettingsOnLaunch: Bool? = nil,
        didConsumeInitialSettingsOpenRequest: Bool = false,
        action: @escaping (Action) async -> Void = { _ in }
    ) {
        let userDefaultsRepository = UserDefaultsRepository(appDependencies.userDefaultsClient)
        let initialShowSettingsOnLaunch = showSettingsOnLaunch ?? userDefaultsRepository.showSettingsOnLaunch
        self.userDefaultsRepository = userDefaultsRepository
        self.showSettingsOnLaunch = initialShowSettingsOnLaunch
        self.didConsumeInitialSettingsOpenRequest = didConsumeInitialSettingsOpenRequest
        self.action = action
    }

    public func shouldOpenSettingsWindowOnLaunch() -> Bool {
        guard !didConsumeInitialSettingsOpenRequest else { return false }
        didConsumeInitialSettingsOpenRequest = true
        return showSettingsOnLaunch
    }

    public func setShowSettingsOnLaunch(_ enabled: Bool) {
        showSettingsOnLaunch = enabled
        userDefaultsRepository.showSettingsOnLaunch = enabled
    }

    public func loadAppPreferences() -> AppPreferences {
        AppPreferences(
            targetKeyCode: userDefaultsRepository.targetKeyCode,
            longPressDuration: userDefaultsRepository.longPressDuration,
            overlayShowAnimationDuration: userDefaultsRepository.overlayShowAnimationDuration,
            overlayHideAnimationDuration: userDefaultsRepository.overlayHideAnimationDuration,
            showSettingsOnLaunch: userDefaultsRepository.showSettingsOnLaunch,
            ignoredDeviceIDs: userDefaultsRepository.ignoredDeviceIDs
        )
    }

    public func saveAppPreferences(
        targetKeyCode: Int,
        longPressDuration: Double,
        overlayShowAnimationDuration: Double,
        overlayHideAnimationDuration: Double
    ) {
        userDefaultsRepository.targetKeyCode = targetKeyCode
        userDefaultsRepository.longPressDuration = longPressDuration
        userDefaultsRepository.overlayShowAnimationDuration = overlayShowAnimationDuration
        userDefaultsRepository.overlayHideAnimationDuration = overlayHideAnimationDuration
    }

    public func saveIgnoredDeviceIDs(_ ids: [String]) {
        userDefaultsRepository.ignoredDeviceIDs = ids
    }

    public enum Action: Sendable {
        case showSettingsOnLaunchToggleSwitched(Bool)
        case settingsWindowLaunchRequestConsumed
    }
}
