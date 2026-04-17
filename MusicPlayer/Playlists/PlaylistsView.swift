import SwiftUI

struct PlaylistsView: View {
    @Environment(AudioPlayerManager.self) private var player
    @State private var showFullPlayer = false

    var body: some View {
        NavigationStack {
            FullScreenEmptyState(icon: "music.note.list", title: "No Playlists", message: "Playlists coming soon")
            .navigationTitle("Playlists")
            .safeAreaInset(edge: .bottom) {
                if let track = player.currentTrack {
                    MiniPlayerView(track: track)
                        .onTapGesture { showFullPlayer = true }
                }
            }
            .sheet(isPresented: $showFullPlayer) {
                if let track = player.currentTrack {
                    PlayerView(track: track)
                        .environment(player)
                }
            }
        }
    }
}
