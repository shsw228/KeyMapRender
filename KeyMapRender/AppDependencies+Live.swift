import AppKit
import DataSource
import Foundation
import Model
import ServiceManagement
import ApplicationServices
import UniformTypeIdentifiers

extension AppDependencies {
    static let keyMapRenderLive = AppDependencies(
        hidKeyboardClient: .keyMapRenderLiveValue,
        vialRawHIDClient: .keyMapRenderLiveValue,
        launchAtLoginClient: .keyMapRenderLiveValue,
        inputAccessClient: .keyMapRenderLiveValue,
        clipboardClient: .keyMapRenderLiveValue,
        fileSaveClient: .keyMapRenderLiveValue,
        hidKeyboardHotplugClient: .keyMapRenderLiveValue
    )
}

extension HIDKeyboardClient {
    static let keyMapRenderLiveValue = Self(
        listKeyboards: {
            HIDKeyboardService.listKeyboards()
        }
    )
}

extension VialRawHIDClient {
    static let keyMapRenderLiveValue = Self(
        probe: { device in
            VialRawHIDService.probe(device: device)
        },
        readKeymap: { device, rows, cols in
            VialRawHIDService.readKeymap(device: device, matrixRows: rows, matrixCols: cols)
        },
        inferMatrix: { device in
            VialRawHIDService.inferMatrix(device: device)
        },
        readDefinition: { device in
            VialRawHIDService.readDefinition(device: device)
        },
        readSwitchMatrixState: { device, rows, cols in
            VialRawHIDService.readSwitchMatrixState(device: device, matrixRows: rows, matrixCols: cols)
        }
    )
}

extension LaunchAtLoginClient {
    static let keyMapRenderLiveValue = Self(
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
    static let keyMapRenderLiveValue = Self(
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
    static let keyMapRenderLiveValue = Self(
        copyString: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    )
}

extension FileSaveClient {
    static let keyMapRenderLiveValue = Self(
        saveText: { request in
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
    )
}

@MainActor
private final class HotplugMonitorRegistry {
    static let shared = HotplugMonitorRegistry()
    private var monitors: [UUID: HIDKeyboardHotplugMonitor] = [:]

    private init() {}

    func start(onChanged: @escaping @Sendable () -> Void) -> Result<HIDKeyboardHotplugSession, HIDKeyboardHotplugError> {
        let id = UUID()
        let monitor = HIDKeyboardHotplugMonitor {
            onChanged()
        }
        guard monitor.start() else {
            return .failure(.message("start failed"))
        }
        monitors[id] = monitor
        return .success(HIDKeyboardHotplugSession(id: id))
    }

    func stop(_ session: HIDKeyboardHotplugSession) {
        guard let monitor = monitors.removeValue(forKey: session.id) else { return }
        monitor.stop()
    }
}

extension HIDKeyboardHotplugClient {
    static let keyMapRenderLiveValue = Self(
        start: { onChanged in
            let container = DispatchSemaphore(value: 0)
            var result: Result<HIDKeyboardHotplugSession, HIDKeyboardHotplugError> = .failure(.message("internal error"))
            Task { @MainActor in
                result = HotplugMonitorRegistry.shared.start(onChanged: onChanged)
                container.signal()
            }
            container.wait()
            return result
        },
        stop: { session in
            Task { @MainActor in
                HotplugMonitorRegistry.shared.stop(session)
            }
        }
    )
}
