import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?

    func show(layout: KeyboardLayout, currentLayer: Int, totalLayers: Int) {
        let window = window ?? makeWindow()
        window.contentView = NSHostingView(
            rootView: KeyboardOverlayView(
                layout: layout,
                currentLayer: currentLayer,
                totalLayers: totalLayers
            )
        )
        window.setFrame(targetScreenFrame(), display: true)
        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: targetScreenFrame(),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return window
    }

    private func targetScreenFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen.frame
        }
        if let main = NSScreen.main {
            return main.frame
        }
        return NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
    }
}
