import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("設定を開く") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("終了") {
                appModel.shutdown()
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 4)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            appModel.shutdown()
        }
    }
}
