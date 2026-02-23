import Foundation
import IOKit.hid

struct VialProbeResult {
    let protocolVersion: String
    let layerCount: Int
    let keycodeL0R0C0: UInt16
}

struct VialKeymapDump {
    let protocolVersion: String
    let layerCount: Int
    let matrixRows: Int
    let matrixCols: Int
    let keycodes: [[[UInt16]]]
}

enum VialProbeError: Error {
    case message(String)
}

enum VialRawHIDService {
    private static let reportLength = 32
    private static let reportIDs: [CFIndex] = [0, 1]
    // Do not seize the device to avoid interfering with keyboard input in other apps.
    private static let openOptions: [IOOptionBits] = [IOOptionBits(kIOHIDOptionsTypeNone)]
    private static let reportTypePairs: [(set: IOHIDReportType, get: IOHIDReportType)] = [
        (kIOHIDReportTypeOutput, kIOHIDReportTypeInput),
        (kIOHIDReportTypeFeature, kIOHIDReportTypeFeature)
    ]

    private enum ViaCommand: UInt8 {
        case getProtocolVersion = 0x01
        case dynamicKeymapGetKeycode = 0x04
        case dynamicKeymapGetLayerCount = 0x11
        case dynamicKeymapGetBuffer = 0x12
    }

    static func probe(device: HIDKeyboardDevice) -> Result<VialProbeResult, VialProbeError> {
        withOpenedRawDevice(device: device) { raw in
            let protocolVersion = try readProtocolVersion(from: raw)
            let layerCount = try readLayerCount(from: raw)
            let keycode = try readSingleKeycode(layer: 0, row: 0, col: 0, from: raw)

            return VialProbeResult(
                protocolVersion: protocolVersion,
                layerCount: layerCount,
                keycodeL0R0C0: keycode
            )
        }
    }

    static func readKeymap(device: HIDKeyboardDevice, matrixRows: Int, matrixCols: Int) -> Result<VialKeymapDump, VialProbeError> {
        guard matrixRows > 0, matrixCols > 0 else {
            return .failure(.message("matrixRows と matrixCols は 1 以上で指定してください。"))
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
                keycodes: keycodes
            )
        }
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

    private static func send(command: ViaCommand, payload: [UInt8], to device: IOHIDDevice) throws -> [UInt8] {
        var errors: [String] = []

        for pair in reportTypePairs {
            for reportID in reportIDs {
                var outbound = [UInt8](repeating: 0, count: reportLength)
                outbound[0] = command.rawValue
                for (index, byte) in payload.enumerated() where index + 1 < reportLength {
                    outbound[index + 1] = byte
                }

                let setResult = outbound.withUnsafeMutableBufferPointer { buffer in
                    IOHIDDeviceSetReport(
                        device,
                        pair.set,
                        reportID,
                        buffer.baseAddress!,
                        reportLength
                    )
                }
                if setResult != kIOReturnSuccess {
                    errors.append("HID送信失敗(type=\(pair.set.rawValue), reportID=\(reportID)): \(setResult)")
                    continue
                }

                var inbound = [UInt8](repeating: 0, count: reportLength)
                var length = reportLength
                let getResult = inbound.withUnsafeMutableBufferPointer { buffer in
                    IOHIDDeviceGetReport(
                        device,
                        pair.get,
                        reportID,
                        buffer.baseAddress!,
                        &length
                    )
                }
                if getResult != kIOReturnSuccess {
                    errors.append("HID受信失敗(type=\(pair.get.rawValue), reportID=\(reportID)): \(getResult)")
                    continue
                }
                if length <= 0 {
                    errors.append("HID受信長が0(type=\(pair.get.rawValue), reportID=\(reportID))")
                    continue
                }

                let response = Array(inbound.prefix(length))
                let commandMatched = response.prefix(4).contains(command.rawValue)
                if !commandMatched {
                    let head = response.prefix(6).map { "0x" + String($0, radix: 16, uppercase: true) }.joined(separator: ",")
                    errors.append("応答コマンド不一致(type=\(pair.get.rawValue), reportID=\(reportID)): expected=0x\(String(command.rawValue, radix: 16, uppercase: true)) head=[\(head)]")
                    continue
                }

                return response
            }
        }

        throw VialProbeError.message(errors.joined(separator: " | "))
    }

    private static func normalizeResponse(_ response: [UInt8], command: ViaCommand) -> [UInt8] {
        if let idx = response.prefix(4).firstIndex(of: command.rawValue), idx > 0 {
            return Array(response.dropFirst(idx))
        }
        return response
    }
}
