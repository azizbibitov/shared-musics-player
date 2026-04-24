import SwiftUI
import AVFoundation
import Observation

struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let filename: String
    let duration: TimeInterval?
    let sourceFilename: String?

    var url: URL {
        Storage.baseURL.appendingPathComponent(filename)
    }

    init(id: UUID = UUID(), name: String, filename: String, duration: TimeInterval?, sourceFilename: String? = nil) {
        self.id = id
        self.name = name
        self.filename = filename
        self.duration = duration
        self.sourceFilename = sourceFilename
    }
}

@Observable
final class TracksViewModel {
    var tracks: [Track] = []
    private(set) var tombstoneIDs: Set<UUID> = []
    private(set) var importingCount: Int = 0
    private(set) var importTotal: Int = 0
    private(set) var importCompleted: Int = 0

    var isImporting: Bool { importingCount > 0 }

    private let documentsURL = Storage.baseURL
    private var metadataURL: URL { Storage.baseURL.appendingPathComponent("tracks.json") }
    private var tombstonesURL: URL { Storage.baseURL.appendingPathComponent("tombstones.json") }

    init() {
        loadTombstones()
        loadFromStorage()
        syncDocumentsFolder()
    }

    func importTrack(from sourceURL: URL) {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let filename = UUID().uuidString + ".mp3"
        let destURL = documentsURL.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("Copy failed: \(error)")
            return
        }

        importingCount += 1
        importTotal += 1
        Task {
            let asset = AVURLAsset(url: destURL)
            async let duration = loadDuration(asset)
            async let title = loadTitle(asset, fallback: sourceURL.deletingPathExtension().lastPathComponent)

            let resolvedDuration = await duration
            let resolvedTitle = await title

            await MainActor.run {
                if let dur = resolvedDuration {
                    let track = Track(name: resolvedTitle, filename: filename, duration: dur, sourceFilename: sourceURL.lastPathComponent)
                    self.tracks.append(track)
                    self.saveToStorage()
                } else {
                    try? FileManager.default.removeItem(at: destURL)
                }
                self.importCompleted += 1
                self.importingCount -= 1
                if self.importingCount == 0 { self.importTotal = 0; self.importCompleted = 0 }
            }
        }
    }

    func importFolder(from folderURL: URL) {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: nil)
        var mp3s: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension.lowercased() == "mp3" { mp3s.append(url) }
        }

        let knownSources = Set(tracks.compactMap { $0.sourceFilename })
        let newMp3s = mp3s.filter { !knownSources.contains($0.lastPathComponent) }

        guard !newMp3s.isEmpty else { return }
        importTotal += newMp3s.count
        importingCount += newMp3s.count

        for url in newMp3s {
            let filename = UUID().uuidString + ".mp3"
            let destURL = documentsURL.appendingPathComponent(filename)
            do {
                try FileManager.default.copyItem(at: url, to: destURL)
            } catch {
                importingCount -= 1
                importCompleted += 1
                if importingCount == 0 { importTotal = 0; importCompleted = 0 }
                continue
            }
            Task {
                let asset = AVURLAsset(url: destURL)
                async let duration = loadDuration(asset)
                async let title = loadTitle(asset, fallback: url.deletingPathExtension().lastPathComponent)
                let resolvedDuration = await duration
                let resolvedTitle = await title
                await MainActor.run {
                    if let dur = resolvedDuration {
                        let track = Track(name: resolvedTitle, filename: filename, duration: dur, sourceFilename: url.lastPathComponent)
                        self.tracks.append(track)
                        self.saveToStorage()
                    } else {
                        try? FileManager.default.removeItem(at: destURL)
                    }
                    self.importCompleted += 1
                    self.importingCount -= 1
                    if self.importingCount == 0 { self.importTotal = 0; self.importCompleted = 0 }
                }
            }
        }
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let track = tracks[index]
            try? FileManager.default.removeItem(at: track.url)
        }
        tracks.remove(atOffsets: offsets)
        saveToStorage()
    }

    func deleteByIDs(_ ids: Set<UUID>) {
        let toDelete = tracks.filter { ids.contains($0.id) }
        toDelete.forEach { try? FileManager.default.removeItem(at: $0.url) }
        tracks.removeAll { ids.contains($0.id) }
        tombstoneIDs.formUnion(ids)
        saveToStorage()
        saveTombstones()
    }

    func deleteAll() {
        tombstoneIDs.formUnion(tracks.map { $0.id })
        tracks.forEach { try? FileManager.default.removeItem(at: $0.url) }
        tracks.removeAll()
        saveToStorage()
        saveTombstones()
    }

    func addSyncedTrack(_ track: Track) {
        guard !tracks.contains(where: { $0.id == track.id }) else { return }
        guard !tombstoneIDs.contains(track.id) else { return }
        tracks.append(track)
        saveToStorage()
    }

    func applyTombstones(_ ids: Set<UUID>) {
        let toDelete = tracks.filter { ids.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        toDelete.forEach { try? FileManager.default.removeItem(at: $0.url) }
        tracks.removeAll { ids.contains($0.id) }
        tombstoneIDs.formUnion(ids)
        saveToStorage()
        saveTombstones()
    }

    func refresh() {
        loadFromStorage()
        syncDocumentsFolder()
    }

    private func syncDocumentsFolder() {
        let known = Set(tracks.map { $0.filename })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path)) ?? []
        let newFiles = files.filter { $0.lowercased().hasSuffix(".mp3") && !known.contains($0) }
        guard !newFiles.isEmpty else { return }

        Task {
            var newTracks: [Track] = []
            for filename in newFiles {
                let url = documentsURL.appendingPathComponent(filename)
                let asset = AVURLAsset(url: url)
                async let duration = loadDuration(asset)
                async let title = loadTitle(asset, fallback: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent)
                newTracks.append(Track(name: await title, filename: filename, duration: await duration))
            }
            let captured = newTracks
            await MainActor.run {
                self.tracks.append(contentsOf: captured)
                self.saveToStorage()
            }
        }
    }

    private func loadDuration(_ asset: AVURLAsset) async -> TimeInterval? {
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : nil
    }

    private func loadTitle(_ asset: AVURLAsset, fallback: String) async -> String {
        guard let formats = try? await asset.load(.availableMetadataFormats) else { return fallback }
        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }
            for item in items where item.identifier == .id3MetadataTitleDescription {
                if let title = try? await item.load(.stringValue), !title.isEmpty {
                    return title
                }
            }
        }
        return fallback
    }

    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func loadFromStorage() {
        guard let data = try? Data(contentsOf: metadataURL),
              let saved = try? JSONDecoder().decode([Track].self, from: data) else { return }
        tracks = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if tracks.count != saved.count { saveToStorage() }
    }

    private func saveTombstones() {
        guard let data = try? JSONEncoder().encode(Array(tombstoneIDs)) else { return }
        try? data.write(to: tombstonesURL, options: .atomic)
    }

    private func loadTombstones() {
        guard let data = try? Data(contentsOf: tombstonesURL),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        tombstoneIDs = Set(ids)
    }
}
