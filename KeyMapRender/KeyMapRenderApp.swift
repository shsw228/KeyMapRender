//
//  KeyMapRenderApp.swift
//  KeyMapRender
//
//  Created by Kengo Tate on 2026/02/23.
//

import SwiftUI
import AppIntents
import DataSource

@main
struct KeyMapRenderApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
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

private struct MenuBarContentView: View {
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
        .onAppear {
            appModel.start()
            appModel.refreshLaunchAtLoginStatus()
            if appModel.shouldOpenSettingsWindowOnLaunch() {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
