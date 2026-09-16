import AVFoundation
import Foundation
import Observation

/// Archivio locale: metadati in JSON, file video su disco.
/// Niente cloud, niente rete: tutto resta dentro la sandbox dell'app.
@Observable
final class LibraryStore {

    private(set) var projects: [Project] = []
    var loadError: String?

    // MARK: Percorsi

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var mediaDirectory: URL { documents.appendingPathComponent("Media", isDirectory: true) }
    static var thumbsDirectory: URL { documents.appendingPathComponent("Thumbs", isDirectory: true) }
    static var libraryFile: URL { documents.appendingPathComponent("library.json") }

    func url(for clip: Clip) -> URL {
        Self.mediaDirectory.appendingPathComponent(clip.fileName)
    }

    /// Nuovo URL di destinazione per una registrazione.
    func newRecordingURL(extension ext: String = "mov") -> URL {
        let name = "\(Formatters.fileStamp.string(from: Date()))_\(UUID().uuidString.prefix(6)).\(ext)"
        return Self.mediaDirectory.appendingPathComponent(name)
    }

    // MARK: Ciclo di vita

    init() {
        createDirectories()
        load()
    }

    private func createDirectories() {
        for dir in [Self.mediaDirectory, Self.thumbsDirectory] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.libraryFile.path) else { return }
        do {
            let data = try Data(contentsOf: Self.libraryFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            projects = try decoder.decode([Project].self, from: data)
        } catch {
            loadError = "Impossibile leggere l'archivio: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(projects)
            try data.write(to: Self.libraryFile, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            loadError = "Impossibile salvare l'archivio: \(error.localizedDescription)"
        }
    }

    // MARK: Accesso

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    func sketch(_ target: RecordingTarget) -> Sketch? {
        project(target.projectID)?.sketches.first { $0.id == target.sketchID }
    }

    private func indexes(for target: RecordingTarget) -> (Int, Int)? {
        guard let p = projects.firstIndex(where: { $0.id == target.projectID }),
              let s = projects[p].sketches.firstIndex(where: { $0.id == target.sketchID })
        else { return nil }
        return (p, s)
    }

    // MARK: Progetti

    @discardableResult
    func addProject(name: String, notes: String = "") -> Project {
        let project = Project(name: name.isEmpty ? "Nuovo progetto" : name,
                              notes: notes,
                              colorIndex: projects.count % ProjectPalette.colors.count)
        projects.insert(project, at: 0)
        save()
        return project
    }

    func updateProject(_ id: UUID, name: String? = nil, notes: String? = nil,
                       colorIndex: Int? = nil, isArchived: Bool? = nil) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        if let name { projects[i].name = name }
        if let notes { projects[i].notes = notes }
        if let colorIndex { projects[i].colorIndex = colorIndex }
        if let isArchived { projects[i].isArchived = isArchived }
        save()
    }

    /// Elimina il progetto e tutti i file video contenuti.
    func deleteProject(_ id: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        for sketch in projects[i].sketches {
            for clip in sketch.clips { removeFiles(for: clip) }
        }
        projects.remove(at: i)
        save()
    }

    // MARK: Sketch

    @discardableResult
    func addSketch(to projectID: UUID, title: String) -> Sketch? {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let sketch = Sketch(title: title.isEmpty ? "Nuovo sketch" : title)
        projects[i].sketches.insert(sketch, at: 0)
        save()
        return sketch
    }

    func updateSketch(_ target: RecordingTarget, title: String? = nil, notes: String? = nil,
                      script: String? = nil, isDone: Bool? = nil) {
        guard let (p, s) = indexes(for: target) else { return }
        if let title { projects[p].sketches[s].title = title }
        if let notes { projects[p].sketches[s].notes = notes }
        if let script { projects[p].sketches[s].script = script }
        if let isDone { projects[p].sketches[s].isDone = isDone }
        save()
    }

    func deleteSketch(_ target: RecordingTarget) {
        guard let (p, s) = indexes(for: target) else { return }
        for clip in projects[p].sketches[s].clips { removeFiles(for: clip) }
        projects[p].sketches.remove(at: s)
        save()
    }

    func moveSketches(in projectID: UUID, from offsets: IndexSet, to destination: Int) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[p].sketches.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    // MARK: Clip

    /// Registra su disco una clip appena girata leggendone i metadati reali dal file.
    @MainActor
    func addClip(fileURL: URL, to target: RecordingTarget,
                 metadata: CaptureMetadata, isImported: Bool = false) async {
        guard let (p, s) = indexes(for: target) else { return }

        let asset = AVURLAsset(url: fileURL)
        var duration: Double = 0
        var size = CGSize.zero
        var fps: Double = metadata.fps

        if let d = try? await asset.load(.duration) { duration = CMTimeGetSeconds(d) }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let natural = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                size = natural.applying(transform)
            }
            if let rate = try? await track.load(.nominalFrameRate), rate > 0 { fps = Double(rate) }
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        let clip = Clip(fileName: fileURL.lastPathComponent,
                        duration: duration,
                        width: Int(abs(size.width)),
                        height: Int(abs(size.height)),
                        fps: fps,
                        codec: metadata.codec,
                        colorMode: metadata.colorMode,
                        stabilization: metadata.stabilization,
                        lens: metadata.lens,
                        fileSize: bytes,
                        take: projects[p].sketches[s].nextTake,
                        isImported: isImported)

