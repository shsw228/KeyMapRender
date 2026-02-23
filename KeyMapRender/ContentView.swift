//
//  ContentView.swift
//  KeyMapRender
//
//  Created by Kengo Tate on 2026/02/23.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var diagnosticsExpanded = false

    var body: some View {
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
            }

            Section("Vial通信") {
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
                    Button("Vial通信テスト") {
                        appModel.probeVialOnSelectedKeyboard()
                    }
                    .disabled(appModel.isDiagnosticsRunning)
                }

                Text(appModel.keyboardStatusText)
                Text(appModel.vialStatusText)

                HStack {
                    TextField("Rows", text: $appModel.matrixRowsText)
                        .textFieldStyle(.roundedBorder)
                    TextField("Cols", text: $appModel.matrixColsText)
                        .textFieldStyle(.roundedBorder)
                    Button("全マップ読出し") {
                        appModel.readFullVialKeymapOnSelectedKeyboard()
                    }
                    .disabled(appModel.isDiagnosticsRunning)
                }
                if appModel.isDiagnosticsRunning {
                    ProgressView("通信中...")
                }
                Text(appModel.keymapStatusText)
                Text(appModel.keymapPreviewText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("状態") {
                Text(appModel.permissionStatusText)
                Text("オーバーレイ: \(appModel.isOverlayVisible ? "表示中" : "非表示")")
                Text("レイアウト: \(appModel.layout.name)")
            }

            Section("診断") {
                DisclosureGroup("通信ログ", isExpanded: $diagnosticsExpanded) {
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

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
