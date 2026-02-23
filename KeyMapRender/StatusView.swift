import SwiftUI
import DataSource

struct StatusView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("オーバーレイ状態") {
                Text(appModel.permissionStatusText)
                Text("オーバーレイ: \(appModel.isOverlayVisible ? "表示中" : "非表示")")
                Text("レイアウト: \(appModel.layout.name)")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}
