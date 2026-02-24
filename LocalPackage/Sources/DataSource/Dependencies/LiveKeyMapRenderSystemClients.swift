import AppKit
import ApplicationServices
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

extension LaunchAtLoginClient {
    public static let keyMapRenderLiveValue = Self(
        status: {
            guard #available(macOS 13.0, *) else {
                return .failure(.message("自動起動設定は macOS 13 以降で利用できます。"))
            }
            return .success(SMAppService.mainApp.status == .enabled)
        },
        setEnabled: { enabled in
            guard #available(macOS 13.0, *) else {
                return .failure(.message("自動起動設定は macOS 13 以降で利用できます。"))
            }
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return .success(SMAppService.mainApp.status == .enabled)
            } catch {
                return .failure(.message(error.localizedDescription))
            }
        }
    )
}

extension InputAccessClient {
    public static let keyMapRenderLiveValue = Self(
        checkStatus: { promptAccessibility, requestInputMonitoring in
            let options = ["AXTrustedCheckOptionPrompt": promptAccessibility] as CFDictionary
            let axTrusted = AXIsProcessTrustedWithOptions(options)
            let listenTrusted = CGPreflightListenEventAccess()
            if requestInputMonitoring {
                _ = CGRequestListenEventAccess()
            }
            return InputAccessStatus(
                accessibilityTrusted: axTrusted,
                inputMonitoringTrusted: listenTrusted
            )
        }
    )
}

extension ClipboardClient {
    public static let keyMapRenderLiveValue = Self(
        copyString: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    )
}

extension FileSaveClient {
    public static let keyMapRenderLiveValue = Self(
        saveText: { request in
            MainActor.assumeIsolated {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = request.suggestedFileName
                let contentTypes = request.allowedExtensions.compactMap { UTType(filenameExtension: $0) }
                if !contentTypes.isEmpty {
                    panel.allowedContentTypes = contentTypes
                }
                panel.canCreateDirectories = true
                panel.title = request.title
                let response = panel.runModal()
                guard response == .OK, let url = panel.url else {
                    return .success(.cancelled)
                }
                do {
                    try request.content.write(to: url, atomically: true, encoding: .utf8)
                    return .success(.saved(path: url.path))
                } catch {
                    return .failure(.message(error.localizedDescription))
                }
            }
        }
    )
}

@MainActor
private final class OverlayWindowRegistry {
    static let shared = OverlayWindowRegistry()
    private let lock = NSLock()
    private var controller: OverlayWindowController?

    private init() {}

    private func resolveController() -> OverlayWindowController {
        lock.lock()
        defer { lock.unlock() }
        if let controller {
            return controller
        }
        let newController = OverlayWindowController()
        controller = newController
        return newController
    }

    func updateAnimationDurations(show: Double, hide: Double) {
        resolveController().updateAnimationDurations(show: show, hide: hide)
    }

    func show(layout: KeyboardLayout, currentLayer: Int, totalLayers: Int) {
        resolveController().show(
            layout: layout,
            currentLayer: currentLayer,
            totalLayers: totalLayers
        )
    }

    func hide() {
        resolveController().hide()
    }
}

extension OverlayWindowClient {
    public static let keyMapRenderLiveValue = Self(
        updateAnimationDurations: { show, hide in
            MainActor.assumeIsolated {
                OverlayWindowRegistry.shared.updateAnimationDurations(show: show, hide: hide)
            }
        },
        show: { layout, currentLayer, totalLayers in
            MainActor.assumeIsolated {
                OverlayWindowRegistry.shared.show(
                    layout: layout,
                    currentLayer: currentLayer,
                    totalLayers: totalLayers
                )
            }
        },
        hide: {
            MainActor.assumeIsolated {
                OverlayWindowRegistry.shared.hide()
            }
        }
    )
}
