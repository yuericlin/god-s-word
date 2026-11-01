// SourcesSettingsView.swift — Settings > Sources (REQ-SRC-2/3): pick the
// default download source, manage sources, and update the public source
// list on demand. Also Settings > Languages (REQ-LG-1/2).

import SwiftUI
import SwordReader

struct SourcesSettingsView: View {
    @State private var sources: [BibleSource] = []
    @State private var defaultID = BibleSource.crossWire.id
    @State private var addingSource = false
    @State private var editingSource: BibleSource?
    @State private var updating = false
    @State private var updateMessage: String?

    private var store: BibleSourceStore { BibleSourceStore.shared }

    /// Repository sources the download pages can open with.
    private var repositorySources: [BibleSource] {
        sources.filter { $0.repositoryURL != nil }
    }

    var body: some View {
        List {
            Section {
                ForEach(repositorySources) { source in
                    Button {
                        store.defaultSourceID = source.id
                        defaultID = source.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).foregroundStyle(.primary)
                                if let url = source.repositoryURL {
                                    Text(url.host() ?? url.absoluteString)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if source.id == defaultID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Default download source")
            } footer: {
                Text("The “Add Bible” and “Add Commentary” pages open with this source. Changing the source on those pages updates this default too.")
            }

            Section {
                ForEach(sources) { source in
                    Button {
                        editingSource = source
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).foregroundStyle(.primary)
                                Text(kindLabel(for: source))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                Button("Add Source…") { addingSource = true }
            } header: {
                Text("All sources")
            } footer: {
                Text("Public sources come with the app. You can also add your own repository URL or a local folder of private Bibles; only custom sources can be deleted.")
            }

            Section {
                Button {
                    Task { await updatePublicSources() }
                } label: {
                    HStack {
                        Text("Update Public Sources")
                        Spacer()
                        if updating { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(updating)
                Text(publicListStatus)
                    .font(.callout).foregroundStyle(.secondary)
                if let updateMessage {
                    Text(updateMessage).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Public sources")
            } footer: {
                Text("Fetches the latest list of public repositories maintained with the app. Your custom sources are never changed; if an update removes the source a Bible came from, that Bible is listed under CrossWire.")
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(isPresented: $addingSource, onDismiss: reload) {
            SourceEditView()
        }
        .sheet(item: $editingSource, onDismiss: reload) { source in
            SourceEditView(source: source)
        }
    }

    private var publicListStatus: String {
        if let date = store.publicSourcesUpdatedAt {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            return "\(store.publicSources.count) public sources · list updated \(fmt.string(from: date))"
        }
        return "\(store.publicSources.count) public sources · bundled list"
    }

    private func kindLabel(for source: BibleSource) -> String {
        if source.isBuiltIn
            && store.publicSources.contains(where: { $0.id == source.id }) {
            return "Public repository"
        }
        switch source.kind {
        case .repository:
            return source.isBuiltIn ? "Built-in repository" : "Custom repository"
        case .appFolder:
            return "Private Bibles on this device"
        case .folder:
            return "Local folder"
        }
    }

    private func reload() {
        sources = store.allSources
        defaultID = store.defaultSourceID
    }

    private func updatePublicSources() async {
        updating = true
        updateMessage = nil
        defer { updating = false }
        do {
            let count = try await store.refreshPublicSources()
            updateMessage = "Updated: \(count) public sources."
            reload()
        } catch {
            updateMessage = "Couldn't update: \(error.localizedDescription)"
        }
    }
}

/// Display name for a primary language code: "中文" for zh (matching
/// the library's grouping), the system's localized name otherwise,
/// and the code itself when the system has no name for it ("grc").
func languageDisplayName(forPrimaryCode code: String) -> String {
    if code == "zh" { return "中文" }
    return Locale.current.localizedString(forLanguageCode: code) ?? code
}

/// Settings > Languages (REQ-LG-1/2): the languages the user is
/// interested in. When the list is non-empty, the download lists
/// (Bibles, commentaries, dictionaries) show only modules in those
/// languages. The choices come from the catalogs of all repository
/// sources, counted by primary language subtag (a "zh" choice
/// covers zh, zh-Hans, and zh-Hant modules alike).
struct LanguagesSettingsView: View {
    @EnvironmentObject private var personalData: PersonalData
    @State private var counts: [String: Int] = [:]
    @State private var loading = true
    @State private var loadFailed = false
    @State private var partialFailure = false

    private struct LanguageRow: Identifiable {
        let code: String
        let count: Int?
        var id: String { code }
        var name: String { languageDisplayName(forPrimaryCode: code) }
    }

    /// Catalog languages plus any selected language no catalog
    /// currently offers (kept so it can be removed), sorted by name.
    private var rows: [LanguageRow] {
        var codes = Set(counts.keys)
        codes.formUnion(personalData.interestedLanguages)
        return codes
            .map { LanguageRow(code: $0, count: counts[$0]) }
            .sorted { $0.name < $1.name }
    }

    /// The current selection on its own, in the main list's
    /// order — shown at the top so unselecting never means
    /// scrolling the whole catalog list (REQ-LG-4). Available
    /// even while the catalogs load: selected codes are part of
    /// `rows` whether or not a count is known yet.
    private var selectedRows: [LanguageRow] {
        rows.filter { personalData.interestedLanguages.contains($0.code) }
    }

    var body: some View {
        List {
            if !selectedRows.isEmpty {
                Section {
                    ForEach(selectedRows) { row in
                        Button {
                            toggle(row.code)
                        } label: {
                            HStack {
                                Text(row.name).foregroundStyle(.primary)
                                Spacer()
                                if let count = row.count {
                                    Text("\(count)")
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    Button("Clear All") {
                        personalData.interestedLanguages = []
                    }
                } header: {
                    Text("Selected")
                } footer: {
                    Text("Tap a language to remove it. Clear All empties the selection, so every language shows again.")
                }
            }
            Section {
                if loading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading languages from your sources…")
                            .foregroundStyle(.secondary)
                    }
                } else if rows.isEmpty {
                    Text("No languages found. Check your connection and try again.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        Button {
                            toggle(row.code)
                        } label: {
                            HStack {
                                Text(row.name).foregroundStyle(.primary)
                                Spacer()
                                if let count = row.count {
                                    Text("\(count)")
                                        .foregroundStyle(.secondary)
                                }
                                if personalData.interestedLanguages.contains(row.code) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                if loadFailed && !loading {
                    Button("Try Again") { Task { await load() } }
                }
            } header: {
                Text("Languages of interest")
            } footer: {
                Text("When at least one language is chosen, the download lists for Bibles, commentaries, and dictionaries show only modules in those languages. With none chosen, everything shows. The number is how many downloadable modules that language has across your sources.")
            }
            if partialFailure && !loading {
                Section {
                    Text("Some sources couldn't be reached, so their languages aren't listed.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Languages")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func toggle(_ code: String) {
        var selected = personalData.interestedLanguages
        if let i = selected.firstIndex(of: code) {
            selected.remove(at: i)
        } else {
            selected.append(code)
            selected.sort {
                languageDisplayName(forPrimaryCode: $0)
                    < languageDisplayName(forPrimaryCode: $1)
            }
        }
        personalData.interestedLanguages = selected
    }

    /// Fetches every repository source's catalog and counts the
    /// downloadable modules (Bibles, commentaries, dictionaries) per
    /// primary language, de-duplicated by module ID across sources.
    private func load() async {
        loading = true
        loadFailed = false
        partialFailure = false
        defer { loading = false }
        let sources = BibleSourceStore.shared.allSources
            .filter { $0.repositoryURL != nil }
        var idsByLanguage: [String: Set<String>] = [:]
        var failures = 0
        await withTaskGroup(of: (String, [ModuleInfo]?).self) { group in
            for source in sources {
                guard let url = source.repositoryURL else { continue }
                let repo = SwordRepository(name: source.name, baseURL: url)
                group.addTask {
                    do {
                        let (data, _) = try await URLSession.shared.data(
                            from: repo.catalogURL)
                        return (source.id, try SwordRepository.parseCatalog([UInt8](data)))
                    } catch {
                        return (source.id, nil)
                    }
                }
            }
            for await (_, modules) in group {
                guard let modules else { failures += 1; continue }
                for m in modules
                where m.isRenderable || m.isCommentaryRenderable || m.isDictionaryRenderable {
                    let primary = ModuleInfo.primaryLanguage(of: m.language)
                    if !primary.isEmpty {
                        idsByLanguage[primary, default: []].insert(m.id)
                    }
                }
            }
        }
        counts = idsByLanguage.mapValues(\.count)
        if counts.isEmpty { loadFailed = true }
        partialFailure = failures > 0 && !counts.isEmpty
    }
}
