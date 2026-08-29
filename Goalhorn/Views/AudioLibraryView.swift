import SwiftUI
import UniformTypeIdentifiers

/// Import, pick, and manage goal songs.
struct AudioLibraryView: View {
    @EnvironmentObject private var audioLibrary: AudioLibrary
    @EnvironmentObject private var settings: AppSettings

    @State private var showingImporter = false
    @State private var importError: String?
    @State private var renaming: AudioTrack?
    @State private var newName: String = ""

    private var songLengthSection: some View {
        Section {
            Picker("Length", selection: $settings.songPlayback) {
                ForEach(SongPlaybackMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            if settings.songPlayback == .fixed {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Stop after")
                        Spacer()
                        Text("\(Int(settings.songDuration))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.songDuration, in: 5...120, step: 1)
                }
            }
        } header: {
            Text("Song Length")
        } footer: {
            Text(songLengthFooter)
        }
    }

    private var songLengthFooter: String {
        switch settings.songPlayback {
        case .full:
            return "The song plays to its end. The light show still stops after \(Int(settings.celebrationDuration))s."
        case .matchLights:
            return "The song fades out with the light show, after \(Int(settings.celebrationDuration))s."
        case .fixed:
            return "The song fades out after \(Int(settings.songDuration))s, whatever the light show is doing."
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Upload a Goal Song", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Import MP3, M4A, WAV, or AIFF files. The selected song plays when you trigger the horn.")
                }

                songLengthSection

                if audioLibrary.tracks.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Songs Yet",
                            systemImage: "music.note",
                            description: Text("Upload your goal song to get started.")
                        )
                    }
                } else {
                    Section("Your Songs") {
                        ForEach(audioLibrary.tracks) { track in
                            trackRow(track)
                        }
                        .onDelete(perform: deleteTracks)
                    }
                }
            }
            .navigationTitle("Goal Songs")
            .toolbar {
                if !audioLibrary.tracks.isEmpty {
                    EditButton()
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .aiff],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .alert("Rename Song", isPresented: renamingBinding) {
                TextField("Title", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let track = renaming { audioLibrary.rename(track, to: newName) }
                    renaming = nil
                }
            }
            .alert("Import Failed", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func trackRow(_ track: AudioTrack) -> some View {
        let isSelected = effectiveSelectedID == track.id
        return Button {
            settings.selectedTrackID = track.id
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .red : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).foregroundStyle(.primary)
                    Text(track.dateAdded, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                newName = track.title
                renaming = track
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    /// The song that will actually play — the explicit pick, or the first song.
    private var effectiveSelectedID: UUID? {
        settings.selectedTrackID ?? audioLibrary.tracks.first?.id
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var firstImported: AudioTrack?
            for url in urls {
                do {
                    let track = try audioLibrary.importAudio(from: url)
                    if firstImported == nil { firstImported = track }
                } catch {
                    importError = error.localizedDescription
                }
            }
            // Auto-select the first import if nothing is selected yet.
            if settings.selectedTrackID == nil, let track = firstImported {
                settings.selectedTrackID = track.id
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func deleteTracks(at offsets: IndexSet) {
        let removedIDs = offsets.map { audioLibrary.tracks[$0].id }
        audioLibrary.delete(at: offsets)
        if let selected = settings.selectedTrackID, removedIDs.contains(selected) {
            settings.selectedTrackID = audioLibrary.tracks.first?.id
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }
}
