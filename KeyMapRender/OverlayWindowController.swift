import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private let slideDistance: CGFloat = 96
    private var showDuration: TimeInterval = 0.24
    private var hideDuration: TimeInterval = 0.18
    private var isAnimatingShow = false
    private var isAnimatingHide = false
    private var animationGeneration: UInt64 = 0

    func updateAnimationDurations(show: TimeInterval, hide: TimeInterval) {
        showDuration = max(0.05, min(show, 1.2))
        hideDuration = max(0.05, min(hide, 1.2))
    }

    func show(layout: KeyboardLayout, currentLayer: Int, totalLayers: Int) {
        let window = window ?? makeWindow()
        let wasVisible = window.isVisible
        window.contentView = NSHostingView(
            rootView: KeyboardOverlayView(
                layout: layout,
                currentLayer: currentLayer,
                totalLayers: totalLayers
            )
        )
        let targetFrame = targetPanelFrame()
        let shouldAnimateEntrance = !wasVisible || isAnimatingHide || window.alphaValue < 0.99
        if wasVisible, !shouldAnimateEntrance {
            if isAnimatingShow {
                self.window = window
                return
            }
            if window.frame != targetFrame {
                window.setFrame(targetFrame, display: true)
            }
            window.alphaValue = 1
            self.window = window
            return
        }

        animationGeneration &+= 1
        isAnimatingHide = false
        let startFrame = NSRect(
            x: targetFrame.origin.x,
            y: targetFrame.origin.y + slideDistance,
            width: targetFrame.width,
            height: targetFrame.height
        )
        window.alphaValue = 0
        window.setFrame(startFrame, display: true)
        window.orderFrontRegardless()
        isAnimatingShow = true
        let generation = animationGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = showDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if self.animationGeneration == generation {
                self.isAnimatingShow = false
            }
        })
        self.window = window
    }

    func hide() {
        guard let window else { return }
        guard window.isVisible else { return }
        animationGeneration &+= 1
        let generation = animationGeneration
        isAnimatingShow = false
        isAnimatingHide = true
        let endFrame = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y + slideDistance,
            width: window.frame.width,
            height: window.frame.height
        )
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(endFrame, display: true)
        }, completionHandler: {
            guard self.animationGeneration == generation else { return }
            self.isAnimatingHide = false
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
