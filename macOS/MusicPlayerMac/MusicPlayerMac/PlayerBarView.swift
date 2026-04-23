import SwiftUI

struct PlayerBarView: View {
    @Environment(AudioPlayerManager.self) private var player
    @State private var isDragging = false
    @State private var dragValue: TimeInterval = 0

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                trackInfo
                    .frame(minWidth: 140, maxWidth: 220, alignment: .leading)

                Spacer()

                controls

                Spacer()

                dismissButton
                    .frame(minWidth: 140, maxWidth: 220, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var trackInfo: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if let track = player.currentTrack {
                Text(track.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .transaction { $0.animation = nil }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Text(formatTime(isDragging ? dragValue : player.currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { isDragging ? dragValue : player.currentTime },
                        set: { dragValue = $0 }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        isDragging = editing
                        if !editing { player.seek(to: dragValue) }
                    }
                )
                .frame(maxWidth: 380)

                Text(formatTime(player.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .leading)
            }
        }
    }

    private var dismissButton: some View {
        HStack {
            Spacer()
            Button {
                player.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
