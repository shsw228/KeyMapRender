import Foundation
import IOKit.hid

struct VialProbeResult {
    let protocolVersion: String
    let layerCount: Int
    let keycodeL0R0C0: UInt16
    let backend: String
}

struct VialKeymapDump {
    let protocolVersion: String
    let layerCount: Int
    let matrixRows: Int
    let matrixCols: Int
    let keycodes: [[[UInt16]]]
    let layoutKeymapRows: [[Any]]?
    let layoutLabels: [Any]?
    let layoutOptions: UInt32?
    let backend: String
}

struct VialMatrixInfo {
    let rows: Int
    let cols: Int
    let backend: String
}

struct VialSwitchMatrixState {
    let rows: Int
    let cols: Int
    let pressed: [[Bool]]
    let backend: String
}

enum VialProbeError: Error {
    case message(String)
}

enum VialRawHIDService {
    private static let reportLength = 32
    private static let reportIDs: [CFIndex] = [0, 1]
    private static let hidSendRetries = 20
    private static let hidReadTimeoutSeconds: CFTimeInterval = 0.5
    private static let matrixPollRetries = 2
    private static let matrixPollReadTimeoutSeconds: CFTimeInterval = 0.02
    private static let matrixPollRetrySleepSeconds: CFTimeInterval = 0.005
    // Do not seize the device to avoid interfering with keyboard input in other apps.
    private static let openOptions: [IOOptionBits] = [IOOptionBits(kIOHIDOptionsTypeNone)]

    private enum ViaCommand: UInt8 {
        case getProtocolVersion = 0x01
        case getKeyboardValue = 0x02
        case dynamicKeymapGetKeycode = 0x04
        case dynamicKeymapGetLayerCount = 0x11
        case dynamicKeymapGetBuffer = 0x12
    }

    private enum BridgeMode: String {
        case probe
        case dump
        case matrix
        case definition
    }

    private final class InputReportCapture {
        var response: [UInt8]?
    }

    static func probe(device: HIDKeyboardDevice) -> Result<VialProbeResult, VialProbeError> {
        if let bridge = probeViaPythonBridge(device: device) {
            return bridge
        }
        return withOpenedRawDevice(device: device) { raw in
            let protocolVersion = try readProtocolVersion(from: raw)
            let layerCount = try readLayerCount(from: raw)
            let keycode = try readSingleKeycode(layer: 0, row: 0, col: 0, from: raw)

            return VialProbeResult(
                protocolVersion: protocolVersion,
                layerCount: layerCount,
                keycodeL0R0C0: keycode,
                backend: "native"
            )
        }
    }

    static func readKeymap(device: HIDKeyboardDevice, matrixRows: Int, matrixCols: Int) -> Result<VialKeymapDump, VialProbeError> {
        guard matrixRows > 0, matrixCols > 0 else {
            return .failure(.message("matrixRows と matrixCols は 1 以上で指定してください。"))
        }

        if let bridge = dumpViaPythonBridge(device: device, rows: matrixRows, cols: matrixCols) {
            return bridge
        }

        return withOpenedRawDevice(device: device) { raw in
            let protocolVersion = try readProtocolVersion(from: raw)
            let layerCount = try readLayerCount(from: raw)
            let totalBytes = layerCount * matrixRows * matrixCols * 2
            let rawKeymap = try readBuffer(offset: 0, totalBytes: totalBytes, from: raw)

            var keycodes = Array(
                repeating: Array(repeating: Array(repeating: UInt16(0), count: matrixCols), count: matrixRows),
                count: layerCount
            )

            for layer in 0..<layerCount {
                for row in 0..<matrixRows {
                    for col in 0..<matrixCols {
                        let base = ((layer * matrixRows * matrixCols) + (row * matrixCols) + col) * 2
                        guard base + 1 < rawKeymap.count else { continue }
                        let keycode = UInt16(rawKeymap[base]) << 8 | UInt16(rawKeymap[base + 1])
                        keycodes[layer][row][col] = keycode
                    }
                }
            }

            return VialKeymapDump(
                protocolVersion: protocolVersion,
                layerCount: layerCount,
                matrixRows: matrixRows,
                matrixCols: matrixCols,
                keycodes: keycodes,
                layoutKeymapRows: nil,
                layoutLabels: nil,
                layoutOptions: nil,
                backend: "native"
            )
        }
    }

