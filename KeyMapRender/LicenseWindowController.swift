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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Third-Party Licenses")
                .font(.headline)
            ScrollView {
                Text(ThirdPartyLicenses.load())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }
}
