import AppKit
import SwiftUI
import UserInterface

@MainActor
@main
struct KeyMapRenderApp: App {
    private let appModel: AppModel

    init() {
        let model = AppModel()
        self.appModel = model
        model.start()

        if model.shouldOpenSettingsWindowOnLaunch() {
            DispatchQueue.main.async {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    var body: some Scene {
        KeyMapRenderRootScene(appModel: appModel)
    }
}