    static func inferMatrix(device: HIDKeyboardDevice) -> Result<VialMatrixInfo, VialProbeError> {
        guard let json = runPythonBridge(mode: .matrix, device: device, rows: nil, cols: nil) else {
            return .failure(.message("python bridge が見つかりません。"))
        }
        guard let ok = json["ok"] as? Bool else { return .failure(.message("python bridge: invalid response")) }
        if !ok {
            let message = json["error"] as? String ?? "unknown error"
            return .failure(.message("python bridge: \(message)"))
        }
        guard
            let rows = json["matrix_rows"] as? Int,
            let cols = json["matrix_cols"] as? Int
        else {
            return .failure(.message("python bridge: missing matrix fields"))
        }
        return .success(VialMatrixInfo(rows: rows, cols: cols, backend: "python"))
    }

    static func readDefinition(device: HIDKeyboardDevice) -> Result<String, VialProbeError> {
        guard let json = runPythonBridge(mode: .definition, device: device, rows: nil, cols: nil) else {
            return .failure(.message("python bridge が見つかりません。"))
        }
        guard let ok = json["ok"] as? Bool else { return .failure(.message("python bridge: invalid response")) }
        if !ok {
            let message = json["error"] as? String ?? "unknown error"
            return .failure(.message("python bridge: \(message)"))
        }
        guard let definition = json["definition"] else {
            return .failure(.message("python bridge: missing definition"))
        }
        guard JSONSerialization.isValidJSONObject(definition) else {
            return .failure(.message("python bridge: definition is not valid json object"))
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: definition, options: [.prettyPrinted, .sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(.message("definition の UTF-8 変換に失敗しました。"))
            }
            return .success(text + "\n")
        } catch {
            return .failure(.message("definition の整形に失敗: \(error.localizedDescription)"))
        }
    }

    static func readSwitchMatrixState(
        device: HIDKeyboardDevice,
        matrixRows: Int,
        matrixCols: Int
    ) -> Result<VialSwitchMatrixState, VialProbeError> {
        guard matrixRows > 0, matrixCols > 0 else {
            return .failure(.message("matrixRows と matrixCols は 1 以上で指定してください。"))
        }
        let rowSize = (matrixCols + 7) / 8
        let payloadSize = rowSize * matrixRows
        guard payloadSize <= 28 else {
            return .failure(.message("matrix size exceeds VIA_SWITCH_MATRIX_STATE limit (rows=\(matrixRows), cols=\(matrixCols))"))
        }

        return withOpenedRawDevice(device: device) { raw in
            let response = normalizeResponse(
                try send(
                    command: .getKeyboardValue,
                    payload: [0x03],
                    to: raw,
                    retries: matrixPollRetries,
                    timeout: matrixPollReadTimeoutSeconds,
                    retrySleep: matrixPollRetrySleepSeconds
                ),
                command: .getKeyboardValue
            )
            let expected = 2 + payloadSize
            guard response.count >= expected else {
                throw VialProbeError.message("matrix state 応答サイズ不足: expected>=\(expected), actual=\(response.count)")
            }

            var pressed = Array(
                repeating: Array(repeating: false, count: matrixCols),
                count: matrixRows
            )
            for row in 0..<matrixRows {
                let start = 2 + row * rowSize
                let end = start + rowSize
                let rowData = Array(response[start..<end])
                for col in 0..<matrixCols {
                    let byteIndex = rowData.count - 1 - (col / 8)
                    let bitIndex = col % 8
                    let bit = (rowData[byteIndex] >> bitIndex) & 0x01
                    pressed[row][col] = (bit == 1)
                }
            }

            return VialSwitchMatrixState(
                rows: matrixRows,
                cols: matrixCols,
                pressed: pressed,
                backend: "native"
            )
        }
    }

