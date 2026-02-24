import SwiftUI
import DataSource

public struct KeyMapRenderRootScene: Scene {
    @StateObject private var appModel = AppModel()

    public init() {}

    public var body: some Scene {
        MenuBarExtra("KeyMapRender", systemImage: "keyboard") {
            MenuBarContentView()
                .environmentObject(appModel)
        }
        Settings {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 640, minHeight: 380)
                .onAppear {
                    appModel.start()
                }
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
