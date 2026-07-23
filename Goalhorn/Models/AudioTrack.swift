import Foundation

/// A goal song the user has imported into the app.
///
/// The audio bytes live in the app's Application Support directory; this struct
/// is the lightweight, `Codable` record we persist and show in the UI.
struct AudioTrack: Identifiable, Codable, Hashable {
    let id: UUID
    /// Display name shown in the library (defaults to the imported file name).
    var title: String
    /// File name on disk, relative to the audio library directory.
    let fileName: String
    /// When it was imported.
    let dateAdded: Date

    init(id: UUID = UUID(), title: String, fileName: String, dateAdded: Date = Date()) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.dateAdded = dateAdded
    }

    /// The MIME content type inferred from the file extension, used both by the
    /// local HTTP server (for Sonos) and for display.
    var contentType: String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "aiff", "aif": return "audio/aiff"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        default: return "application/octet-stream"
        }
    }
}
