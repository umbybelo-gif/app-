import AVKit
import Foundation
import SwiftUI

struct ClipDetailView: View {
    let target: RecordingTarget
    let clipID: UUID

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var noteDraft = ""
    @State private var editingNote = false
    @State private var shareURL: URL?
    @State private var statusMessage: String?
    @State private var showMove = false

    private var clip: Clip? { store.sketch(target)?.clips.first { $0.id == clipID } }

    var body: some View {
        Group {
            if let clip {
                content(clip)
            } else {
                EmptyStateView(icon: "film.stack", title: "Clip non trovata", message: "È stata eliminata o spostata.")
            }
        }
        .navigationTitle(clip.map { "Ciak \($0.take)" } ?? "Clip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onAppear(perform: preparePlayer)
        .onDisappear { player?.pause() }
        .sheet(isPresented: $showMove) {
            MoveClipsView(source: target, clipIDs: [clipID]) { dismiss() }
        }
        .sheet(item: Binding(get: { shareURL.map(ExportPayload.init) },
                             set: { if $0 == nil { shareURL = nil } })) { payload in
            ShareSheet(items: [payload.url])
        }
        .alert("Ciak", isPresented: Binding(get: { statusMessage != nil },
                                            set: { if !$0 { statusMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(statusMessage ?? "") }
        .alert("Nota del ciak", isPresented: $editingNote) {
            TextField("Es. luce migliore, battuta sbagliata…", text: $noteDraft)
            Button("Annulla", role: .cancel) {}
            Button("Salva") { store.updateClip(clipID, in: target, note: noteDraft) }
        }
    }

    private func content(_ clip: Clip) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                VideoPlayer(player: player)
                    .aspectRatio(CGFloat(max(clip.width, 1)) / CGFloat(max(clip.height, 1)),
                                 contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    store.updateClip(clipID, in: target, isSelect: !clip.isSelect)
                } label: {
                    Label(clip.isSelect ? "Ciak buono" : "Segna come buono",
                          systemImage: clip.isSelect ? "star.fill" : "star")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(clip.isSelect ? .yellow : .accentColor)

                if !clip.note.isEmpty {
                    Text(clip.note)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(spacing: 0) {
                    infoRow("Durata", clip.durationLabel)
                    Divider()
                    infoRow("Risoluzione", "\(clip.width)×\(clip.height)")
                    Divider()
                    infoRow("Frame rate", clip.fps > 0 ? String(format: "%.0f fps", clip.fps) : "—")
                    Divider()
                    infoRow("Codec", clip.codec.isEmpty ? "—" : clip.codec)
                    Divider()
                    infoRow("Colore", clip.colorMode.isEmpty ? "—" : clip.colorMode)
                    Divider()
                    infoRow("Stabilizzazione", clip.stabilization.isEmpty ? "—" : clip.stabilization)
                    Divider()
                    infoRow("Obiettivo", clip.lens.isEmpty ? "—" : clip.lens)
                    Divider()
                    infoRow("Origine", clip.originLabel)
                    Divider()
                    infoRow("Dimensione", clip.sizeLabel)
                    Divider()
                    infoRow("Girato il", Formatters.date.string(from: clip.createdAt))
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    if let clip { shareURL = store.url(for: clip) }
                } label: { Label("Condividi il file", systemImage: "square.and.arrow.up") }

                Button { saveToPhotos() } label: {
                    Label("Salva in Foto", systemImage: "photo.badge.arrow.down")
                }

                Button {
                    noteDraft = clip?.note ?? ""
                    editingNote = true
                } label: { Label("Nota", systemImage: "note.text") }

                Button { showMove = true } label: { Label("Sposta in…", systemImage: "folder") }

                Divider()

                Button(role: .destructive) {
                    store.deleteClip(clipID, in: target)
                    dismiss()
                } label: { Label("Elimina", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private func preparePlayer() {
        guard let clip else { return }
        let url = store.url(for: clip)
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "Il file di questo ciak non è più sul dispositivo."
            return
        }
        player = AVPlayer(url: url)
    }

    private func saveToPhotos() {
        guard let clip else { return }
        let url = store.url(for: clip)
        Task {
            do {
                try await Exporter.saveToPhotoLibrary([url])
                statusMessage = "Video salvato in Foto."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
