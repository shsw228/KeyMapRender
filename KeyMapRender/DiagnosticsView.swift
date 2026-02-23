import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("診断ログ") {
                HStack {
                    Button("診断ログをコピー") {
                        appModel.copyDiagnosticsLog()
                    }
                    Text("Xcode/Console にも同内容を出力")
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
    }
}
