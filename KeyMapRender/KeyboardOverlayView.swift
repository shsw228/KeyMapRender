import SwiftUI

struct KeyboardOverlayView: View {
    let layout: KeyboardLayout
    let currentLayer: Int
    let totalLayers: Int

    private let unitSize: CGFloat = 54
    private let keyGap: CGFloat = 6
    private let spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(layout.name)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Text("Layer L\(currentLayer) / \(max(0, totalLayers - 1))")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
            }
            .padding(.bottom, 4)

            if layout.positionedKeys.isEmpty {
                legacyRowView
            } else {
                positionedView
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .padding(8)
    }

    private var positionedView: some View {
        let boardWidth = max(1, CGFloat(layout.positionedWidth) * unitSize)
        let boardHeight = max(1, CGFloat(layout.positionedHeight) * unitSize)
        return GeometryReader { geo in
            let maxWidth = max(1, geo.size.width - 32)
            let maxHeight = max(1, geo.size.height - 32)
            let scale = min(maxWidth / boardWidth, maxHeight / boardHeight, 1.0)
            ZStack(alignment: .topLeading) {
                ForEach(layout.positionedKeys) { key in
                    keyView(label: key.label)
                        .frame(
                            width: max(8, CGFloat(key.width) * unitSize - keyGap),
                            height: max(8, CGFloat(key.height) * unitSize - keyGap)
                        )
                        .position(
                            x: (CGFloat(key.x) * unitSize + (CGFloat(key.width) * unitSize) / 2),
                            y: (CGFloat(key.y) * unitSize + (CGFloat(key.height) * unitSize) / 2)
                        )
                }
            }
            .frame(width: boardWidth, height: boardHeight, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(minHeight: 240)
    }

    private var legacyRowView: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        if key.isSpacer {
                            Color.clear
                                .frame(width: unitSize * key.width, height: unitSize * key.height)
                        } else {
                            keyView(label: key.label)
                                .frame(width: unitSize * key.width, height: unitSize * key.height)
                        }
                    }
                }
            }
        }
    }

    private func keyView(label: String) -> some View {
        return RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .overlay(
                keyLabelContent(label: label)
                    .padding(4)
            )
    }

    @ViewBuilder
    private func keyLabelContent(label: String) -> some View {
        if let split = splitTapHoldLabel(label) {
            VStack(spacing: 2) {
                Text(normalizeDisplayLabel(split.tap))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 1)

                Text(normalizeDisplayLabel(split.hold))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
        } else {
            Text(normalizeDisplayLabel(label))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func normalizeDisplayLabel(_ label: String) -> String {
        if label == "TRNS" {
            return "▽"
        }
        if label.hasPrefix("TRNS\n") {
            return "▽" + label.dropFirst(4)
        }
        return label
    }

    private func splitTapHoldLabel(_ label: String) -> (tap: String, hold: String)? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")") else { return nil }

        if let range = trimmed.range(of: "_T(") {
            let hold = String(trimmed[..<range.lowerBound])
            let tapStart = range.upperBound
            let tapEnd = trimmed.index(before: trimmed.endIndex)
            let tap = String(trimmed[tapStart..<tapEnd])
            return (tap: tap, hold: hold)
        }

        if trimmed.hasPrefix("LT"), let open = trimmed.firstIndex(of: "(") {
            let hold = String(trimmed[..<open])
            let tapStart = trimmed.index(after: open)
            let tapEnd = trimmed.index(before: trimmed.endIndex)
            let tap = String(trimmed[tapStart..<tapEnd])
            return (tap: tap, hold: hold)
        }
        return nil
    }
}
