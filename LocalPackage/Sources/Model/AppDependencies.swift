import DataSource
import SwiftUI

public final class AppDependencies: Sendable {
    public let appStateClient: AppStateClient
    public let loggingSystemClient: LoggingSystemClient
    public let userDefaultsClient: UserDefaultsClient
    public let hidKeyboardClient: HIDKeyboardClient
    public let vialRawHIDClient: VialRawHIDClient
    public let launchAtLoginClient: LaunchAtLoginClient
    public let inputAccessClient: InputAccessClient
    public let clipboardClient: ClipboardClient
    public let fileSaveClient: FileSaveClient
    public let hidKeyboardHotplugClient: HIDKeyboardHotplugClient
    public let globalKeyMonitorClient: GlobalKeyMonitorClient

    public nonisolated init(
        appStateClient: AppStateClient = .liveValue,
        loggingSystemClient: LoggingSystemClient = .liveValue,
        userDefaultsClient: UserDefaultsClient = .liveValue,
        hidKeyboardClient: HIDKeyboardClient = .liveValue,
        vialRawHIDClient: VialRawHIDClient = .liveValue,
        launchAtLoginClient: LaunchAtLoginClient = .liveValue,
        inputAccessClient: InputAccessClient = .liveValue,
        clipboardClient: ClipboardClient = .liveValue,
        fileSaveClient: FileSaveClient = .liveValue,
        hidKeyboardHotplugClient: HIDKeyboardHotplugClient = .liveValue,
        globalKeyMonitorClient: GlobalKeyMonitorClient = .liveValue
    ) {
        self.appStateClient = appStateClient
        self.loggingSystemClient = loggingSystemClient
        self.userDefaultsClient = userDefaultsClient
        self.hidKeyboardClient = hidKeyboardClient
        self.vialRawHIDClient = vialRawHIDClient
        self.launchAtLoginClient = launchAtLoginClient
        self.inputAccessClient = inputAccessClient
        self.clipboardClient = clipboardClient
        self.fileSaveClient = fileSaveClient
        self.hidKeyboardHotplugClient = hidKeyboardHotplugClient
        self.globalKeyMonitorClient = globalKeyMonitorClient
    }

    public static let shared = AppDependencies()
}

extension EnvironmentValues {
    @Entry public var appDependencies = AppDependencies.shared
}

extension AppDependencies {
    public static func testDependencies(
        appStateClient: AppStateClient = .testValue,
        loggingSystemClient: LoggingSystemClient = .testValue,
        userDefaultsClient: UserDefaultsClient = .testValue,
        hidKeyboardClient: HIDKeyboardClient = .testValue,
        vialRawHIDClient: VialRawHIDClient = .testValue,
        launchAtLoginClient: LaunchAtLoginClient = .testValue,
        inputAccessClient: InputAccessClient = .testValue,
        clipboardClient: ClipboardClient = .testValue,
        fileSaveClient: FileSaveClient = .testValue,
        hidKeyboardHotplugClient: HIDKeyboardHotplugClient = .testValue,
        globalKeyMonitorClient: GlobalKeyMonitorClient = .testValue
    ) -> AppDependencies {
        AppDependencies(
            appStateClient: appStateClient,
            loggingSystemClient: loggingSystemClient,
            userDefaultsClient: userDefaultsClient,
            hidKeyboardClient: hidKeyboardClient,
            vialRawHIDClient: vialRawHIDClient,
            launchAtLoginClient: launchAtLoginClient,
            inputAccessClient: inputAccessClient,
            clipboardClient: clipboardClient,
            fileSaveClient: fileSaveClient,
            hidKeyboardHotplugClient: hidKeyboardHotplugClient,
            globalKeyMonitorClient: globalKeyMonitorClient
        )
    }
}
