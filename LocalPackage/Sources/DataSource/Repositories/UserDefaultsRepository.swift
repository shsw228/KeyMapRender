import Foundation

public struct UserDefaultsRepository: Sendable {
    private var userDefaultsClient: UserDefaultsClient

    public var isEnabled: Bool {
        get {
            userDefaultsClient.bool("isEnabled")
        }
        nonmutating set {
            userDefaultsClient.setBool(newValue, "isEnabled")
        }
    }

    public var showSettingsOnLaunch: Bool {
        get {
            userDefaultsClient.optionalBool("showSettingsOnLaunch") ?? true
        }
        nonmutating set {
            userDefaultsClient.setBool(newValue, "showSettingsOnLaunch")
        }
    }

    public var targetKeyCode: Int {
        get {
            userDefaultsClient.optionalInt("targetKeyCode") ?? 49
        }
        nonmutating set {
            userDefaultsClient.setInt(newValue, "targetKeyCode")
        }
    }

    public var longPressDuration: Double {
        get {
            userDefaultsClient.optionalDouble("longPressDuration") ?? 0.45
        }
        nonmutating set {
            userDefaultsClient.setDouble(newValue, "longPressDuration")
        }
    }

    public var overlayShowAnimationDuration: Double {
        get {
            userDefaultsClient.optionalDouble("overlayShowAnimationDuration") ?? 0.24
        }
        nonmutating set {
            userDefaultsClient.setDouble(newValue, "overlayShowAnimationDuration")
        }
    }

    public var overlayHideAnimationDuration: Double {
        get {
            userDefaultsClient.optionalDouble("overlayHideAnimationDuration") ?? 0.18
        }
        nonmutating set {
            userDefaultsClient.setDouble(newValue, "overlayHideAnimationDuration")
        }
    }

    public var ignoredDeviceIDs: [String] {
        get {
            userDefaultsClient.stringArray("ignoredDeviceIDs") ?? []
        }
        nonmutating set {
            userDefaultsClient.setStringArray(newValue, "ignoredDeviceIDs")
        }
    }

    public init(_ userDefaultsClient: UserDefaultsClient) {
        self.userDefaultsClient = userDefaultsClient

#if DEBUG
        if ProcessInfo.needsResetUserDefaults {
            userDefaultsClient.removePersistentDomain(Bundle.main.bundleIdentifier!)
        }
        if ProcessInfo.needsShowAllData {
            showAllData()
        }
#endif
    }

    private func showAllData() {
        guard let dict = userDefaultsClient.persistentDomain(Bundle.main.bundleIdentifier!) else {
            return
        }
        for (key, value) in dict.sorted(by: { $0.0 < $1.0 }) {
            Swift.print("\(key) => \(value)")
        }
    }
}
