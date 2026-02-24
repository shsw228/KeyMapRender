import DataSource
import Model

extension AppDependencies {
    static let keyMapRenderLive = AppDependencies(
        hidKeyboardClient: .keyMapRenderLiveValue,
        vialRawHIDClient: .keyMapRenderLiveValue,
        launchAtLoginClient: .keyMapRenderLiveValue,
        inputAccessClient: .keyMapRenderLiveValue,
        clipboardClient: .keyMapRenderLiveValue,
        fileSaveClient: .keyMapRenderLiveValue,
        hidKeyboardHotplugClient: .keyMapRenderLiveValue,
        globalKeyMonitorClient: .keyMapRenderLiveValue,
        overlayWindowClient: .keyMapRenderLiveValue
    )
}
