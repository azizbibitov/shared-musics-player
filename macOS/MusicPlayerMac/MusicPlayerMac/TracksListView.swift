import SwiftUI
import UniformTypeIdentifiers
import MultipeerConnectivity

struct TracksListView: View {
    @Environment(TracksViewModel.self) private var viewModel
    @Environment(MultipeerSyncManager.self) private var syncManager
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
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.refresh()
                    syncManager.syncWithConnectedPeers()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Reload library and sync with nearby devices")
                .disabled(viewModel.isImporting)
            }

            ToolbarItem(placement: .navigation) {
                let connected = !syncManager.connectedPeers.isEmpty
                let names = syncManager.connectedPeers.map { $0.displayName }.joined(separator: ", ")
                Label(
                    connected ? "Connected to \(names)" : "No nearby devices",
                    systemImage: connected ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right"
                )
                .foregroundStyle(connected ? Color.green : Color.secondary.opacity(0.5))
                .help(connected ? "Connected to \(names)" : "Looking for nearby devices...")
            }

            ToolbarItem(placement: .destructiveAction) {
                Menu {
                    if !selectedIDs.isEmpty {
                        Button(role: .destructive) {
                            viewModel.deleteByIDs(selectedIDs)
                            selectedIDs.removeAll()
                        } label: {
                            Label("Delete Selected (\(selectedIDs.count))", systemImage: "trash")
                        }
                    }
                    Button(role: .destructive) {
                        viewModel.deleteAll()
                        selectedIDs.removeAll()
                    } label: {
                        Label("Delete All", systemImage: "trash.fill")
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.tracks.isEmpty)
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
        .onAppear {
            syncManager.syncWithConnectedPeers()
        }
        .onChange(of: viewModel.tracks.count) {
            syncManager.syncWithConnectedPeers()
        }
        .safeAreaInset(edge: .bottom) {
            if !syncManager.activeTransfers.isEmpty {
                TransferProgressBanner(transfers: syncManager.activeTransfers)
            }
        }
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

struct TransferProgressBanner: View {
    let transfers: [FileTransfer]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                ForEach(transfers) { transfer in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(transfer.trackName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(transfer.fraction * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: transfer.fraction)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
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
