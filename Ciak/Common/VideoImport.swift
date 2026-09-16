import AVFoundation
import CoreMedia
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Un video prelevato dal selettore di Foto. Serve a copiarne il file
/// in una posizione nostra prima che il sistema lo rimuova.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideo(url: copy)
        }
    }
}

extension CaptureMetadata {
    /// Ricava i dati tecnici leggendoli dal file, per i video non girati dall'app.
    static func read(from url: URL) async -> CaptureMetadata {
        var metadata = CaptureMetadata()
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return metadata }

        if let descriptions = try? await track.load(.formatDescriptions), let first = descriptions.first {
            metadata.codec = Self.codecLabel(CMFormatDescriptionGetMediaSubType(first))
        }
        if let rate = try? await track.load(.nominalFrameRate), rate > 0 {
            metadata.fps = Double(rate)
        }
        return metadata
    }

    private static func codecLabel(_ subType: FourCharCode) -> String {
        switch subType {
        case FourCharCode.from("hvc1"), FourCharCode.from("hev1"): return "HEVC"
        case FourCharCode.from("avc1"): return "H.264"
        case FourCharCode.from("apcn"): return "ProRes 422"
        case FourCharCode.from("apch"): return "ProRes 422 HQ"
        case FourCharCode.from("apcs"): return "ProRes 422 LT"
        case FourCharCode.from("apco"): return "ProRes 422 Proxy"
        case FourCharCode.from("ap4h"): return "ProRes 4444"
        case FourCharCode.from("jpeg"): return "Motion JPEG"
        default: return subType.stringValue
        }
    }
}

extension FourCharCode {
    var stringValue: String {
        let bytes = [UInt8((self >> 24) & 0xFF), UInt8((self >> 16) & 0xFF),
                     UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
        let text = String(bytes: bytes, encoding: .ascii) ?? ""
        return text.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : text
    }
}

/// Tipi di file accettati dall'importazione da File.
enum ImportTypes {
    static let movies: [UTType] = [.movie, .quickTimeMovie, .mpeg4Movie]
}


// MARK: - Importazione da Foto e da File

/// Aggiunge a una vista le due sorgenti di importazione, con avanzamento ed esito.
struct VideoImportModifier: ViewModifier {
    let target: RecordingTarget
    @Binding var showPhotos: Bool
    @Binding var showFiles: Bool
    let onImported: ((Int) -> Void)?

    @Environment(LibraryStore.self) private var store
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showPhotos, selection: $picked,
                          maxSelectionCount: 20, matching: .videos)
            .fileImporter(isPresented: $showFiles,
                          allowedContentTypes: ImportTypes.movies,
                          allowsMultipleSelection: true) { result in
                handleFiles(result)
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                importFromPhotos(items)
            }
            .overlay { if importing { ProgressOverlay(text: "Importo i video…") } }
            .alert("Importazione", isPresented: Binding(get: { message != nil },
                                                        set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
    }

    private func importFromPhotos(_ items: [PhotosPickerItem]) {
        importing = true
        Task {
            var imported = 0
            var failures = 0
            for item in items {
                do {
                    if let video = try await item.loadTransferable(type: PickedVideo.self) {
                        try await store.importVideo(from: video.url, to: target)
                        try? FileManager.default.removeItem(at: video.url)
                        imported += 1
                    } else {
                        failures += 1
                    }
                } catch {
                    failures += 1
                }
            }
            picked = []
            importing = false
            report(imported: imported, failures: failures)
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            importing = true
            Task {
                var imported = 0
                var failures = 0
                for url in urls {
                    do {
                        try await store.importVideo(from: url, to: target, securityScoped: true)
                        imported += 1
                    } catch {
                        failures += 1
                    }
                }
                importing = false
                report(imported: imported, failures: failures)
            }
        }
    }

    private func report(imported: Int, failures: Int) {
        onImported?(imported)
        if imported == 0 {
            message = "Nessun video importato."
        } else if failures > 0 {
            message = "\(imported) video importati, \(failures) non riusciti."
        } else {
            message = imported == 1 ? "Video importato." : "\(imported) video importati."
        }
    }
}

extension View {
    func videoImporter(target: RecordingTarget,
                       showPhotos: Binding<Bool>,
                       showFiles: Binding<Bool>,
                       onImported: ((Int) -> Void)? = nil) -> some View {
        modifier(VideoImportModifier(target: target,
                                     showPhotos: showPhotos,
                                     showFiles: showFiles,
                                     onImported: onImported))
    }
}
