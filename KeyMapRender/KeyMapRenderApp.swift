//
//  KeyMapRenderApp.swift
//  KeyMapRender
//
//  Created by Kengo Tate on 2026/02/23.
//

import SwiftUI

@main
struct KeyMapRenderApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 640, minHeight: 380)
                .onAppear {
                    appModel.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appModel.shutdown()
                }
        }
        MenuBarExtra("KeyMapRender", systemImage: "keyboard") {
            MenuBarContentView()
                .environmentObject(appModel)
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

private struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("設定を開く") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("終了") {
                appModel.shutdown()
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            appModel.start()
            appModel.refreshLaunchAtLoginStatus()
        }
    }
}
