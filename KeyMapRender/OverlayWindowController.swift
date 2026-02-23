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
        let targetFrame = targetPanelFrame()
        if window.frame.size != targetFrame.size {
            window.setFrame(targetFrame, display: true)
        }
        let startFrame = NSRect(
            x: targetFrame.origin.x,
            y: targetFrame.origin.y + 24,
            width: targetFrame.width,
            height: targetFrame.height
        )
        window.alphaValue = 0
        window.setFrame(startFrame, display: true)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(targetFrame, display: true)
        }
        self.window = window
    }

    func hide() {
        guard let window else { return }
        let endFrame = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y + 24,
            width: window.frame.width,
            height: window.frame.height
        )
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(endFrame, display: true)
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: targetPanelFrame(),
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

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func targetPanelFrame() -> NSRect {
        let screenFrame = targetScreen()?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let width = min(max(860, screenFrame.width * 0.72), 1320)
        let height = min(max(220, screenFrame.height * 0.34), 380)
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.maxY - height - 18
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
