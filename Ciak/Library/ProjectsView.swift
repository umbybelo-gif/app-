import Foundation
import SwiftUI

struct ProjectsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AuthManager.self) private var auth

    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var search = ""
    @State private var showArchived = false
    @State private var showSettings = false
    @State private var pendingDelete: Project?

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
            ZStack(alignment: .bottomTrailing) {
                Ink.bg.ignoresSafeArea()
                GlowBackdrop(color: Ink.accent, height: 340).opacity(0.5)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        header

                        if store.projects.isEmpty {
                            EmptyStateView(icon: "folder.badge.plus",
                                           title: "Ancora niente",
                                           message: "Un progetto è il contenitore di un lavoro. Dentro ci vanno gli sketch, e dentro gli sketch i ciak.",
                                           actionTitle: "Crea il primo progetto") { startNewProject() }
                                .padding(.top, 40)
                        } else if visibleProjects.isEmpty {
                            Text("Nessun risultato")
                                .font(.system(size: 13))
                                .foregroundStyle(Ink.dim)
                                .padding(.vertical, 60)
                        } else {
                            ForEach(visibleProjects) { project in
                                NavigationLink(value: project.id) {
                                    ProjectCard(project: project,
                                                recent: recentClips(of: project),
                                                store: store)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        store.updateProject(project.id, isArchived: !project.isArchived)
                                    } label: {
                                        Label(project.isArchived ? "Ripristina" : "Archivia",
                                              systemImage: project.isArchived ? "tray.and.arrow.up" : "archivebox")
                                    }
                                    Button(role: .destructive) {
                                        pendingDelete = project
                                    } label: { Label("Elimina progetto", systemImage: "trash") }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .nameAlert("Nuovo progetto", placeholder: "Nome del progetto",
                           isPresented: $showNewProject, text: $newProjectName) {
                    store.addProject(name: newProjectName.trimmingCharacters(in: .whitespaces))
                }

                newProjectButton
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                ProjectDetailView(projectID: id)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .confirmationDialog("Eliminare “\(pendingDelete?.name ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina progetto e video", role: .destructive) {
                if let pendingDelete { store.deleteProject(pendingDelete.id) }
                pendingDelete = nil
            }
            Button("Annulla", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Vengono cancellati anche tutti i video che contiene. Non si torna indietro.")
        }
        .tint(Ink.accent)
    }

    // MARK: Intestazione

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ciak").techFont(10, weight: .bold).foregroundStyle(Ink.accent)
                    Text("Archivio").displayFont(40).foregroundStyle(Ink.text)
                }
                Spacer()
                HStack(spacing: 8) {
                    GlyphButton(icon: "lock.fill") { auth.lock(manual: true) }
                    GlyphButton(icon: "gearshape.fill") { showSettings = true }
                }
                .padding(.top, 6)
            }

            if !store.projects.isEmpty {
                HStack(spacing: 6) {
                    TechChip(text: "\(store.projects.count) progetti", icon: "folder")
                    TechChip(text: "\(store.totalClips) clip", icon: "film")
                    TechChip(text: Formatters.bytes(store.usedBytes), icon: "internaldrive")
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.snappy) { showArchived.toggle() }
                    } label: {
                        TechChip(text: "archiviati",
                                 icon: showArchived ? "eye.fill" : "eye.slash",
                                 tint: showArchived ? Ink.accent : Ink.faint)
                    }
                }
            }

            if store.projects.count > 3 {
                SearchField(text: $search, placeholder: "Cerca progetti e sketch")
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var newProjectButton: some View {
        Button {
            startNewProject()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Ink.accentGradient, in: Circle())
                .shadow(color: Ink.accent.opacity(0.45), radius: 18, y: 8)
        }
        .padding(.trailing, 22)
        .padding(.bottom, 28)
    }

    private func recentClips(of project: Project) -> [Clip] {
        Array(project.sketches
            .flatMap(\.clips)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(3))
    }

    private func startNewProject() {
        newProjectName = ""
        showNewProject = true
    }
}

// MARK: - Scheda progetto

struct ProjectCard: View {
    let project: Project
    let recent: [Clip]
    let store: LibraryStore

    private var accent: Color { Color.project(project.colorIndex) }
    private var cover: Clip? { recent.first }
    private let coverHeight: CGFloat = 74

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Capsule()
                .fill(accent)
                .frame(width: 3, height: 46)
                .shadow(color: accent.opacity(0.8), radius: 6)

            VStack(alignment: .leading, spacing: 8) {
                Text(project.name)
                    .displayFont(23)
                    .foregroundStyle(project.isArchived ? Ink.dim : Ink.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    TechChip(text: "\(project.sketches.count) sketch", tint: accent)
                    TechChip(text: "\(project.clipCount) clip")
                    if project.totalDuration > 0 {
                        TechChip(text: Formatters.duration(project.totalDuration))
                    }
                    if project.isArchived {
                        TechChip(text: "archiviato", icon: "archivebox.fill", tint: Ink.faint)
                    }
                }
            }

            Spacer(minLength: 0)

            // Le ultime riprese, nel loro orientamento vero.
            if !recent.isEmpty {
                HStack(spacing: 4) {
                    ForEach(recent.prefix(2)) { clip in
                        ClipThumbnail(clip: clip, url: store.url(for: clip), cornerRadius: 8)
                            .frame(width: clip.coverWidth(height: coverHeight), height: coverHeight)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Ink.stroke, lineWidth: 1))
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Ink.faint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Ink.surface
                RadialGradient(colors: [accent.opacity(0.22), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 200)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Ink.stroke, lineWidth: 1))
        .opacity(project.isArchived ? 0.55 : 1)
    }
}
