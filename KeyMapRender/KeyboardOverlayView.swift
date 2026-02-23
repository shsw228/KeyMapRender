import SwiftUI

struct KeyboardOverlayView: View {
    let layout: KeyboardLayout

    private let unitSize: CGFloat = 54
    private let keyGap: CGFloat = 6
    private let spacing: CGFloat = 8

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: spacing) {
                Text(layout.name)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 4)

                if layout.positionedKeys.isEmpty {
                    legacyRowView
                } else {
                    positionedView
                }
            }
            .padding(26)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .padding(24)
        }
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
        let resolvedLabel = resolveDisplayLabel(label)
        return RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .overlay(
                Text(resolvedLabel)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(4)
            )
    }

    private func resolveDisplayLabel(_ raw: String) -> String {
        guard let code = parseNumericKeycode(raw) else { return raw }
        return KeycodeLabelFormatter.label(for: code)
    }

    private func parseNumericKeycode(_ raw: String) -> UInt16? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return UInt16(text.dropFirst(2), radix: 16)
        }

        let separators = CharacterSet.decimalDigits.inverted
        let token = text.components(separatedBy: separators).first(where: { !$0.isEmpty }) ?? ""
        guard let decimal = Int(token), decimal >= 0, decimal <= Int(UInt16.max) else {
            return nil
        }
        return UInt16(decimal)
    }
}
