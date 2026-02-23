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
                .frame(minWidth: 520, minHeight: 340)
                .onAppear {
                    appModel.start()
                }
        }
    }
}
