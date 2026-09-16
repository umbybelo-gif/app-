import Foundation
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
    @State private var message: String?
    @State private var showMovePicker = false
    @State private var showPhotoImport = false
    @State private var showFileImport = false

    private var sketch: Sketch? { store.sketch(target) }
    private var project: Project? { store.project(target.projectID) }
    private var accent: Color { Color.project(project?.colorIndex ?? 0) }

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 10)]

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            GlowBackdrop(color: accent, height: 240).opacity(0.7)

            if let sketch {
                content(sketch)
            } else {
                EmptyStateView(icon: "questionmark.folder", title: "Sketch non trovato",
                               message: "Potrebbe essere stato eliminato.")
            }
        }
        .navigationTitle(sketch?.title ?? "Sketch")
        .navigationBarTitleDisplayMode(.inline)
        .darkNavigationBar()
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .fullScreenCover(isPresented: $showCamera) { CameraScreen(target: target) }
        .nameAlert("Rinomina sketch", placeholder: "Titolo",
                   isPresented: $showRename, text: $renameText) {
            store.updateSketch(target, title: renameText.trimmingCharacters(in: .whitespaces))
        }
        .sheet(isPresented: $editingScript) {
            TextEditorSheet(title: "Copione", text: $scriptDraft) {
                store.updateSketch(target, script: scriptDraft)
            }
        }
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
        .messageAlert("Ciak", message: $message)
        .overlay { if exporting { ProgressOverlay(text: "Preparo i file") } }
        .videoImporter(target: target, showPhotos: $showPhotoImport, showFiles: $showFileImport)
    }

    // MARK: Contenuto

    private func content(_ sketch: Sketch) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(sketch)

                if !sketch.script.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Copione").techFont(9, weight: .bold).foregroundStyle(Ink.faint)
                        Text(sketch.script)
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.text.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .card(radius: 14)
                }

                if sketch.clips.isEmpty {
                    VStack(spacing: 10) {
                        EmptyStateView(icon: "video.badge.plus",
                                       title: "Nessun ciak",
                                       message: "Premi il pulsante rosso per girare la prima ripresa, oppure aggiungi un video che hai già.")
                        Button("Importa un video") { showPhotoImport = true }
                            .buttonStyle(OutlineButtonStyle())
                            .frame(maxWidth: 240)
                    }
                    .padding(.top, 20)
                } else {
                    SectionHeader(title: "Ciak", trailing: "\(sketch.clips.count)")

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(sketch.clips) { clip in
                            clipCell(clip)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func hero(_ sketch: Sketch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(project?.name ?? "").techFont(10, weight: .bold).foregroundStyle(accent)
                if sketch.isDone {
                    TechChip(text: "completato", icon: "checkmark", tint: Ink.good)
                }
            }
            Text(sketch.title)
                .displayFont(32)
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TechChip(text: "\(sketch.clips.count) ciak", tint: accent)
                if sketch.selectsCount > 0 {
                    TechChip(text: "\(sketch.selectsCount) buone", icon: "star.fill", tint: Ink.gold)
                }
                if sketch.totalDuration > 0 {
                    TechChip(text: Formatters.duration(sketch.totalDuration), icon: "clock")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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
                    Button { exportURL = store.url(for: clip) } label: {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                    }
                    Button { saveToPhotos([clip]) } label: {
                        Label("Salva in Foto", systemImage: "photo.badge.arrow.down")
                    }
                    Divider()
                    Button(role: .destructive) {
                        store.deleteClip(clip.id, in: target)
                    } label: { Label("Elimina", systemImage: "trash") }
                }
            }
        }
    }

    // MARK: Barra inferiore

    private var bottomBar: some View {
        Group {
            if isSelecting {
                HStack(spacing: 12) {
                    Button("Annulla") { isSelecting = false; selection.removeAll() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.dim)

                    Spacer()
                    Text("\(selection.count) selezionate").techFont(10).foregroundStyle(Ink.text)
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
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(selection.isEmpty ? Ink.faint : Ink.accent)
                    }
                    .disabled(selection.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            } else {
                HStack(spacing: 10) {
                    Button {
                        showCamera = true
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Ink.live).frame(width: 10, height: 10)
                            Text("Registra ciak \(sketch?.nextTake ?? 1)")
                        }
                    }
                    .buttonStyle(AccentButtonStyle())

                    Menu {
                        Button { showPhotoImport = true } label: { Label("Importa da Foto", systemImage: "photo.on.rectangle") }
                        Button { showFileImport = true } label: { Label("Importa da File", systemImage: "folder.badge.plus") }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Ink.text)
                            .frame(width: 50, height: 50)
                            .card(radius: 14, fill: Ink.surfaceHigh)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(
                    LinearGradient(colors: [Ink.bg.opacity(0), Ink.bg.opacity(0.92), Ink.bg],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
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
                } label: { Label("Copione", systemImage: "text.alignleft") }

                if let sketch {
                    Button {
                        store.updateSketch(target, isDone: !sketch.isDone)
                    } label: {
                        Label(sketch.isDone ? "Riapri sketch" : "Segna completato",
                              systemImage: sketch.isDone ? "arrow.uturn.backward" : "checkmark.circle")
                    }
                }

                Divider()

                Button { showPhotoImport = true } label: { Label("Importa da Foto", systemImage: "photo.on.rectangle") }
                Button { showFileImport = true } label: { Label("Importa da File", systemImage: "folder.badge.plus") }

                Divider()

                Button { exportAll() } label: { Label("Esporta tutto (.zip)", systemImage: "square.and.arrow.up") }
                Button { exportSelects() } label: { Label("Esporta solo le buone", systemImage: "star") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
            }
        }
    }

    // MARK: Azioni

    private var selectedClips: [Clip] {
        (sketch?.clips ?? []).filter { selection.contains($0.id) }
    }

    private func saveToPhotos(_ clips: [Clip]) {
        let urls = clips.map { store.url(for: $0) }
        Task {
            do {
                try await Exporter.saveToPhotoLibrary(urls)
                message = urls.count == 1 ? "Video salvato in Foto." : "\(urls.count) video salvati in Foto."
                isSelecting = false
                selection.removeAll()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func exportAll() { export(clips: sketch?.clips ?? []) }

    private func exportSelects() {
        let selects = (sketch?.clips ?? []).filter(\.isSelect)
        if selects.isEmpty {
            message = "Nessuna clip è segnata come buona. Tienile premute per marcarle."
            return
        }
        export(clips: selects)
    }

    private func exportSelection() { export(clips: selectedClips) }

    private func export(clips: [Clip]) {
        guard let sketch, !clips.isEmpty else {
            message = "Non c'è nulla da esportare."
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
                message = error.localizedDescription
            }
        }
    }
}

// MARK: - Scheda clip

struct ClipCard: View {
    let clip: Clip
    let url: URL
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ClipThumbnail(clip: clip, url: url, cornerRadius: 0)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(ScrimGradient())

                HStack(alignment: .top) {
                    Text("\(String(format: "%02d", clip.take))")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    if clip.isSelect {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Ink.bg)
                            .padding(5)
                            .background(Ink.gold, in: Circle())
                    }
                    if clip.isImported {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(clip.durationLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.technicalSummary)
                    .techFont(8.5)
                    .foregroundStyle(Ink.faint)
                    .lineLimit(1)
                if !clip.note.isEmpty {
                    Text(clip.note)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.dim)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
        }
        .background(Ink.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Ink.accent : (clip.isSelect ? Ink.gold.opacity(0.5) : Ink.stroke),
                              lineWidth: selected ? 2 : 1)
        )
    }
}

// MARK: - Scelta della destinazione

struct MoveClipsView: View {
    let source: RecordingTarget
    let clipIDs: [UUID]
    let onDone: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(store.projects.filter { !$0.isArchived }) { project in
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: project.name)
                                ForEach(project.sketches) { sketch in
                                    let destination = RecordingTarget(projectID: project.id, sketchID: sketch.id)
                                    Button {
                                        for id in clipIDs { store.moveClip(id, from: source, to: destination) }
                                        onDone()
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Text(sketch.title)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(destination == source ? Ink.faint : Ink.text)
                                            Spacer()
                                            if destination == source {
                                                Text("attuale").techFont(9).foregroundStyle(Ink.faint)
                                            } else {
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(Ink.faint)
                                            }
                                        }
                                        .padding(14)
                                        .card(radius: 14)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(destination == source)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Sposta in")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
        .tint(Ink.accent)
    }
}