    private static func probeViaPythonBridge(device: HIDKeyboardDevice) -> Result<VialProbeResult, VialProbeError>? {
        guard let json = runPythonBridge(mode: .probe, device: device, rows: nil, cols: nil) else { return nil }
        guard let ok = json["ok"] as? Bool else { return .failure(.message("python bridge: invalid response")) }
        if !ok {
            let message = json["error"] as? String ?? "unknown error"
            if shouldFallbackToNative(for: message) {
                return nil
            }
            return .failure(.message("python bridge: \(message)"))
        }
        guard
            let protocolVersion = json["protocol_version"] as? String,
            let layerCount = json["layer_count"] as? Int,
            let keycode = json["keycode_l0_r0_c0"] as? Int
        else {
            return .failure(.message("python bridge: missing fields"))
        }
        return .success(
            VialProbeResult(
                protocolVersion: protocolVersion,
                layerCount: layerCount,
                keycodeL0R0C0: UInt16(clamping: keycode),
                backend: "python"
            )
        )
    }

    private static func dumpViaPythonBridge(device: HIDKeyboardDevice, rows: Int, cols: Int) -> Result<VialKeymapDump, VialProbeError>? {
        guard let json = runPythonBridge(mode: .dump, device: device, rows: rows, cols: cols) else { return nil }
        guard let ok = json["ok"] as? Bool else { return .failure(.message("python bridge: invalid response")) }
        if !ok {
            let message = json["error"] as? String ?? "unknown error"
            if shouldFallbackToNative(for: message) {
                return nil
            }
            return .failure(.message("python bridge: \(message)"))
        }

        guard
            let protocolVersion = json["protocol_version"] as? String,
            let layerCount = json["layer_count"] as? Int,
            let matrixRows = json["matrix_rows"] as? Int,
            let matrixCols = json["matrix_cols"] as? Int,
            let anyKeycodes = json["keycodes"] as? [[[Any]]]
        else {
            return .failure(.message("python bridge: missing fields"))
        }
        let layoutKeymapRows = json["layout_keymap"] as? [[Any]]
        let layoutLabels = json["layout_labels"] as? [Any]
        let layoutOptions = (json["layout_options"] as? NSNumber).map { UInt32(truncating: $0) }

        var keycodes: [[[UInt16]]] = []
        keycodes.reserveCapacity(anyKeycodes.count)
        for layer in anyKeycodes {
            var rowsParsed: [[UInt16]] = []
            rowsParsed.reserveCapacity(layer.count)
            for row in layer {
                rowsParsed.append(row.map {
                    if let intValue = $0 as? Int {
                        return UInt16(clamping: intValue)
                    }
                    if let number = $0 as? NSNumber {
                        return UInt16(clamping: number.intValue)
                    }
                    return 0
                })
            }
            keycodes.append(rowsParsed)
        }

        return .success(
            VialKeymapDump(
                protocolVersion: protocolVersion,
                layerCount: layerCount,
                matrixRows: matrixRows,
                matrixCols: matrixCols,
                keycodes: keycodes,
                layoutKeymapRows: layoutKeymapRows,
                layoutLabels: layoutLabels,
                layoutOptions: layoutOptions,
                backend: "python"
            )
        )
    }

    private static func runPythonBridge(
        mode: BridgeMode,
        device: HIDKeyboardDevice,
        rows: Int?,
        cols: Int?
    ) -> [String: Any]? {
        guard let scriptURL = Bundle.main.url(forResource: "vial_hid_bridge", withExtension: "py") else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        var args = [scriptURL.path, mode.rawValue, "--vid", "0x" + String(device.vendorID, radix: 16), "--pid", "0x" + String(device.productID, radix: 16)]
        if mode == .dump, let rows, let cols {
            args.append(contentsOf: ["--rows", "\(rows)", "--cols", "\(cols)"])
        }
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ["ok": false, "error": "python bridge launch failed: \(error.localizedDescription)"]
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !outData.isEmpty else {
            return ["ok": false, "error": "python bridge empty output \(errString)"]
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: outData),
            let dict = object as? [String: Any]
        else {
            let raw = String(data: outData, encoding: .utf8) ?? "<non-utf8>"
            return ["ok": false, "error": "python bridge invalid json: \(raw) \(errString)"]
        }
        return dict
    }

