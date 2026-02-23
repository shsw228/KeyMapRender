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
        guard let raw = HIDKeyboardService.findRawHIDInterface(for: device) else {
            return .failure(.message("Vial Raw HIDインターフェイス (usagePage=0xFF60, usage=0x61) が見つかりません。"))
        }

        let openResult = IOHIDDeviceOpen(raw, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return .failure(.message("HIDデバイスを開けませんでした: \(openResult)"))
        }
        defer {
            IOHIDDeviceClose(raw, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        do {
            return .success(try operation(raw))
        } catch {
            if let typed = error as? VialProbeError {
                return .failure(typed)
            }
            return .failure(.message("不明なエラー: \(error.localizedDescription)"))
        }
    }

    private static func readProtocolVersion(from raw: IOHIDDevice) throws -> String {
        let protocolBytes = try send(command: .getProtocolVersion, payload: [], to: raw)
        guard protocolBytes.count >= 3 else {
            throw VialProbeError.message("プロトコル応答が不正です。")
        }
        let proto = UInt16(protocolBytes[1]) << 8 | UInt16(protocolBytes[2])
        return "0x" + String(proto, radix: 16, uppercase: true)
    }

    private static func readLayerCount(from raw: IOHIDDevice) throws -> Int {
        let layerBytes = try send(command: .dynamicKeymapGetLayerCount, payload: [], to: raw)
        guard layerBytes.count >= 2 else {
            throw VialProbeError.message("レイヤー応答が不正です。")
        }
        return Int(layerBytes[1])
    }

    private static func readSingleKeycode(layer: UInt8, row: UInt8, col: UInt8, from raw: IOHIDDevice) throws -> UInt16 {
        let keyBytes = try send(command: .dynamicKeymapGetKeycode, payload: [layer, row, col], to: raw)
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
            let response = try send(command: .dynamicKeymapGetBuffer, payload: payload, to: raw)
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
        var outbound = [UInt8](repeating: 0, count: reportLength)
        outbound[0] = command.rawValue
        for (index, byte) in payload.enumerated() where index + 1 < reportLength {
            outbound[index + 1] = byte
        }

        let setResult = outbound.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(0),
                buffer.baseAddress!,
                reportLength
            )
        }
        guard setResult == kIOReturnSuccess else {
            throw VialProbeError.message("HID送信失敗: \(setResult)")
        }

        var inbound = [UInt8](repeating: 0, count: reportLength)
        var length = reportLength
        let getResult = inbound.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeInput,
                CFIndex(0),
                buffer.baseAddress!,
                &length
            )
        }
        guard getResult == kIOReturnSuccess else {
            throw VialProbeError.message("HID受信失敗: \(getResult)")
        }

        if length <= 0 {
            throw VialProbeError.message("HID受信長が0です。")
        }
        return Array(inbound.prefix(length))
    }
}