        projects[p].sketches[s].clips.append(clip)
        save()
    }

    /// Aggiunge allo sketch un video già esistente (da Foto o da File),
    /// copiandolo nell'archivio dell'app così resta disponibile anche se l'originale sparisce.
    @MainActor
    func importVideo(from sourceURL: URL, to target: RecordingTarget,
                     securityScoped: Bool = false) async throws {
        var accessing = false
        if securityScoped { accessing = sourceURL.startAccessingSecurityScopedResource() }
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = newRecordingURL(extension: ext)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let metadata = await CaptureMetadata.read(from: destination)
        await addClip(fileURL: destination, to: target, metadata: metadata, isImported: true)
    }

    func updateClip(_ clipID: UUID, in target: RecordingTarget,
                    note: String? = nil, isSelect: Bool? = nil) {
        guard let (p, s) = indexes(for: target),
              let c = projects[p].sketches[s].clips.firstIndex(where: { $0.id == clipID })
        else { return }
        if let note { projects[p].sketches[s].clips[c].note = note }
        if let isSelect { projects[p].sketches[s].clips[c].isSelect = isSelect }
        save()
    }

    func deleteClip(_ clipID: UUID, in target: RecordingTarget) {
        guard let (p, s) = indexes(for: target),
              let c = projects[p].sketches[s].clips.firstIndex(where: { $0.id == clipID })
        else { return }
        removeFiles(for: projects[p].sketches[s].clips[c])
        projects[p].sketches[s].clips.remove(at: c)
        save()
    }

    /// Sposta una clip in un altro sketch senza toccare il file su disco.
    func moveClip(_ clipID: UUID, from source: RecordingTarget, to destination: RecordingTarget) {
        guard source != destination,
              let (p, s) = indexes(for: source),
              let c = projects[p].sketches[s].clips.firstIndex(where: { $0.id == clipID }),
              let (dp, ds) = indexes(for: destination)
        else { return }
        var clip = projects[p].sketches[s].clips.remove(at: c)
        clip.take = projects[dp].sketches[ds].nextTake
        projects[dp].sketches[ds].clips.append(clip)
        save()
    }

    func moveClips(in target: RecordingTarget, from offsets: IndexSet, to destination: Int) {
        guard let (p, s) = indexes(for: target) else { return }
        projects[p].sketches[s].clips.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    private func removeFiles(for clip: Clip) {
        try? FileManager.default.removeItem(at: url(for: clip))
        try? FileManager.default.removeItem(at: Thumbnailer.cacheURL(for: clip.id))
    }

    // MARK: Statistiche

    var totalClips: Int { projects.reduce(0) { $0 + $1.clipCount } }

    var usedBytes: Int64 {
        projects.reduce(0) { acc, p in
            acc + p.sketches.reduce(0) { $0 + $1.clips.reduce(0) { $0 + $1.fileSize } }
        }
    }

    /// Spazio libero utile sul dispositivo.
    static var availableBytes: Int64 {
        let values = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Elimina dai metadati le clip il cui file non esiste più, e cancella i file orfani.
    @discardableResult
    func reconcile() -> (removedEntries: Int, removedFiles: Int) {
        var removedEntries = 0
        var known = Set<String>()

        for p in projects.indices {
            for s in projects[p].sketches.indices {
                let before = projects[p].sketches[s].clips.count
                projects[p].sketches[s].clips.removeAll { clip in
                    !FileManager.default.fileExists(atPath: url(for: clip).path)
                }
                removedEntries += before - projects[p].sketches[s].clips.count
                for clip in projects[p].sketches[s].clips { known.insert(clip.fileName) }
            }
        }

        var removedFiles = 0
        let contents = (try? FileManager.default.contentsOfDirectory(at: Self.mediaDirectory,
                                                                    includingPropertiesForKeys: nil)) ?? []
        for file in contents where !known.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            removedFiles += 1
        }

        if removedEntries > 0 { save() }
        return (removedEntries, removedFiles)
    }
}

/// Metadati tecnici noti al momento dello scatto (li completa poi il file reale).
struct CaptureMetadata {
    var codec: String = ""
    var colorMode: String = ""
    var stabilization: String = ""
    var lens: String = ""
    var fps: Double = 0
}

enum ProjectPalette {
    static let colors: [String] = ["FF6B35", "3AAFA9", "F2C14E", "8367C7", "4ECB71", "EF476F"]
    static func hex(_ index: Int) -> String { colors[((index % colors.count) + colors.count) % colors.count] }
}
