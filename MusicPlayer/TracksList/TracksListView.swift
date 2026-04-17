import SwiftUI
import UniformTypeIdentifiers

struct TracksListView: View {
    @State private var viewModel = TracksViewModel()
    @Environment(AudioPlayerManager.self) private var player
    enum PickerMode { case files, folder }
    @State private var pickerMode: PickerMode? = nil
    @State private var showFullPlayer = false
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var navPath: [Track] = []

    var isEditing: Bool { editMode == .active }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if viewModel.tracks.isEmpty {
                    FullScreenEmptyState(icon: "music.note", title: "No Tracks", message: "Tap + to add tracks from your files")
                } else {
                    List(selection: $selection) {
                        ForEach(viewModel.tracks) { track in
                            NavigationLink(value: track) {
                                TrackRowView(track: track)
                            }
                            .tag(track.id)
                        }
                        .onDelete(perform: viewModel.delete)
                    }
                }
            }
            .navigationTitle("Tracks")
            .navigationDestination(for: Track.self) { track in
                PlayerView(track: track)
            }
            .environment(\.editMode, $editMode)
            .toolbar {
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
                                pickerMode = .files
                            } label: {
                                Label("Import Files", systemImage: "doc.badge.plus")
                            }
                            Button {
                                pickerMode = .folder
                            } label: {
                                Label("Import Folder", systemImage: "folder.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let track = player.currentTrack, navPath.isEmpty {
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
            .fileImporter(
                isPresented: Binding(get: { pickerMode != nil }, set: { if !$0 { pickerMode = nil } }),
                allowedContentTypes: pickerMode == .folder ? [.folder] : [.mp3],
                allowsMultipleSelection: pickerMode == .files
            ) { result in
                guard case .success(let urls) = result else { return }
                if pickerMode == .folder {
                    urls.first.map { viewModel.importFolder(from: $0) }
                } else {
                    urls.forEach { viewModel.importTrack(from: $0) }
                }
                pickerMode = nil
            }
        }
    }
}

struct MiniPlayerView: View {
    @Environment(AudioPlayerManager.self) private var player
    let track: Track

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * CGFloat(player.duration > 0 ? player.currentTime / player.duration : 0))
            }
            .frame(height: 2)

            HStack(spacing: 16) {
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundColor(.accentColor)

                Text(track.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

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
        }
        .background(.regularMaterial)
    }
}

struct TrackRowView: View {
    let track: Track

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.headline)
                if let formatted = formatDuration(track.duration) {
                    Text(formatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
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
