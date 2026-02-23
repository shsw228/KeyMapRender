import DataSource
import Observation

@MainActor @Observable
public final class RootStore: Composable {
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

    public enum Action: Sendable {
        case showSettingsOnLaunchToggleSwitched(Bool)
        case settingsWindowLaunchRequestConsumed
    }
}
