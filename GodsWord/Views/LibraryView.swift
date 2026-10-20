// LibraryView.swift — root screen: the user's Bible versions.
// Versions are segregated by source (CrossWire, Private, then custom
// sources), then by language, then alphabetically. Sources are managed
// here: add (repository URL or local folder), edit any source, delete
// custom ones (their version files are kept).

import SwiftUI
import SwordReader
import UniformTypeIdentifiers

/// Drill-down order: versions -> books -> chapters -> reader.
/// The screens share one ReadingHistory, so stepping back always shows the
/// current selection.
enum Route: Hashable {
    case books
    case chapters
    case reader
}

/// One source section in the library: its versions grouped by language.
private struct SourceGroup: Identifiable {
    let source: BibleSource
    var id: String { source.id }
    let languages: [LanguageGroup]
}

/// One language's versions, alphabetically sorted.
private struct LanguageGroup: Identifiable {
    let id: String          // language code
    let title: String       // "English" / "中文" / …
    let versions: [BibleVersion]
}

struct LibraryView: View {
    @Environment(\.moduleStore) private var store
    @EnvironmentObject private var personalData: PersonalData
    @State private var groups: [SourceGroup] = []
    @State private var path = NavigationPath()
    @State private var history: ReadingHistory?
    @State private var showingRepository = false
    @State private var showingSettings = false
    @State private var editingSource: BibleSource?
    @State private var addingSource = false
    @State private var importTarget: BibleSource?
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var didRestoreLastReading = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if groups.allSatisfy({ $0.languages.isEmpty }) {
                    ContentUnavailableView(
                        "No Bibles yet",
                        systemImage: "book.closed",
                        description: Text("Add a Bible version from a repository, or import a private Bible, to start reading.")
                    )
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.languages) { lang in
                                    Text(lang.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    ForEach(lang.versions) { version in
                                        versionRow(version)
                                    }
                                }
                                if group.source.isLocal {
                                    Button {
                                        importTarget = group.source
                                        showingImporter = true
                                    } label: {
                                        Label("Import a private Bible…", systemImage: "square.and.arrow.down")
                                    }
                                }
                            } header: {
                                sourceHeader(group.source)
                            }
                        }
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
                    Menu {
                        Button {
                            showingRepository = true
                        } label: {
                            Label("Download Bible…", systemImage: "arrow.down.circle")
                        }
                        Button {
                            addingSource = true
                        } label: {
                            Label("Add Source…", systemImage: "plus.circle")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingRepository, onDismiss: refresh) {
                RepositoryView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(onSelectHistoryEntry: { entry in
                    if let version = allVersions().first(where: { $0.id == entry.moduleID }) {
                        history = ReadingHistory(version: version,
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
            .sheet(isPresented: $addingSource, onDismiss: refresh) {
                SourceEditView()
            }
            .sheet(item: $editingSource, onDismiss: refresh) { source in
                SourceEditView(source: source)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json, .gzip]) { result in
                if let target = importTarget {
                    importPrivateBible(result, into: target)
                }
                importTarget = nil
            }
            .alert("Import failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importError ?? "")
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

    /// Source section header: name, public base URL when there is one, and
    /// an edit button (all sources are editable).
    private func sourceHeader(_ source: BibleSource) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                if let url = source.repositoryURL {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            Spacer()
            Button {
                editingSource = source
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func versionRow(_ version: BibleVersion) -> some View {
        Button {
            history = ReadingHistory(version: version)
            path.append(Route.books)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(version.displayName).font(.headline)
                    Text(version.id).font(.caption).foregroundStyle(.secondary)
                }
                if history?.version.id == version.id {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                delete(version)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// All versions flat, for history-entry lookup.
    private func allVersions() -> [BibleVersion] {
        groups.flatMap { $0.languages.flatMap(\.versions) }
    }

    private func refresh() {
        let store = BibleSourceStore.shared
        let installed = self.store.installedModules()
        var newGroups: [SourceGroup] = []
        for source in store.allSources {
            let versions: [BibleVersion]
            switch source.kind {
            case .repository:
                versions = installed
                    .filter { store.sourceID(forModule: $0.id) == source.id }
                    .map(BibleVersion.sword)
            case .appFolder, .folder:
                versions = loadPrivateBibles(from: source).map(BibleVersion.private)
            }
            newGroups.append(makeGroup(source: source, versions: versions))
        }
        groups = newGroups
        restoreLastReading()
        // Ensure iCloud folders exist (if enabled) and sync private Bibles.
        iCloudSync.shared.ensureFoldersOnLaunchIfEnabled()
        if iCloudSync.shared.isEnabled {
            iCloudSync.shared.syncPrivateModulesToLocal()
        }
    }

    /// Private Bibles in a local source's folder (security-scoped when
    /// it's a user-picked folder).
    private func loadPrivateBibles(from source: BibleSource) -> [PrivateBible] {
        guard let dir = source.resolvedFolder else { return [] }
        let scoped = source.needsSecurityScope && dir.startAccessingSecurityScopedResource()
        defer { if scoped { dir.stopAccessingSecurityScopedResource() } }
        return PrivateBibleStore.loadAll(in: dir)
    }

    private func makeGroup(source: BibleSource, versions: [BibleVersion]) -> SourceGroup {
        let byLang = Dictionary(grouping: versions, by: \.language)
        let langs = byLang.keys.sorted().map { code -> LanguageGroup in
            let vs = (byLang[code] ?? []).sorted { $0.displayName < $1.displayName }
            return LanguageGroup(id: code,
                                 title: vs.first?.languageTitle ?? code,
                                 versions: vs)
        }
        return SourceGroup(source: source, languages: langs)
    }

    /// Import a private Bible JSON (.json or .json.gz) into a local source's folder.
    private func importPrivateBible(_ result: Result<URL, Error>, into source: BibleSource) {
        let url: URL
        switch result {
        case .success(let u): url = u
        case .failure(let e):
            importError = e.localizedDescription
            return
        }
        guard let dir = source.resolvedFolder else {
            importError = "That source has no folder."
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Couldn't open the file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let bible = PrivateBibleStore.load(from: url) else {
            importError = "That file isn't a valid private Bible JSON."
            return
        }
        let scoped = source.needsSecurityScope && dir.startAccessingSecurityScopedResource()
        defer { if scoped { dir.stopAccessingSecurityScopedResource() } }
        do {
            try PrivateBibleStore.save(bible, into: dir)
        } catch {
            importError = error.localizedDescription
            return
        }
        refresh()
    }

    /// On first launch, picks up where the user left off.
    private func restoreLastReading() {
        guard !didRestoreLastReading else { return }
        didRestoreLastReading = true
        guard let last = personalData.loadLastReading(),
              last.testament == 1 || last.testament == 2,
              let version = allVersions().first(where: { $0.id == last.moduleID })
        else { return }
        let maxBook = last.testament == 1 ? 39 : 27
        guard last.book >= 1 && last.book <= maxBook else { return }
        let h = ReadingHistory(version: version, testament: last.testament,
                               book: last.book, chapter: max(last.chapter, 1))
        if h.chapter > h.chapterCount {
            h.chapter = max(h.chapterCount, 1)
        }
        history = h
        path.append(Route.books)
        path.append(Route.chapters)
        path.append(Route.reader)
    }

    private func delete(_ version: BibleVersion) {
        switch version {
        case .sword(let mod):
            try? store.delete(mod.id)
            Task { await ModuleLoader.shared.evict(mod.id) }
        case .private(let bible):
            // Remove from whichever local source folder holds it.
            for source in BibleSourceStore.shared.allSources where source.isLocal {
                guard let dir = source.resolvedFolder else { continue }
                let scoped = source.needsSecurityScope && dir.startAccessingSecurityScopedResource()
                for ext in ["json", "json.gz"] {
                    try? FileManager.default.removeItem(
                        at: dir.appendingPathComponent("\(bible.id).\(ext)"))
                }
                if scoped { dir.stopAccessingSecurityScopedResource() }
            }
        }
        if history?.version.id == version.id { history = nil }
        refresh()
    }
}