    private static func shouldFallbackToNative(for message: String) -> Bool {
        let lower = message.lowercased()
        // If python bridge path is unstable, prefer native RawHID path.
        return lower.contains("python hid module is not available")
            || lower.contains("no module named 'hid'")
            || lower.contains("python bridge launch failed")
            || lower.contains("input format not supported by decoder")
            || lower.contains("invalid definition size")
            || lower.contains("invalid layer count")
            || lower.contains("open_path failed")
            || lower.contains("path=")
    }

    private static func withOpenedRawDevice<T>(
        device: HIDKeyboardDevice,
        operation: (IOHIDDevice) throws -> T
    ) -> Result<T, VialProbeError> {
        let candidates = HIDKeyboardService.findCandidateInterfaces(for: device)
        guard !candidates.isEmpty else {
            return .failure(.message("対象VID/PIDのHIDインターフェイスが見つかりません。"))
        }

        var errors: [String] = []
        for candidate in candidates {
            var opened = false
            var openErrorCodes: [String] = []
            for openOption in openOptions {
                let openResult = IOHIDDeviceOpen(candidate.device, openOption)
                if openResult != kIOReturnSuccess {
                    openErrorCodes.append("opt=\(openOption):\(openResult)")
                    continue
                }
                opened = true
                defer { IOHIDDeviceClose(candidate.device, openOption) }

                do {
                    return .success(try operation(candidate.device))
                } catch {
                    let msg: String
                    if let typed = error as? VialProbeError, case let .message(text) = typed {
                        msg = text
                    } else {
                        msg = error.localizedDescription
                    }
                    errors.append("probe失敗 usagePage=0x\(String(candidate.usagePage, radix: 16, uppercase: true)) usage=0x\(String(candidate.usage, radix: 16, uppercase: true)) openOpt=\(openOption) detail=\(msg)")
                }
            }
            if !opened {
                errors.append("open失敗 usagePage=0x\(String(candidate.usagePage, radix: 16, uppercase: true)) usage=0x\(String(candidate.usage, radix: 16, uppercase: true)) code=\(openErrorCodes.joined(separator: ","))")
            }
        }

        return .failure(.message(errors.joined(separator: " | ")))
    }

    private static func readProtocolVersion(from raw: IOHIDDevice) throws -> String {
        let protocolBytes = normalizeResponse(try send(command: .getProtocolVersion, payload: [], to: raw), command: .getProtocolVersion)
        guard protocolBytes.count >= 3 else {
            throw VialProbeError.message("プロトコル応答が不正です。")
        }
        let proto = UInt16(protocolBytes[1]) << 8 | UInt16(protocolBytes[2])
        return "0x" + String(proto, radix: 16, uppercase: true)
    }

    private static func readLayerCount(from raw: IOHIDDevice) throws -> Int {
        let layerBytes = normalizeResponse(try send(command: .dynamicKeymapGetLayerCount, payload: [], to: raw), command: .dynamicKeymapGetLayerCount)
        guard layerBytes.count >= 2 else {
            throw VialProbeError.message("レイヤー応答が不正です。")
        }
        return Int(layerBytes[1])
    }

    private static func readSingleKeycode(layer: UInt8, row: UInt8, col: UInt8, from raw: IOHIDDevice) throws -> UInt16 {
        let keyBytes = normalizeResponse(try send(command: .dynamicKeymapGetKeycode, payload: [layer, row, col], to: raw), command: .dynamicKeymapGetKeycode)
        guard keyBytes.count >= 6 else {
            throw VialProbeError.message("キーコード応答が不正です。")
        }
        return UInt16(keyBytes[4]) << 8 | UInt16(keyBytes[5])
    }

