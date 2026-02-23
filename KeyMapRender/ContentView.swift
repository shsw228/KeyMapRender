//
//  ContentView.swift
//  KeyMapRender
//
//  Created by Kengo Tate on 2026/02/23.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selection: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationTitle("KeyMapRender")
            .frame(minWidth: 180)
        } detail: {
            detailView
                .navigationTitle(selection.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            Form {
                Section("基本設定") {
                    TextField("対象キーコード (例: 49 = Space)", text: $appModel.targetKeyCodeText)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("長押し判定秒数")
                        Slider(value: $appModel.longPressDuration, in: 0.2...1.5, step: 0.05)
                        Text(appModel.longPressDuration.formatted(.number.precision(.fractionLength(2))))
                            .frame(width: 48, alignment: .trailing)
                    }

                    Button("設定を保存して再適用") {
                        appModel.applySettings()
                    }

                    Toggle(
                        "PC起動時に自動起動",
                        isOn: Binding(
                            get: { appModel.launchAtLoginEnabled },
                            set: { appModel.setLaunchAtLogin($0) }
                        )
                    )
                }
            }
            .formStyle(.grouped)
            .padding(12)

        case .vial:
            Form {
                Section("接続キーボード") {
                    Picker("対象デバイス", selection: $appModel.selectedKeyboardID) {
                        if appModel.connectedKeyboards.isEmpty {
                            Text("未検出").tag("")
                        } else {
                            ForEach(appModel.connectedKeyboards) { keyboard in
                                Text("\(keyboard.manufacturerName) \(keyboard.productName)").tag(keyboard.id)
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Button("接続キーボードを再読込") {
                            appModel.refreshKeyboards()
                        }
                        .disabled(appModel.isDiagnosticsRunning)
                        Button("選択を無視") {
                            appModel.ignoreSelectedKeyboard()
                        }
                        .disabled(appModel.isDiagnosticsRunning || appModel.selectedKeyboardID.isEmpty)
                        Button("無視解除") {
                            appModel.clearIgnoredKeyboards()
                        }
                        .disabled(appModel.isDiagnosticsRunning || appModel.ignoredDeviceCount == 0)
                        Button("Vial通信テスト") {
                            appModel.probeVialOnSelectedKeyboard()
                        }
                        .disabled(appModel.isDiagnosticsRunning)
                    }

                    Text("無視中デバイス: \(appModel.ignoredDeviceCount) 台")
                    Text(appModel.keyboardStatusText)
                    Text(appModel.vialStatusText)
                }

                Section("キーマップ読出し") {
                    HStack {
                        Text("表示レイヤー")
                        Stepper(
                            value: Binding(
                                get: { appModel.selectedLayerIndex },
                                set: { appModel.setSelectedLayerIndex($0) }
                            ),
                            in: 0...max(0, appModel.availableLayerCount - 1)
                        ) {
                            Text("L\(appModel.selectedLayerIndex) / \(max(0, appModel.availableLayerCount - 1))")
                        }
                    }

                    HStack {
                        TextField("Rows", text: $appModel.matrixRowsText)
                            .textFieldStyle(.roundedBorder)
                        TextField("Cols", text: $appModel.matrixColsText)
                            .textFieldStyle(.roundedBorder)
                        Button("自動取得") {
                            appModel.autoDetectMatrixOnSelectedKeyboard()
                        }
                        .disabled(appModel.isDiagnosticsRunning)
                        Button("全マップ読出し") {
                            appModel.readFullVialKeymapOnSelectedKeyboard()
                        }
                        .disabled(appModel.isDiagnosticsRunning)
                        Button("vial.json保存") {
                            appModel.exportVialDefinitionOnSelectedKeyboard()
                        }
                        .disabled(appModel.isDiagnosticsRunning)
                    }
                    if appModel.isDiagnosticsRunning {
                        ProgressView("通信中...")
                    }

                    if !appModel.layoutChoices.isEmpty {
                        ForEach(appModel.layoutChoices) { choice in
                            Picker(choice.title, selection: Binding(
                                get: { choice.selected },
                                set: { appModel.updateLayoutChoice(index: choice.id, selected: $0) }
                            )) {
                                ForEach(Array(choice.options.enumerated()), id: \.offset) { idx, title in
                                    Text(title).tag(idx)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Text(appModel.keymapStatusText)
                    Text(appModel.keymapPreviewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .padding(12)

        case .status:
            Form {
                Section("状態") {
                    Text(appModel.permissionStatusText)
                    Text("オーバーレイ: \(appModel.isOverlayVisible ? "表示中" : "非表示")")
                    Text("レイアウト: \(appModel.layout.name)")
                }
            }
            .formStyle(.grouped)
            .padding(12)

        case .diagnostics:
            Form {
                Section("診断") {
                    HStack {
                        Button("診断ログをコピー") {
                            appModel.copyDiagnosticsLog()
                        }
                        Text("Xcodeログにも同内容を出力")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(appModel.diagnosticsLogText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .padding(12)

        case .help:
            Form {
                Section("ヘルプ") {
                    Text("初回はアクセシビリティ権限が必要です。")
                    Text("Vial/VIA JSON は `layouts.keymap` を解釈します。")
                    Button("Third-Party Licenses") {
                        LicenseWindowController.shared.show()
                    }
                }
            }
            .formStyle(.grouped)
            .padding(12)
        }
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
        case .general: return "基本設定"
        case .vial: return "Vial通信"
        case .status: return "状態"
        case .diagnostics: return "診断"
        case .help: return "ヘルプ"
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
