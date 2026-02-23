import SwiftUI

struct KeyboardOverlayView: View {
    let layout: KeyboardLayout

    private let unitWidth: CGFloat = 56
    private let keyHeight: CGFloat = 52
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

                ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: spacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                            if key.isSpacer {
                                Color.clear
                                    .frame(width: unitWidth * key.width, height: keyHeight * key.height)
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                                    )
                                    .overlay(
                                        Text(key.label)
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.92))
                                    )
                                    .frame(width: unitWidth * key.width, height: keyHeight * key.height)
                            }
                        }
                    }
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
}

