import SwiftUI

struct HelpView: View {
    var body: some View {
        Form {
            Section("情報とライセンス") {
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
