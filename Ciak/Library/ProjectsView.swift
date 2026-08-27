import SwiftUI

struct ProjectsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AuthManager.self) private var auth

    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var search = ""
    @State private var showArchived = false
    @State private var showSettings = false

    private var visibleProjects: [Project] {
        store.projects
            .filter { showArchived ? true : !$0.isArchived }
            .filter { search.isEmpty ? true : matches($0, query: search) }
    }

    private func matches(_ project: Project, query: String) -> Bool {
        let q = query.lowercased()
        if project.name.lowercased().contains(q) { return true }
        return project.sketches.contains { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    EmptyStateView(icon: "folder.badge.plus",
                                   title: "Nessun progetto",
                                   message: "Crea un progetto per iniziare a organizzare i tuoi video: dentro ci metterai gli sketch e i relativi ciak.",
                                   actionTitle: "Crea progetto") { startNewProject() }
                } else {
                    list
                }
            }
            .navigationTitle("Progetti")
            .searchable(text: $search, prompt: "Cerca progetti e sketch")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            startNewProject()
                        } label: { Label("Nuovo progetto", systemImage: "plus") }
                        Toggle(isOn: $showArchived) { Label("Mostra archiviati", systemImage: "archivebox") }
                        Button {
                            auth.lock()
                        } label: { Label("Blocca l'app", systemImage: "lock.fill") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .nameAlert("Nuovo progetto", placeholder: "Nome del progetto",
                       isPresented: $showNewProject, text: $newProjectName) {
                store.addProject(name: newProjectName.trimmingCharacters(in: .whitespaces))
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var list: some View {
        List {
            if !visibleProjects.isEmpty {
                Section {
                    ForEach(visibleProjects) { project in
                        NavigationLink(value: project.id) {
                            ProjectRow(project: project)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteProject(project.id)
                            } label: { Label("Elimina", systemImage: "trash") }

                            Button {
                                store.updateProject(project.id, isArchived: !project.isArchived)
                            } label: {
                                Label(project.isArchived ? "Ripristina" : "Archivia",
                                      systemImage: project.isArchived ? "tray.and.arrow.up" : "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                } footer: {
                    Text("\(store.projects.count) progetti · \(store.totalClips) clip · \(Formatters.bytes(store.usedBytes)) occupati")
                }
            } else {
                Text("Nessun risultato").foregroundStyle(.secondary)
            }
        }
        .navigationDestination(for: UUID.self) { id in
            ProjectDetailView(projectID: id)
        }
    }

    private func startNewProject() {
        newProjectName = ""
        showNewProject = true
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.project(project.colorIndex))
                .frame(width: 5, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(project.isArchived ? .secondary : .primary)
                HStack(spacing: 12) {
                    StatLabel(icon: "list.bullet", text: "\(project.sketches.count) sketch")
                    StatLabel(icon: "film", text: "\(project.clipCount) clip")
                    if project.totalDuration > 0 {
                        StatLabel(icon: "clock", text: Formatters.duration(project.totalDuration))
                    }
                }
            }
            Spacer()
            if project.isArchived {
                Image(systemName: "archivebox.fill").foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
