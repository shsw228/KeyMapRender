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
        WindowGroup {
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
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Third-Party Licenses…") {
                    LicenseWindowController.shared.show()
                }
            }
        }
    }
}
