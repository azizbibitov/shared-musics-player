import SwiftUI

struct PlaylistsView: View {
    var body: some View {
        NavigationStack {
            FullScreenEmptyState(icon: "music.note.list", title: "No Playlists", message: "Playlists coming soon")
                .navigationTitle("Playlists")
        }
    }
}
