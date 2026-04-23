import SwiftUI
import UniformTypeIdentifiers

struct TracksListView: View {
    @State private var viewModel = TracksViewModel()
    @Environment(AudioPlayerManager.self) private var player
    @State private var showFilePicker = false
    @State private var showFolderPicker = false
    @State private var selectedIDs = Set<UUID>()
    @State private var searchText = ""

    var filteredTracks: [Track] {
        searchText.isEmpty ? viewModel.tracks : viewModel.tracks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if viewModel.tracks.isEmpty {
                FullScreenEmptyState(
                    icon: "music.note",
                    title: "No Tracks",
                    message: "Click + to import tracks from your files"
                )
            } else {
                List(filteredTracks, selection: $selectedIDs) { track in
                    TrackRowView(track: track)
                        .tag(track.id)
                        .onTapGesture(count: 2) {
                            player.load(track, autoPlay: true)
                        }
                        .contextMenu {
                            Button {
                                player.load(track, autoPlay: true)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            Divider()
                            Button(role: .destructive) {
                                viewModel.deleteByIDs([track.id])
                                selectedIDs.remove(track.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDeleteCommand {
                    guard !selectedIDs.isEmpty else { return }
                    viewModel.deleteByIDs(selectedIDs)
                    selectedIDs.removeAll()
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search tracks")
        .navigationTitle("Tracks")
        .navigationSubtitle(subtitleText)
        .toolbar {
            if !selectedIDs.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        viewModel.deleteByIDs(selectedIDs)
                        selectedIDs.removeAll()
                    } label: {
                        Label("Delete Selected (\(selectedIDs.count))", systemImage: "trash")
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showFilePicker = true }
                    } label: {
                        Label("Import Files", systemImage: "doc.badge.plus")
                    }
                    Button {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showFolderPicker = true }
                    } label: {
                        Label("Import Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.mp3],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            urls.forEach { viewModel.importTrack(from: $0) }
        }
        .background(
            EmptyView().fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let folderURL = urls.first else { return }
                viewModel.importFolder(from: folderURL)
            }
        )
    }

    private var subtitleText: String {
        if viewModel.isImporting {
            return "Importing \(viewModel.importCompleted) of \(viewModel.importTotal)..."
        }
        let total = viewModel.tracks.count
        let shown = filteredTracks.count
        return searchText.isEmpty
            ? "\(total) track\(total == 1 ? "" : "s")"
            : "\(shown) of \(total)"
    }
}

struct TrackRowView: View {
    let track: Track
    @Environment(AudioPlayerManager.self) private var player

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.headline)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                if let formatted = formatDuration(track.duration) {
                    Text(formatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isCurrent {
                Image(systemName: "waveform")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: player.isPlaying)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval?) -> String? {
        guard let d = duration, d.isFinite else { return nil }
        let m = Int(d) / 60
        let s = Int(d) % 60
        return String(format: "%d:%02d", m, s)
    }
}
