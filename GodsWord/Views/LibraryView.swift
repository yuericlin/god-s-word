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
    @State private var didRestoreLastReading = false

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
                SettingsView(onSelectHistoryEntry: { entry in
                    if let mod = modules.first(where: { $0.id == entry.moduleID }) {
                        history = ReadingHistory(module: mod,
                                                 testament: entry.testament,
                                                 book: entry.book,
                                                 chapter: entry.chapter)
                        path = NavigationPath()
                        path.append(Route.books)
                        path.append(Route.chapters)
                        path.append(Route.reader)
                    }
                })
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
            .edgeNavigation(onForward: {
                // Right-edge swipe left: forward to the book picker (if reading).
                if history != nil {
                    path.append(Route.books)
                }
            })
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        modules = store.installedModules()
        restoreLastReading()
        // Sync private Bibles from iCloud (only if the toggle is enabled).
        if iCloudSync.shared.isEnabled {
            iCloudSync.shared.syncPrivateModulesToLocal()
        }
    }

    /// On first launch, picks up where the user left off.
    private func restoreLastReading() {
        guard !didRestoreLastReading else { return }
        didRestoreLastReading = true
        guard let last = personalData.loadLastReading(),
              last.testament == 1 || last.testament == 2,
              let mod = modules.first(where: { $0.id == last.moduleID })
        else { return }
        let maxBook = last.testament == 1 ? 39 : 27
        guard last.book >= 1 && last.book <= maxBook else { return }
        let h = ReadingHistory(module: mod, testament: last.testament,
                               book: last.book, chapter: max(last.chapter, 1))
        if h.chapter > h.chapterCount {
            h.chapter = max(h.chapterCount, 1)
        }
        history = h
        path.append(Route.books)
        path.append(Route.chapters)
        path.append(Route.reader)
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
