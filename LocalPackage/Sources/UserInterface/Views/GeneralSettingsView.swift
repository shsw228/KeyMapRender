import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("一般設定") {
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

                Toggle(
                    "起動時に設定画面を表示",
                    isOn: Binding(
                        get: { appModel.showSettingsOnLaunch },
                        set: { appModel.setShowSettingsOnLaunch($0) }
                    )
                )
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}
