import Foundation
import SwiftUI

struct ProjectDetailView: View {
    let projectID: UUID
    @Environment(LibraryStore.self) private var store

    @State private var showNewSketch = false
    @State private var newSketchTitle = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var editingNotes = false
    @State private var notesDraft = ""
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var message: String?
    @State private var recordingTarget: RecordingTarget?
    @State private var pendingDelete: Sketch?

    private var project: Project? { store.project(projectID) }
    private var accent: Color { Color.project(project?.colorIndex ?? 0) }

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            GlowBackdrop(color: accent, height: 300)

            if let project {
                content(project)
            } else {
                EmptyStateView(icon: "questionmark.folder",
                               title: "Progetto non trovato",
                               message: "Potrebbe essere stato eliminato.")
            }
        }
        .navigationTitle(project?.name ?? "Progetto")
        .navigationBarTitleDisplayMode(.inline)
        .darkNavigationBar()
        .toolbar { toolbar }
        .nameAlert("Nuovo sketch", placeholder: "Titolo dello sketch",
                   isPresented: $showNewSketch, text: $newSketchTitle) {
            store.addSketch(to: projectID, title: newSketchTitle.trimmingCharacters(in: .whitespaces))
        }
        .nameAlert("Rinomina progetto", placeholder: "Nome",
                   isPresented: $showRename, text: $renameText) {
            store.updateProject(projectID, name: renameText.trimmingCharacters(in: .whitespaces))
        }
        .sheet(isPresented: $editingNotes) {
            TextEditorSheet(title: "Note del progetto", text: $notesDraft) {
                store.updateProject(projectID, notes: notesDraft)
            }
        }
        .sheet(item: Binding(get: { exportURL.map(ExportPayload.init) },
                             set: { if $0 == nil { exportURL = nil } })) { payload in
            ShareSheet(items: [payload.url])
        }
        .fullScreenCover(item: $recordingTarget) { target in
            CameraScreen(target: target)
        }
        .messageAlert("Ciak", message: $message)
        .confirmationDialog("Eliminare “\(pendingDelete?.title ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina sketch e ciak", role: .destructive) {
                if let pendingDelete {
                    store.deleteSketch(RecordingTarget(projectID: projectID, sketchID: pendingDelete.id))
                }
                pendingDelete = nil
            }
            Button("Annulla", role: .cancel) { pendingDelete = nil }
        }
        .overlay { if exporting { ProgressOverlay(text: "Preparo l'archivio") } }
    }

    // MARK: Contenuto

    private func content(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(project)

                if !project.notes.isEmpty {
                    Text(project.notes)
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .card(radius: 14)
                }

                SectionHeader(title: "Sketch", trailing: "\(project.sketches.count)")

                if project.sketches.isEmpty {
                    EmptyStateView(icon: "square.stack.3d.up",
                                   title: "Nessuno sketch",
                                   message: "Uno sketch è una singola idea o scena. Dentro finiscono tutti i ciak che giri per quell'idea.",
                                   actionTitle: "Crea sketch") { startNewSketch() }
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(project.sketches.enumerated()), id: \.element.id) { index, sketch in
                            NavigationLink {
                                SketchDetailView(target: RecordingTarget(projectID: projectID, sketchID: sketch.id))
                            } label: {
                                SketchCard(sketch: sketch, accent: accent, store: store)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    recordingTarget = RecordingTarget(projectID: projectID, sketchID: sketch.id)
                                } label: { Label("Registra", systemImage: "record.circle") }

                                Button {
                                    store.updateSketch(RecordingTarget(projectID: projectID, sketchID: sketch.id),
                                                       isDone: !sketch.isDone)
                                } label: {
                                    Label(sketch.isDone ? "Riapri" : "Segna completato",
                                          systemImage: sketch.isDone ? "arrow.uturn.backward" : "checkmark.circle")
                                }

                                if index > 0 {
                                    Button {
                                        store.moveSketches(in: projectID,
                                                           from: IndexSet(integer: index), to: index - 1)
                                    } label: { Label("Sposta su", systemImage: "arrow.up") }
                                }
                                if index < project.sketches.count - 1 {
                                    Button {
                                        store.moveSketches(in: projectID,
                                                           from: IndexSet(integer: index), to: index + 2)
                                    } label: { Label("Sposta giù", systemImage: "arrow.down") }
                                }

                                Button(role: .destructive) {
                                    pendingDelete = sketch
                                } label: { Label("Elimina sketch", systemImage: "trash") }
                            }
                        }
                    }

                    Button {
                        startNewSketch()
                    } label: {
                        Label("Nuovo sketch", systemImage: "plus")
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private func hero(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progetto").techFont(10, weight: .bold).foregroundStyle(accent)
            Text(project.name)
                .displayFont(34)
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TechChip(text: "\(project.sketches.count) sketch", tint: accent)
                TechChip(text: "\(project.clipCount) clip")
                if project.totalDuration > 0 {
                    TechChip(text: Formatters.duration(project.totalDuration), icon: "clock")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { startNewSketch() } label: { Label("Nuovo sketch", systemImage: "plus") }
                Button {
                    renameText = project?.name ?? ""
                    showRename = true
                } label: { Label("Rinomina", systemImage: "pencil") }
                Button {
                    notesDraft = project?.notes ?? ""
                    editingNotes = true
                } label: { Label("Note del progetto", systemImage: "note.text") }

                Divider()

                Button { exportProject() } label: {
                    Label("Esporta tutto (.zip)", systemImage: "square.and.arrow.up")
                }

                if let project {
                    Menu("Colore") {
                        ForEach(ProjectPalette.colors.indices, id: \.self) { index in
                            Button {
                                store.updateProject(projectID, colorIndex: index)
                            } label: {
                                Label("Colore \(index + 1)",
                                      systemImage: project.colorIndex == index ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    }
                }

                Button {
                    store.updateProject(projectID, isArchived: !(project?.isArchived ?? false))
                } label: {
                    Label(project?.isArchived == true ? "Ripristina" : "Archivia", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
            }
        }
    }

    private func startNewSketch() {
        newSketchTitle = ""
        showNewSketch = true
    }

    private func exportProject() {
        guard let project else { return }
        exporting = true
        let groups = project.sketches.map { (sketch: $0, clips: $0.clips) }
        let name = project.name
        Task {
            do {
                let url = try await Exporter.makeArchiveAsync(projectName: name, groups: groups)
                exporting = false
                exportURL = url
            } catch {
                exporting = false
                message = error.localizedDescription
            }
        }
    }
}

// MARK: - Scheda sketch

struct SketchCard: View {
    let sketch: Sketch
    let accent: Color
    let store: LibraryStore

    private var cover: Clip? {
        sketch.clips.first(where: \.isSelect) ?? sketch.clips.last
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let cover {
                    ClipThumbnail(clip: cover, url: store.url(for: cover), cornerRadius: 12)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Ink.surfaceHigh)
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 15))
                                .foregroundStyle(Ink.faint)
                        )
                }
            }
            .frame(width: 84, height: 60)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Ink.stroke, lineWidth: 1))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    if sketch.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.good)
                    }
                    Text(sketch.title)
                        .displayFont(18, weight: .bold)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    TechChip(text: "\(sketch.clips.count) ciak", tint: accent)
                    if sketch.selectsCount > 0 {
                        TechChip(text: "\(sketch.selectsCount) buone", icon: "star.fill", tint: Ink.gold)
                    }
                    if sketch.totalDuration > 0 {
                        TechChip(text: Formatters.duration(sketch.totalDuration))
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Ink.faint)
        }
        .padding(12)
        .card(radius: 18)
    }
}

// MARK: - Editor di testo a tutta pagina

struct TextEditorSheet: View {
    let title: String
    @Binding var text: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                TextEditor(text: $draft)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.text)
                    .padding(14)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .darkNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        text = draft
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { draft = text }
        }
        .tint(Ink.accent)
    }
}
