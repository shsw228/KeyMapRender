import SwiftUI
import DataSource

public struct KeyMapRenderRootScene: Scene {
    @ObservedObject private var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some Scene {
        MenuBarExtra("KeyMapRender", systemImage: "keyboard") {
            MenuBarContentView()
                .environmentObject(appModel)
        }
        Settings {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 640, minHeight: 380)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Third-Party Licenses…") {
                    LicenseWindowController.shared.show()
                }
            }
        }
    }
}
