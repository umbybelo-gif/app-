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
    @State private var exportError: String?
    @State private var recordingTarget: RecordingTarget?

    private var project: Project? { store.project(projectID) }

    var body: some View {
        Group {
            if let project {
                content(project)
            } else {
                EmptyStateView(icon: "questionmark.folder",
                               title: "Progetto non trovato",
                               message: "Potrebbe essere stato eliminato.")
            }
        }
        .navigationTitle(project?.name ?? "Progetto")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar }
        .nameAlert("Nuovo sketch", placeholder: "Titolo dello sketch",
                   isPresented: $showNewSketch, text: $newSketchTitle) {
            store.addSketch(to: projectID, title: newSketchTitle.trimmingCharacters(in: .whitespaces))
        }
        .nameAlert("Rinomina progetto", placeholder: "Nome",
                   isPresented: $showRename, text: $renameText) {
            store.updateProject(projectID, name: renameText.trimmingCharacters(in: .whitespaces))
        }
        .sheet(isPresented: $editingNotes) { notesEditor }
        .sheet(item: Binding(get: { exportURL.map(ExportPayload.init) },
                             set: { if $0 == nil { exportURL = nil } })) { payload in
            ShareSheet(items: [payload.url])
        }
        .fullScreenCover(item: $recordingTarget) { target in
            CameraScreen(target: target)
        }
        .alert("Esportazione", isPresented: Binding(get: { exportError != nil },
                                                    set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .overlay { if exporting { ProgressOverlay(text: "Preparo l'archivio…") } }
    }

    private func content(_ project: Project) -> some View {
        List {
            if !project.notes.isEmpty {
                Section("Note") {
                    Text(project.notes).font(.subheadline)
                }
            }

            Section {
                if project.sketches.isEmpty {
                    EmptyStateView(icon: "square.stack.3d.up",
                                   title: "Nessuno sketch",
                                   message: "Uno sketch è una singola idea o scena. Dentro finiscono tutti i ciak che giri per quell'idea.",
                                   actionTitle: "Crea sketch") { startNewSketch() }
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(project.sketches) { sketch in
                        NavigationLink {
                            SketchDetailView(target: RecordingTarget(projectID: projectID, sketchID: sketch.id))
                        } label: {
                            SketchRow(sketch: sketch, color: Color.project(project.colorIndex))
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                recordingTarget = RecordingTarget(projectID: projectID, sketchID: sketch.id)
                            } label: { Label("Registra", systemImage: "record.circle") }
                                .tint(.red)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteSketch(RecordingTarget(projectID: projectID, sketchID: sketch.id))
                            } label: { Label("Elimina", systemImage: "trash") }
                        }
                    }
                    .onMove { offsets, destination in
                        store.moveSketches(in: projectID, from: offsets, to: destination)
                    }
                }
            } header: {
                Text("Sketch")
            } footer: {
                if project.clipCount > 0 {
                    Text("\(project.clipCount) clip · \(Formatters.duration(project.totalDuration))")
                }
            }
        }
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
            } label: { Image(systemName: "ellipsis.circle") }
        }
        ToolbarItem(placement: .topBarTrailing) { EditButton() }
    }

    private var notesEditor: some View {
        NavigationStack {
            TextEditor(text: $notesDraft)
                .padding()
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { editingNotes = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") {
                            store.updateProject(projectID, notes: notesDraft)
                            editingNotes = false
                        }
                    }
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
                exportError = error.localizedDescription
            }
        }
    }
}

struct SketchRow: View {
    let sketch: Sketch
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: sketch.isDone ? "checkmark" : "film")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(sketch.title).font(.headline)
                HStack(spacing: 12) {
                    StatLabel(icon: "film", text: "\(sketch.clips.count)")
                    if sketch.selectsCount > 0 {
                        StatLabel(icon: "star.fill", text: "\(sketch.selectsCount) buone")
                    }
                    if sketch.totalDuration > 0 {
                        StatLabel(icon: "clock", text: Formatters.duration(sketch.totalDuration))
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// Wrapper per presentare il foglio di condivisione con `sheet(item:)`.
struct ExportPayload: Identifiable {
    let url: URL
    var id: String { url.path }
    init(_ url: URL) { self.url = url }
}

extension RecordingTarget: Identifiable {
    var id: String { "\(projectID.uuidString)-\(sketchID.uuidString)" }
}

struct ProgressOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(text).font(.subheadline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
