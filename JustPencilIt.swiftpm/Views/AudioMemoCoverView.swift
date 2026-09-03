import SwiftUI

/// Um memo de áudio desenhado como fita cassete — mesmo estilo mangá das
/// capas de caderno (contorno grosso, sombra dura, meio-tom), só que na
/// forma de uma fita: corpo retangular baixo e largo, dois carretéis, e uma
/// etiqueta com o nome.
struct AudioMemoCoverView: View {
    let memo: AudioMemo

    private var isProtected: Bool { memo.isProtected }

    private var statusIcon: (name: String, color: Color)? {
        switch memo.transcriptionStatus {
        case .pending, .transcribing: return ("waveform", .white.opacity(0.85))
        case .done: return ("text.alignleft", .white)
        case .failed: return ("exclamationmark.triangle.fill", .yellow)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black)
                .offset(x: 5, y: 5)

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(memo.coverColor.color.gradient)
                    .overlay(
                        HStack(spacing: 18) {
                            ReelView()
                            ReelView()
                        }
                        .padding(.horizontal, 22)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black, lineWidth: 3)
                    )
                    .frame(height: 72)

                VStack(alignment: .leading, spacing: 2) {
                    Text(memo.title)
                        .font(.custom(NotebookCoverView.titleFontName, size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(formattedDuration)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(
                    UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black, lineWidth: 3))

            if let statusIcon {
                Image(systemName: statusIcon.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusIcon.color)
                    .padding(6)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .padding(6)
            }

            if isProtected {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .padding(6)
                    .padding(.top, 30)
            }
        }
        .padding(6)
    }

    private var formattedDuration: String {
        let total = Int(memo.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ReelView: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.8))
            Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5).padding(6)
        }
        .frame(width: 34, height: 34)
    }
}
