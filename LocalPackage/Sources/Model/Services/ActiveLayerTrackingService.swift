import DataSource

public struct ActiveLayerTrackingService {
    public init() {}

    public func deriveTrackedLayer(from pressed: [[Bool]], dump: VialKeymapDump, baseLayer: Int) -> Int {
        guard !dump.keycodes.isEmpty else { return 0 }
        let maxLayer = max(0, min(dump.layerCount - 1, dump.keycodes.count - 1))
        var effective = max(0, min(baseLayer, maxLayer))

        // Resolve nested MO/LT/LM holds with a few fixed-point iterations.
        for _ in 0..<4 {
            var next = max(0, min(baseLayer, maxLayer))
            var hasFnMo13 = false
            var hasFnMo23 = false
            for row in 0..<min(pressed.count, dump.matrixRows) {
                for col in 0..<min(pressed[row].count, dump.matrixCols) where pressed[row][col] {
                    let activeKeycode = resolvedKeycodeAt(layer: effective, row: row, col: col, keycodes: dump.keycodes)
                    if isFnMo13(activeKeycode) {
                        hasFnMo13 = true
                        continue
                    }
                    if isFnMo23(activeKeycode) {
                        hasFnMo23 = true
                        continue
                    }
                    if let target = layerHoldTarget(for: activeKeycode) {
                        next = max(next, min(target, maxLayer))
                    }
                }
            }
            if hasFnMo13 && hasFnMo23 {
                next = max(next, min(3, maxLayer))
            } else if hasFnMo13 {
                next = max(next, min(1, maxLayer))
            } else if hasFnMo23 {
                next = max(next, min(2, maxLayer))
            }
            if next == effective { break }
            effective = next
        }
        return effective
    }

    private func resolvedKeycodeAt(layer: Int, row: Int, col: Int, keycodes: [[[UInt16]]]) -> UInt16 {
        let safeLayer = max(0, min(layer, keycodes.count - 1))
        for current in stride(from: safeLayer, through: 0, by: -1) {
            guard row >= 0, row < keycodes[current].count else { continue }
            guard col >= 0, col < keycodes[current][row].count else { continue }
            let code = keycodes[current][row][col]
            if code != 0x0001 {
                return code
            }
        }
        return 0x0001
    }

    private func layerHoldTarget(for keycode: UInt16) -> Int? {
        // LT(layer, kc)
        if keycode >= 0x4000, keycode <= 0x4FFF {
            return Int((keycode >> 8) & 0x0F)
        }

        // QMK v5/v6 MO(layer) families.
        if keycode >= 0x5100, keycode <= 0x51FF {
            return Int(keycode & 0x00FF) // v5 MO
        }
        if keycode >= 0x5220, keycode <= 0x523F {
            return Int(keycode & 0x001F) // v6 MO
        }

        // LM(layer, mod): layer-while-hold
        if keycode >= 0x5900, keycode <= 0x59FF {
            return Int((keycode >> 4) & 0x0F) // v5 LM
        }
        if keycode >= 0x5000, keycode <= 0x51FF {
            return Int((keycode >> 5) & 0x1F) // v6 LM
        }
        return nil
    }

    private func isFnMo13(_ keycode: UInt16) -> Bool {
        keycode == 0x5F10 || keycode == 0x7C77
    }

    private func isFnMo23(_ keycode: UInt16) -> Bool {
        keycode == 0x5F11 || keycode == 0x7C78
    }
}
