import SwiftUI

@main
struct MusicPlayerApp: App {
    @State private var player = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Playlists", systemImage: "music.note.list") {
                    PlaylistsView()
                }
                Tab("Tracks", systemImage: "music.note") {
                    TracksListView()
                }
            }
            .environment(player)
        }
    }
}
