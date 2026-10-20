// LibraryView.swift — root screen: the user's Bible versions.
// Versions are segregated by source (CrossWire, then Private), then by
// language, then alphabetically. Private versions are imported from JSON
// files; public ones show their source base URL.

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
    let id: String          // "CrossWire" / "Private"
    let sourceURL: URL?     // public base URL; nil for private
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
                        description: Text("Add a Bible version from the CrossWire repository to start reading.")
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
                                        versionRow(version, in: group)
                                    }
                                }
                                if group.id == "Private" {
                                    Button {
                                        showingImporter = true
                                    } label: {
                                        Label("Import a private Bible…", systemImage: "square.and.arrow.down")
                                    }
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.id)
                                    if let url = group.sourceURL {
                                        Text(url.absoluteString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textCase(nil)
                                    }
                                }
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
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.json, .gzip]) { result in
                importPrivateBible(result)
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

    private func versionRow(_ version: BibleVersion, in group: SourceGroup) -> some View {
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
        let sword = store.installedModules().map(BibleVersion.sword)
        let privates = PrivateBibleStore.loadAll().map(BibleVersion.private)
        groups = [makeGroup(id: "CrossWire", versions: sword),
                  makeGroup(id: "Private", versions: privates)]
        restoreLastReading()
        // Ensure iCloud folders exist (if enabled) and sync private Bibles.
        iCloudSync.shared.ensureFoldersOnLaunchIfEnabled()
        if iCloudSync.shared.isEnabled {
            iCloudSync.shared.syncPrivateModulesToLocal()
        }
    }

    private func makeGroup(id: String, versions: [BibleVersion]) -> SourceGroup {
        let byLang = Dictionary(grouping: versions, by: \.language)
        let langs = byLang.keys.sorted().map { code -> LanguageGroup in
            let vs = (byLang[code] ?? []).sorted { $0.displayName < $1.displayName }
            return LanguageGroup(id: code,
                                 title: vs.first?.languageTitle ?? code,
                                 versions: vs)
        }
        let url = versions.first?.sourceURL
        return SourceGroup(id: id, sourceURL: url, languages: langs)
    }

    /// Import a private Bible JSON (.json or .json.gz) picked by the user.
    private func importPrivateBible(_ result: Result<URL, Error>) {
        let url: URL
        switch result {
        case .success(let u): url = u
        case .failure(let e):
            importError = e.localizedDescription
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
        do {
            try PrivateBibleStore.save(bible)
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
            let fm = FileManager.default
            for ext in ["json", "json.gz"] {
                let url = PrivateBibleStore.baseDir
                    .appendingPathComponent("\(bible.id).\(ext)")
                try? fm.removeItem(at: url)
            }
        }
        if history?.version.id == version.id { history = nil }
        refresh()
    }
}
