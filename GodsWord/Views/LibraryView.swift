// LibraryView.swift — root screen: the user's downloaded Bible versions.

import SwiftUI
import SwordReader

enum Route: Hashable {
    case books(moduleID: String)
    case chapters(moduleID: String, testament: Int, book: Int)
    case reader(moduleID: String, testament: Int, book: Int, chapter: Int)
}

struct LibraryView: View {
    @Environment(\.moduleStore) private var store
    @EnvironmentObject private var personalData: PersonalData
    @State private var modules: [InstalledModule] = []
    @State private var path = NavigationPath()
    @State private var showingRepository = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if modules.isEmpty {
                    ContentUnavailableView(
                        "No Bibles yet",
                        systemImage: "book.closed",
                        description: Text("Add a Bible version from the CrossWire repository to start reading.")
                    )
                } else {
                    List {
                        ForEach(modules) { mod in
                            NavigationLink(value: Route.books(moduleID: mod.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mod.info.description).font(.headline)
                                    Text(mod.info.id).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("God's Word")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingRepository = true } label: {
                        Label("Add Bible", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingRepository, onDismiss: refresh) {
                RepositoryView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .books(let moduleID):
                    if let mod = modules.first(where: { $0.id == moduleID }) {
                        BooksView(module: mod, path: $path)
                    }
                case .chapters(let moduleID, let testament, let book):
                    if let mod = modules.first(where: { $0.id == moduleID }) {
                        ChaptersView(module: mod, testament: testament, book: book, path: $path)
                    }
                case .reader(let moduleID, let testament, let book, let chapter):
                    if let mod = modules.first(where: { $0.id == moduleID }) {
                        ReaderView(module: mod, testament: testament, book: book, chapter: chapter, path: $path)
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        modules = store.installedModules()
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets {
            let mod = modules[i]
            try? store.delete(mod.id)
            Task { await ModuleLoader.shared.evict(mod.id) }
        }
        refresh()
    }
}
