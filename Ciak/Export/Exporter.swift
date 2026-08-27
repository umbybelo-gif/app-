import AVFoundation
import Foundation
import Photos
import UIKit

enum ExportError: LocalizedError {
    case noClips
    case photoLibraryDenied
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .noClips: return "Non c'è nessun video da esportare."
        case .photoLibraryDenied: return "Serve il permesso di aggiungere video a Foto. Attivalo da Impostazioni › Ciak."
        case .zipFailed(let reason): return "Creazione dell'archivio non riuscita: \(reason)"
        }
    }
}

enum Exporter {

    // MARK: Salvataggio in Foto

    static func saveToPhotoLibrary(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { throw ExportError.noClips }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.photoLibraryDenied }

        try await PHPhotoLibrary.shared().performChanges {
            for url in urls {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }

    // MARK: Esportazione su file

    /// Prepara una cartella temporanea con i video rinominati in modo leggibile
    /// (Progetto / Sketch / Ciak) e la comprime in un unico .zip da condividere.
    static func makeArchive(projectName: String,
                            groups: [(sketch: Sketch, clips: [Clip])],
                            fileURL: (Clip) -> URL,
                            includeManifest: Bool = true) throws -> URL {
        let allClips = groups.flatMap(\.clips)
        guard !allClips.isEmpty else { throw ExportError.noClips }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        let folderName = projectName.fileSafe
        let contentRoot = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: contentRoot, withIntermediateDirectories: true)

        for group in groups where !group.clips.isEmpty {
            let sketchDir = contentRoot.appendingPathComponent(group.sketch.title.fileSafe, isDirectory: true)
            try FileManager.default.createDirectory(at: sketchDir, withIntermediateDirectories: true)

            for clip in group.clips {
                let source = fileURL(clip)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
                let marker = clip.isSelect ? "_BUONA" : ""
                let name = "\(group.sketch.title.fileSafe)_Ciak-\(String(format: "%02d", clip.take))\(marker).\(ext)"
                try? FileManager.default.copyItem(at: source, to: sketchDir.appendingPathComponent(name))
            }
        }

        if includeManifest {
            let manifest = manifestText(projectName: projectName, groups: groups)
            try? manifest.write(to: contentRoot.appendingPathComponent("NOTE.txt"),
                                atomically: true, encoding: .utf8)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(folderName).zip")
        try zip(folder: contentRoot, to: destination)
        try? FileManager.default.removeItem(at: root)
        return destination
    }

    /// Versione asincrona: il lavoro pesante (copia e compressione) esce dal main thread.
    static func makeArchiveAsync(projectName: String,
                                 groups: [(sketch: Sketch, clips: [Clip])]) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Exporter.makeArchive(projectName: projectName, groups: groups) { clip in
                LibraryStore.mediaDirectory.appendingPathComponent(clip.fileName)
            }
        }.value
    }

    /// Compressione senza librerie esterne: NSFileCoordinator sa già produrre uno zip.
    private static func zip(folder: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var thrown: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: folder, options: [.forUploading],
                               error: &coordinatorError) { zippedURL in
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: zippedURL, to: destination)
            } catch {
                thrown = error
            }
        }

        if let coordinatorError { throw ExportError.zipFailed(coordinatorError.localizedDescription) }
        if let thrown { throw ExportError.zipFailed(thrown.localizedDescription) }
    }

    private static func manifestText(projectName: String,
                                     groups: [(sketch: Sketch, clips: [Clip])]) -> String {
        var lines = ["PROGETTO: \(projectName)",
                     "Esportato il \(Formatters.date.string(from: Date()))",
                     ""]
        for group in groups where !group.clips.isEmpty {
            lines.append("— \(group.sketch.title)")
            if !group.sketch.notes.isEmpty { lines.append("  Note: \(group.sketch.notes)") }
            for clip in group.clips.sorted(by: { $0.take < $1.take }) {
                var line = "  Ciak \(clip.take) · \(clip.durationLabel) · \(clip.technicalSummary)"
                if clip.isSelect { line += " · BUONA" }
                if !clip.note.isEmpty { line += "\n      \(clip.note)" }
                lines.append(line)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// Foglio di condivisione di sistema (AirDrop, File, Mail, WhatsApp…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
