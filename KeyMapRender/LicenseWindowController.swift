import AppKit
import SwiftUI

@MainActor
final class LicenseWindowController {
    static let shared = LicenseWindowController()

    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        window.contentView = NSHostingView(rootView: ThirdPartyLicensesView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Third-Party Licenses"
        window.center()
        return window
    }
}

struct ThirdPartyLicensesView: View {
    private let libraries = ThirdPartyLicenses.libraries()
    @State private var selectionID: String?

    var body: some View {
        NavigationSplitView {
            List(libraries, selection: $selectionID) { item in
                Text(item.name)
                    .tag(item.id)
            }
            .navigationTitle("Third-Party Licenses")
            .onAppear {
                if selectionID == nil {
                    selectionID = libraries.first?.id
                }
            }
        } detail: {
            if let selected = libraries.first(where: { $0.id == selectionID }) {
                ScrollView {
                    Text(selected.body)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .navigationTitle(selected.name)
            } else {
                ContentUnavailableView("ライセンスを選択", systemImage: "doc.text")
            }
        }
    }
}
