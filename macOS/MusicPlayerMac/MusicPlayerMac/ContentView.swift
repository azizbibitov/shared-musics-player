import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case playlists = "Playlists"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .tracks: return "music.note"
        case .playlists: return "music.note.list"
        }
    }
}

struct RootView: View {
    @Environment(AudioPlayerManager.self) private var player
    @State private var selectedItem: SidebarItem? = .tracks

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(SidebarItem.allCases, selection: $selectedItem) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .navigationTitle("Music")
            } detail: {
                switch selectedItem {
                case .tracks, nil:
                    TracksListView()
                case .playlists:
                    PlaylistsView()
                }
            }

            if player.currentTrack != nil {
                PlayerBarView()
            }
        }
        .alert("Playback Error", isPresented: Binding(
            get: { player.loadError != nil },
            set: { if !$0 { player.loadError = nil } }
        )) {
            Button("OK", role: .cancel) { player.loadError = nil }
        } message: {
            Text(player.loadError ?? "")
        }
    }
}
