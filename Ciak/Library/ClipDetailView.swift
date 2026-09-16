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
    @State private var message: String?
    @State private var showMove = false
    @State private var confirmDelete = false

    private var clip: Clip? { store.sketch(target)?.clips.first { $0.id == clipID } }
    private var accent: Color { Color.project(store.project(target.projectID)?.colorIndex ?? 0) }

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()

            if let clip {
                content(clip)
            } else {
                EmptyStateView(icon: "film.stack", title: "Clip non trovata",
                               message: "È stata eliminata o spostata.")
            }
        }
        .navigationTitle(clip.map { "Ciak \($0.take)" } ?? "Clip")
        .navigationBarTitleDisplayMode(.inline)
        .darkNavigationBar()
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
        .messageAlert("Ciak", message: $message)
        .alert("Nota del ciak", isPresented: $editingNote) {
            TextField("Es. luce migliore, battuta sbagliata…", text: $noteDraft)
            Button("Annulla", role: .cancel) {}
            Button("Salva") { store.updateClip(clipID, in: target, note: noteDraft) }
        }
        .confirmationDialog("Eliminare questo ciak?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina il video", role: .destructive) {
                store.deleteClip(clipID, in: target)
                dismiss()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il file viene cancellato dal dispositivo.")
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
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Ink.stroke, lineWidth: 1))

                selectToggle(clip)

                actionRow

                if !clip.note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nota").techFont(9, weight: .bold).foregroundStyle(Ink.faint)
                        Text(clip.note)
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.text.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .card(radius: 14)
                }

                technicalSheet(clip)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func selectToggle(_ clip: Clip) -> some View {
        Button {
            store.updateClip(clipID, in: target, isSelect: !clip.isSelect)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: clip.isSelect ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .bold))
                Text(clip.isSelect ? "Ciak buono" : "Segna come buono")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(clip.isSelect ? Ink.bg : Ink.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(clip.isSelect ? Ink.gold : Ink.surface)
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(clip.isSelect ? .clear : Ink.gold.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionTile(icon: "square.and.arrow.up", label: "Condividi") {
                if let clip { shareURL = store.url(for: clip) }
            }
            actionTile(icon: "photo.badge.arrow.down", label: "In Foto") { saveToPhotos() }
            actionTile(icon: "note.text", label: "Nota") {
                noteDraft = clip?.note ?? ""
                editingNote = true
            }
            actionTile(icon: "folder", label: "Sposta") { showMove = true }
        }
    }

    private func actionTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).techFont(8.5)
            }
            .foregroundStyle(Ink.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .card(radius: 14)
        }
        .buttonStyle(.plain)
    }

    private func technicalSheet(_ clip: Clip) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scheda tecnica").techFont(9, weight: .bold).foregroundStyle(Ink.faint)
                Spacer()
                Text(clip.originLabel).techFont(9).foregroundStyle(clip.isImported ? Ink.dim : accent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            infoRow("Durata", clip.durationLabel)
            infoRow("Risoluzione", clip.width > 0 ? "\(clip.width)×\(clip.height)" : "—")
            infoRow("Frame rate", clip.fps > 0 ? String(format: "%.0f fps", clip.fps) : "—")
            infoRow("Codec", clip.codec.isEmpty ? "—" : clip.codec)
            infoRow("Colore", clip.colorMode.isEmpty ? "—" : clip.colorMode)
            infoRow("Stabilizzazione", clip.stabilization.isEmpty ? "—" : clip.stabilization)
            infoRow("Obiettivo", clip.lens.isEmpty ? "—" : clip.lens)
            infoRow("Dimensione", clip.sizeLabel)
            infoRow("Girato il", Formatters.date.string(from: clip.createdAt), last: true)
        }
        .card(radius: 16)
    }

    private func infoRow(_ title: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.dim)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !last {
                Rectangle().fill(Ink.stroke).frame(height: 1).padding(.leading, 14)
            }
        }
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

                Divider()

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Elimina", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
            }
        }
    }

    private func preparePlayer() {
        guard let clip else { return }
        let url = store.url(for: clip)
        guard FileManager.default.fileExists(atPath: url.path) else {
            message = "Il file di questo ciak non è più sul dispositivo."
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
                message = "Video salvato in Foto."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
