import AppKit
import Carbon.HIToolbox
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isCapturingTargetKey = false
    @State private var keyDownMonitor: Any?
    @State private var flagsChangedMonitor: Any?

    var body: some View {
        Form {
            Section("一般設定") {
                HStack {
                    Text("対象キー")
                    Spacer()
                    Button {
                        toggleTargetKeyCapture()
                    } label: {
                        VStack(spacing: 4) {
                            Text(isCapturingTargetKey ? "..." : currentKeyDisplayText)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(isCapturingTargetKey ? "入力待機中" : "クリックで変更")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 78, height: 62)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(isCapturingTargetKey ? 0.2 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isCapturingTargetKey ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
                    )
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

    private var currentKeyDisplayText: String {
        guard let keyCode = UInt16(appModel.targetKeyCodeText) else { return "-" }
        return keyLabel(for: keyCode)
    }

    private func keyLabel(for keyCode: UInt16) -> String {
        switch keyCode {
        case 56, 60: return "⇧"
        case 59, 62: return "⌃"
        case 58, 61: return "⌥"
        case 55, 54: return "⌘"
        case 57: return "⇪"
        case 63: return "fn"
        default:
            if let text = translatedKey(for: keyCode), !text.isEmpty {
                return text
            }
            return "K\(keyCode)"
        }
    }

    private func translatedKey(for keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let keyboardLayoutData = unsafeBitCast(rawData, to: CFData.self)
        guard let rawPtr = CFDataGetBytePtr(keyboardLayoutData) else { return nil }
        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(
            OpaquePointer(rawPtr)
        )

        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var actualLength = 0
        var chars: [UniChar] = Array(repeating: 0, count: maxLength)
        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &actualLength,
            &chars
        )
        guard status == noErr, actualLength > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: actualLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text == " " { return "Space" }
        return text.uppercased()
    }
}
