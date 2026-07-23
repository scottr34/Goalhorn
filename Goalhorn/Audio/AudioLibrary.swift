import Foundation
import Combine

/// Stores the goal songs the user imports.
///
/// Audio files are copied into Application Support (so they survive relaunch and
/// aren't purged like the caches directory), and a small JSON index records the
/// `AudioTrack` metadata.
@MainActor
final class AudioLibrary: ObservableObject {
    @Published private(set) var tracks: [AudioTrack] = []

    private let fileManager = FileManager.default

    /// Directory that holds the copied audio files.
    private lazy var audioDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GoalhornAudio", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// JSON index of tracks.
    private lazy var indexURL: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("goalhorn-tracks.json")
    }()

    init() {
        load()
    }

    /// Absolute file URL for a track's audio on disk.
    func fileURL(for track: AudioTrack) -> URL {
        audioDirectory.appendingPathComponent(track.fileName)
    }

    func track(withID id: UUID?) -> AudioTrack? {
        guard let id else { return nil }
        return tracks.first { $0.id == id }
    }

    /// Import an audio file chosen from the document picker.
    ///
    /// `sourceURL` may be a security-scoped URL, so we bracket the copy with
    /// `startAccessingSecurityScopedResource()`.
    @discardableResult
    func importAudio(from sourceURL: URL) throws -> AudioTrack {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let destination = audioDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)

        let title = sourceURL.deletingPathExtension().lastPathComponent
        let track = AudioTrack(id: id, title: title.isEmpty ? "Goal Song" : title, fileName: fileName)
        tracks.append(track)
        save()
        return track
    }

    func rename(_ track: AudioTrack, to newTitle: String) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        tracks[index].title = trimmed.isEmpty ? tracks[index].title : trimmed
        save()
    }

    func delete(_ track: AudioTrack) {
        try? fileManager.removeItem(at: fileURL(for: track))
        tracks.removeAll { $0.id == track.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            try? fileManager.removeItem(at: fileURL(for: tracks[index]))
        }
        tracks.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        if let decoded = try? JSONDecoder().decode([AudioTrack].self, from: data) {
            // Drop any records whose file is missing (e.g. restored from backup).
            tracks = decoded.filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
