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
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
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
    private(set) var importingCount: Int = 0
    private(set) var importTotal: Int = 0
    private(set) var importCompleted: Int = 0

    var isImporting: Bool { importingCount > 0 }

    private let storageKey = "saved_tracks"
    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
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

            let track = Track(name: await title, filename: filename, duration: await duration, sourceFilename: sourceURL.lastPathComponent)

            await MainActor.run {
                self.tracks.append(track)
                self.saveToStorage()
                self.importCompleted += 1
                self.importingCount -= 1
                if self.importingCount == 0 { self.importTotal = 0; self.importCompleted = 0 }
            }
        }
    }

    func importFolder(from folderURL: URL) {
        print("[importFolder] folderURL=\(folderURL)")
        print("[importFolder] isDirectory=\(folderURL.hasDirectoryPath)")
        let accessed = folderURL.startAccessingSecurityScopedResource()
        print("[importFolder] startAccessingSecurityScopedResource=\(accessed)")
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: nil)
        print("[importFolder] enumerator=\(String(describing: enumerator))")
        var mp3s: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            print("[importFolder] found item: \(url.lastPathComponent) ext=\(url.pathExtension)")
            if url.pathExtension.lowercased() == "mp3" { mp3s.append(url) }
        }
        print("[importFolder] total mp3s found: \(mp3s.count)")
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
                print("Copy failed: \(error)")
                importingCount -= 1
                importCompleted += 1
                if importingCount == 0 { importTotal = 0; importCompleted = 0 }
                continue
            }
            Task {
                let asset = AVURLAsset(url: destURL)
                async let duration = loadDuration(asset)
                async let title = loadTitle(asset, fallback: url.deletingPathExtension().lastPathComponent)
                let track = Track(name: await title, filename: filename, duration: await duration, sourceFilename: url.lastPathComponent)
                await MainActor.run {
                    self.tracks.append(track)
                    self.saveToStorage()
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
        saveToStorage()
    }

    func deleteAll() {
        tracks.forEach { try? FileManager.default.removeItem(at: $0.url) }
        tracks.removeAll()
        saveToStorage()
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
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Track].self, from: data) else { return }
        tracks = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if tracks.count != saved.count { saveToStorage() }
    }
}
