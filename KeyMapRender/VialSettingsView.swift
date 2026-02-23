import SwiftUI
import DataSource
import Model

struct VialSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
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
    }
}