    private static func readBuffer(offset: Int, totalBytes: Int, from raw: IOHIDDevice) throws -> [UInt8] {
        let chunkLimit = 28
        var cursor = offset
        var bytes: [UInt8] = []
        bytes.reserveCapacity(totalBytes)

        while bytes.count < totalBytes {
            let remain = totalBytes - bytes.count
            let chunkSize = min(chunkLimit, remain)
            let payload: [UInt8] = [
                UInt8((cursor >> 8) & 0xFF),
                UInt8(cursor & 0xFF),
                UInt8(chunkSize)
            ]
            let response = normalizeResponse(try send(command: .dynamicKeymapGetBuffer, payload: payload, to: raw), command: .dynamicKeymapGetBuffer)
            let expected = 4 + chunkSize
            guard response.count >= expected else {
                throw VialProbeError.message("バッファ応答サイズ不足: expected>=\(expected), actual=\(response.count)")
            }
            bytes.append(contentsOf: response[4..<expected])
            cursor += chunkSize
        }

        return bytes
    }

    private static func send(
        command: ViaCommand,
        payload: [UInt8],
        to device: IOHIDDevice,
        retries: Int = hidSendRetries,
        timeout: CFTimeInterval = hidReadTimeoutSeconds,
        retrySleep: CFTimeInterval = 0.05
    ) throws -> [UInt8] {
        var errors: [String] = []
        var outbound = [UInt8](repeating: 0, count: reportLength)
        outbound[0] = command.rawValue
        for (index, byte) in payload.enumerated() where index + 1 < reportLength {
            outbound[index + 1] = byte
        }

        for retry in 0..<max(1, retries) {
            for reportID in reportIDs {
                let setResult = outbound.withUnsafeMutableBufferPointer { buffer in
                    IOHIDDeviceSetReport(
                        device,
                        kIOHIDReportTypeOutput,
                        reportID,
                        buffer.baseAddress!,
                        reportLength
                    )
                }
                if setResult != kIOReturnSuccess {
                    errors.append("retry=\(retry) reportID=\(reportID) HID送信失敗(type=output): \(setResult)")
                    continue
                }

                if let callbackResponse = receiveViaInputCallback(device: device, timeout: timeout) {
                    if isCommandMatched(response: callbackResponse, command: command) {
                        return callbackResponse
                    }
                    let head = callbackResponse.prefix(6).map { "0x" + String($0, radix: 16, uppercase: true) }.joined(separator: ",")
                    errors.append("retry=\(retry) reportID=\(reportID) 受信はしたがコマンド不一致: expected=0x\(String(command.rawValue, radix: 16, uppercase: true)) head=[\(head)]")
                    continue
                }

                errors.append("retry=\(retry) reportID=\(reportID) 受信タイムアウト(\(timeout)s)")
            }
            Thread.sleep(forTimeInterval: retrySleep)
        }

        throw VialProbeError.message(errors.joined(separator: " | "))
    }

    private static func normalizeResponse(_ response: [UInt8], command: ViaCommand) -> [UInt8] {
        if let idx = response.prefix(4).firstIndex(of: command.rawValue), idx > 0 {
            return Array(response.dropFirst(idx))
        }
        return response
    }

    private static func isCommandMatched(response: [UInt8], command: ViaCommand) -> Bool {
        response.prefix(4).contains(command.rawValue)
    }

    private static let inputReportCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
        guard let context else { return }
        let capture = Unmanaged<InputReportCapture>.fromOpaque(context).takeUnretainedValue()
        if capture.response == nil {
            capture.response = Array(UnsafeBufferPointer(start: report, count: Int(reportLength)))
        }
    }

    private static func receiveViaInputCallback(device: IOHIDDevice, timeout: CFTimeInterval) -> [UInt8]? {
        let capture = InputReportCapture()
        let retained = Unmanaged.passRetained(capture)
        var reportBuffer = [UInt8](repeating: 0, count: reportLength)
        let mode = CFRunLoopMode.defaultMode.rawValue
        guard let runLoop = CFRunLoopGetCurrent() else {
            retained.release()
            return nil
        }

        IOHIDDeviceScheduleWithRunLoop(device, runLoop, mode)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            &reportBuffer,
            reportBuffer.count,
            inputReportCallback,
            retained.toOpaque()
        )

        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            if let response = capture.response {
                IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, mode)
                retained.release()
                return response
            }
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, true)
        }

        IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, mode)
        retained.release()
        return nil
    }
}
