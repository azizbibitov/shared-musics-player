import SwiftUI

struct PlayerView: View {
    @Environment(AudioPlayerManager.self) private var player
    let track: Track
    @State private var isDragging = false
    @State private var dragValue: TimeInterval = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundColor(.accentColor)
                .padding(32)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 24))

            Text(track.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal)

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { isDragging ? dragValue : player.currentTime },
                        set: { dragValue = $0 }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        isDragging = editing
                        if !editing {
                            player.seek(to: dragValue)
                        }
                    }
                )

                HStack {
                    Text(formatTime(isDragging ? dragValue : player.currentTime))
                    Spacer()
                    Text(formatTime(player.duration))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .foregroundColor(.primary)
                    .transaction { $0.animation = nil }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            player.isPlayerViewOpen = true
            if player.currentTrack?.id != track.id {
                player.load(track, autoPlay: true)
            }
        }
        .onDisappear {
            player.isPlayerViewOpen = false
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
