import SwiftUI

struct SketchDetailView: View {
    let target: RecordingTarget
    @Environment(LibraryStore.self) private var store

    @State private var showCamera = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var editingScript = false
    @State private var scriptDraft = ""
    @State private var selection = Set<UUID>()
    @State private var isSelecting = false
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var statusMessage: String?
    @State private var showMovePicker = false
    @State private var showPhotoImport = false
    @State private var showFileImport = false

    private var sketch: Sketch? { store.sketch(target) }
    private var project: Project? { store.project(target.projectID) }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        Group {
            if let sketch {
                content(sketch)
            } else {
                EmptyStateView(icon: "questionmark.folder", title: "Sketch non trovato", message: "Potrebbe essere stato eliminato.")
            }
        }
        .navigationTitle(sketch?.title ?? "Sketch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { recordBar }
        .fullScreenCover(isPresented: $showCamera) { CameraScreen(target: target) }
        .nameAlert("Rinomina sketch", placeholder: "Titolo",
                   isPresented: $showRename, text: $renameText) {
            store.updateSketch(target, title: renameText.trimmingCharacters(in: .whitespaces))
        }
        .sheet(isPresented: $editingScript) { scriptEditor }
        .sheet(isPresented: $showMovePicker) {
            MoveClipsView(source: target, clipIDs: Array(selection)) {
                selection.removeAll()
                isSelecting = false
            }
        }
        .sheet(item: Binding(get: { exportURL.map(ExportPayload.init) },
                             set: { if $0 == nil { exportURL = nil } })) { payload in
            ShareSheet(items: [payload.url])
        }
        .alert("Ciak", isPresented: Binding(get: { statusMessage != nil },
                                            set: { if !$0 { statusMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(statusMessage ?? "") }
        .overlay { if exporting { ProgressOverlay(text: "Preparo i file…") } }
        .videoImporter(target: target, showPhotos: $showPhotoImport, showFiles: $showFileImport)
    }

    private func content(_ sketch: Sketch) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !sketch.script.isEmpty || !sketch.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !sketch.script.isEmpty {
                            Text(sketch.script)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        }
                        if !sketch.notes.isEmpty {
                            Text(sketch.notes).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }

                if sketch.clips.isEmpty {
                    VStack(spacing: 4) {
                        EmptyStateView(icon: "video.badge.plus",
                                       title: "Nessun ciak",
                                       message: "Premi il pulsante rosso per girare la prima ripresa, oppure aggiungi un video che hai già.",
                                       actionTitle: "Registra ora") { showCamera = true }
                        Button("Importa un video") { showPhotoImport = true }
                            .font(.subheadline)
                    }
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sketch.clips) { clip in
                            clipCell(clip)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 90)
        }
    }

    private func clipCell(_ clip: Clip) -> some View {
        let selected = selection.contains(clip.id)
        return Group {
            if isSelecting {
                ClipCard(clip: clip, url: store.url(for: clip), selected: selected)
                    .onTapGesture {
                        if selected { selection.remove(clip.id) } else { selection.insert(clip.id) }
                    }
            } else {
                NavigationLink {
                    ClipDetailView(target: target, clipID: clip.id)
                } label: {
                    ClipCard(clip: clip, url: store.url(for: clip), selected: false)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        store.updateClip(clip.id, in: target, isSelect: !clip.isSelect)
                    } label: {
                        Label(clip.isSelect ? "Togli da buone" : "Segna come buona",
                              systemImage: clip.isSelect ? "star.slash" : "star")
                    }
                    Button {
                        shareClips([clip])
                    } label: { Label("Condividi", systemImage: "square.and.arrow.up") }
                    Button {
                        saveToPhotos([clip])
                    } label: { Label("Salva in Foto", systemImage: "photo.badge.arrow.down") }
                    Divider()
                    Button(role: .destructive) {
                        store.deleteClip(clip.id, in: target)
                    } label: { Label("Elimina", systemImage: "trash") }
                }
            }
        }
    }

