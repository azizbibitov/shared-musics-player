import SwiftUI
import UniformTypeIdentifiers

struct TracksListView: View {
    @Environment(TracksViewModel.self) private var viewModel
    @Environment(MultipeerSyncManager.self) private var syncManager
    @Environment(AudioPlayerManager.self) private var player
    @State private var showFilePicker = false
    @State private var showFolderPicker = false
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var searchText = ""

    var filteredTracks: [Track] {
        searchText.isEmpty ? viewModel.tracks : viewModel.tracks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var isEditing: Bool { editMode == .active }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.tracks.isEmpty {
                    FullScreenEmptyState(icon: "music.note", title: "No Tracks", message: "Tap + to add tracks from your files")
                } else {
                    List(selection: $selection) {
                        ForEach(filteredTracks) { track in
                            Button {
                                player.load(track, autoPlay: true)
                            } label: {
                                TrackRowView(track: track)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(TrackRowButtonStyle())
                            .tag(track.id)
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { filteredTracks[$0].id })
                            viewModel.deleteByIDs(ids)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search tracks")
                    .refreshable {
                        viewModel.refresh()
                        syncManager.syncWithConnectedPeers()
                    }
                }
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        HStack(spacing: 5) {
                            Text("Tracks").font(.headline)
                            Circle()
                                .fill(syncManager.connectedPeers.isEmpty ? Color.secondary.opacity(0.4) : Color.green)
                                .frame(width: 7, height: 7)
                            if viewModel.isImporting {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.secondary)
                            }
                        }
                        if viewModel.isImporting {
                            Text("Importing \(viewModel.importCompleted) of \(viewModel.importTotal)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            let total = viewModel.tracks.count
                            let shown = filteredTracks.count
                            Text(searchText.isEmpty ? "\(total) track\(total == 1 ? "" : "s")" : "\(shown) of \(total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        Button("Done") { editMode = .inactive; selection.removeAll() }
                    } else {
                        Button("Edit") { editMode = .active }
                            .disabled(viewModel.tracks.isEmpty)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Menu {
                            Button(role: .destructive) {
                                viewModel.deleteByIDs(selection)
                                selection.removeAll()
                                editMode = .inactive
                            } label: {
                                Label("Delete Selected (\(selection.count))", systemImage: "trash")
                            }
                            .disabled(selection.isEmpty)

                            Button(role: .destructive) {
                                viewModel.deleteAll()
                                selection.removeAll()
                                editMode = .inactive
                            } label: {
                                Label("Delete All", systemImage: "trash.fill")
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    } else {
                        Menu {
                            Button {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showFilePicker = true
                                }
                            } label: {
                                Label("Import Files", systemImage: "doc.badge.plus")
                            }
                            Button {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showFolderPicker = true
                                }
                            } label: {
                                Label("Import Folder", systemImage: "folder.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
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
    }
}

struct MiniPlayerView: View {
    @Environment(AudioPlayerManager.self) private var player
    let track: Track
    var onTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 16) {
            
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundColor(.accentColor)

                    Text(track.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    Spacer()
                }
                

            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .transaction { $0.animation = nil }
            }
            .buttonStyle(.plain)

            Button {
                player.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffectIfAvailable()
        .onTapGesture {
            onTap()
             
        }
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

struct TrackRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
                        .foregroundColor(.secondary)
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
