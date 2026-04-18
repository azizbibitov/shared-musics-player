import SwiftUI

@main
struct MusicPlayerApp: App {
    @State private var player = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
        }
    }
}

struct RootView: View {
    @Environment(AudioPlayerManager.self) private var player
    @State private var showFullPlayer = false
    @State private var tabBarAreaHeight: CGFloat = 83

    var body: some View {
        TabView {
            Tab("Playlists", systemImage: "music.note.list") {
                PlaylistsView()
            }
            Tab("Tracks", systemImage: "music.note") {
                TracksListView()
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.onAppear {
                    tabBarAreaHeight = geo.safeAreaInsets.bottom + 49
                }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if let track = player.currentTrack, !player.isPlayerViewOpen {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer {
                        MiniPlayerView(track: track, onTap: { showFullPlayer = true })
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, tabBarAreaHeight + 8)
                } else {
                    MiniPlayerView(track: track, onTap: { showFullPlayer = true })
                        .padding(.horizontal, 12)
                        .padding(.bottom, tabBarAreaHeight + 8)
                }
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
