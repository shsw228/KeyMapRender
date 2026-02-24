import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isCapturingTargetKey = false
    @State private var keyDownMonitor: Any?
    @State private var flagsChangedMonitor: Any?

    var body: some View {
        Form {
            Section("一般設定") {
                TextField("対象キーコード (例: 49 = Space)", text: $appModel.targetKeyCodeText)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(isCapturingTargetKey ? "入力待機中... (停止)" : "キー入力で設定") {
                        toggleTargetKeyCapture()
                    }
                    .keyboardShortcut(.defaultAction)
                    Text("任意のキーを1回押すと keyCode を設定")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
        .onDisappear {
            stopTargetKeyCapture()
        }
    }

    private func toggleTargetKeyCapture() {
        if isCapturingTargetKey {
            stopTargetKeyCapture()
        } else {
            startTargetKeyCapture()
        }
    }

    private func startTargetKeyCapture() {
        guard !isCapturingTargetKey else { return }
        isCapturingTargetKey = true

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            capture(event.keyCode)
            return event
        }
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            capture(event.keyCode)
            return event
        }
    }

    private func stopTargetKeyCapture() {
        isCapturingTargetKey = false
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let flagsChangedMonitor {
            NSEvent.removeMonitor(flagsChangedMonitor)
            self.flagsChangedMonitor = nil
        }
    }

    private func capture(_ keyCode: UInt16) {
        appModel.targetKeyCodeText = String(keyCode)
        stopTargetKeyCapture()
    }
}