    private var recordBar: some View {
        HStack(spacing: 14) {
            if isSelecting {
                Button("Annulla") { isSelecting = false; selection.removeAll() }
                Spacer()
                Text("\(selection.count) selezionate").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button { exportSelection() } label: { Label("Esporta .zip", systemImage: "square.and.arrow.up") }
                    Button { saveToPhotos(selectedClips) } label: { Label("Salva in Foto", systemImage: "photo.badge.arrow.down") }
                    Button { showMovePicker = true } label: { Label("Sposta in…", systemImage: "folder") }
                    Divider()
                    Button(role: .destructive) {
                        for id in selection { store.deleteClip(id, in: target) }
                        selection.removeAll(); isSelecting = false
                    } label: { Label("Elimina", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title2)
                }
                .disabled(selection.isEmpty)
            } else {
                Button {
                    showCamera = true
                } label: {
                    Label("Registra ciak \(sketch?.nextTake ?? 1)", systemImage: "record.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    isSelecting.toggle()
                    selection.removeAll()
                } label: { Label(isSelecting ? "Fine selezione" : "Seleziona", systemImage: "checkmark.circle") }

                Button {
                    renameText = sketch?.title ?? ""
                    showRename = true
                } label: { Label("Rinomina", systemImage: "pencil") }

                Button {
                    scriptDraft = sketch?.script ?? ""
                    editingScript = true
                } label: { Label("Copione / note", systemImage: "text.alignleft") }

                if let sketch {
                    Button {
                        store.updateSketch(target, isDone: !sketch.isDone)
                    } label: {
                        Label(sketch.isDone ? "Riapri sketch" : "Segna come completato",
                              systemImage: sketch.isDone ? "arrow.uturn.backward" : "checkmark.circle")
                    }
                }

                Divider()

                Button { showPhotoImport = true } label: {
                    Label("Importa da Foto", systemImage: "photo.on.rectangle")
                }
                Button { showFileImport = true } label: {
                    Label("Importa da File", systemImage: "folder.badge.plus")
                }

                Divider()

                Button { exportAll() } label: { Label("Esporta tutto (.zip)", systemImage: "square.and.arrow.up") }
                Button { exportSelects() } label: { Label("Esporta solo le buone", systemImage: "star") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private var scriptEditor: some View {
        NavigationStack {
            TextEditor(text: $scriptDraft)
                .padding()
                .navigationTitle("Copione")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { editingScript = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") {
                            store.updateSketch(target, script: scriptDraft)
                            editingScript = false
                        }
                    }
                }
        }
    }

    // MARK: Azioni

    private var selectedClips: [Clip] {
        (sketch?.clips ?? []).filter { selection.contains($0.id) }
    }

    private func shareClips(_ clips: [Clip]) {
        let urls = clips.map { store.url(for: $0) }
        guard let first = urls.first else { return }
        exportURL = first
    }

    private func saveToPhotos(_ clips: [Clip]) {
        let urls = clips.map { store.url(for: $0) }
        Task {
            do {
                try await Exporter.saveToPhotoLibrary(urls)
                statusMessage = urls.count == 1 ? "Video salvato in Foto." : "\(urls.count) video salvati in Foto."
                isSelecting = false
                selection.removeAll()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func exportAll() { export(clips: sketch?.clips ?? []) }

    private func exportSelects() {
        let selects = (sketch?.clips ?? []).filter(\.isSelect)
        if selects.isEmpty {
            statusMessage = "Nessuna clip è segnata come buona. Tienile premute per marcarle."
            return
        }
        export(clips: selects)
    }

    private func exportSelection() { export(clips: selectedClips) }

    private func export(clips: [Clip]) {
        guard let sketch, !clips.isEmpty else {
            statusMessage = "Non c'è nulla da esportare."
            return
        }
        exporting = true
        let name = "\(project?.name ?? "Progetto") - \(sketch.title)"
        let groups = [(sketch: sketch, clips: clips)]
        Task {
            do {
                let url = try await Exporter.makeArchiveAsync(projectName: name, groups: groups)
                exporting = false
                exportURL = url
                isSelecting = false
                selection.removeAll()
            } catch {
                exporting = false
                statusMessage = error.localizedDescription
            }
        }
    }
}

struct ClipCard: View {
    let clip: Clip
    let url: URL
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ClipThumbnail(clip: clip, url: url)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(height: 96)
                    .clipped()

                HStack {
                    Text("Ciak \(clip.take)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                    Spacer()
                    if clip.isSelect {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .padding(5)
                            .background(.yellow, in: Circle())
                            .foregroundStyle(.black)
                    }
                }
                .padding(6)

                if selected {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text(clip.durationLabel)
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .padding(6)
            }

            Text(clip.technicalSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !clip.note.isEmpty {
                Text(clip.note).font(.caption2).lineLimit(2)
            }
        }
        .frame(height: 150, alignment: .top)
    }
}

/// Scelta della destinazione per spostare una o più clip.
struct MoveClipsView: View {
    let source: RecordingTarget
    let clipIDs: [UUID]
    let onDone: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.projects.filter { !$0.isArchived }) { project in
                    Section(project.name) {
                        ForEach(project.sketches) { sketch in
                            let destination = RecordingTarget(projectID: project.id, sketchID: sketch.id)
                            Button {
                                for id in clipIDs { store.moveClip(id, from: source, to: destination) }
                                onDone()
                                dismiss()
                            } label: {
                                HStack {
                                    Text(sketch.title)
                                    Spacer()
                                    if destination == source {
                                        Text("attuale").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(destination == source)
                        }
                    }
                }
            }
            .navigationTitle("Sposta in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
    }
}
