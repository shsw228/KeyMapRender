//
//  ContentView.swift
//  KeyMapRender
//
//  Created by Kengo Tate on 2026/02/23.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: Pane = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tag(Pane.general)
                .tabItem { Label(Pane.general.title, systemImage: Pane.general.icon) }
            VialSettingsView()
                .tag(Pane.vial)
                .tabItem { Label(Pane.vial.title, systemImage: Pane.vial.icon) }
            StatusView()
                .tag(Pane.status)
                .tabItem { Label(Pane.status.title, systemImage: Pane.status.icon) }
            DiagnosticsView()
                .tag(Pane.diagnostics)
                .tabItem { Label(Pane.diagnostics.title, systemImage: Pane.diagnostics.icon) }
            HelpView()
                .tag(Pane.help)
                .tabItem { Label(Pane.help.title, systemImage: Pane.help.icon) }
        }
        .tabViewStyle(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum Pane: String, CaseIterable, Identifiable {
    case general
    case vial
    case status
    case diagnostics
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "一般設定"
        case .vial: return "デバイス/Vial"
        case .status: return "状態"
        case .diagnostics: return "診断ログ"
        case .help: return "情報"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .vial: return "keyboard"
        case .status: return "info.circle"
        case .diagnostics: return "wrench.and.screwdriver"
        case .help: return "questionmark.circle"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
