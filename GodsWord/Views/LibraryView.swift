// LibraryView.swift — root screen: the user's downloaded Bible versions.

import SwiftUI
import SwordReader

/// Drill-down order: versions -> books -> chapters -> reader.
/// The screens share one ReadingHistory, so stepping back always shows the
/// current selection.
enum Route: Hashable {
    case books
    case chapters
    case reader
}

struct LibraryView: View {
    @Environment(\.moduleStore) private var store
    @EnvironmentObject private var personalData: PersonalData
    @State private var modules: [InstalledModule] = []
    @State private var path = NavigationPath()
    @State private var history: ReadingHistory?
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
                            Button {
                                history = ReadingHistory(module: mod)
                                path.append(Route.books)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mod.info.description).font(.headline)
                                        Text(mod.info.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if history?.module.id == mod.id {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
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
                if let history {
                    switch route {
                    case .books:
                        BooksView(history: history, path: $path)
                    case .chapters:
                        ChaptersView(history: history, path: $path)
                    case .reader:
                        ReaderView(history: history, path: $path)
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
