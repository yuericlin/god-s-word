// SettingsView.swift — reading preferences, Google Drive backup, about.

import SwiftUI
import SwordReader
import UniformTypeIdentifiers

struct SettingsView: View {
    /// The live reading, when Settings is opened over the reader
    /// or over the Library's current book; the Current version
    /// option (REQ-LG-3) switches it in place. Nil on a fresh
    /// launch, where the option works on the saved last reading.
    var history: ReadingHistory? = nil

    @EnvironmentObject private var personalData: PersonalData
    @EnvironmentObject private var driveBackup: GoogleDriveBackup
    @Environment(\.moduleStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var message: String?
    @State private var showingRestoreConfirm = false
    @State private var pendingRestore: BackupPayload?
    @State private var showingImporter = false
    @State private var showingExportShare = false
    @State private var exportFolder: URL?
    /// What the manual backup spinner says while exporting/importing.
    @State private var progressText = ""

    /// The Google Drive backup section is hidden for now (the
    /// feature and its code stay in place). Flip to show it again.
    private static let showGoogleDriveBackup = false

    /// The iCloud section is hidden for now, the same way; only
    /// Manual backup (export/import) shows. Flip to show it again.
    private static let showICloudSync = false

    var body: some View {
        NavigationStack {
            List {
                Section("Reading") {
                    ReadingSettingsView()
                }

                Section("Bible") {
                    NavigationLink {
                        LanguagesSettingsView()
                    } label: {
                        HStack {
                            Text("Languages")
                            Spacer()
                            Text(personalData.interestedLanguages.isEmpty
                                 ? "All languages"
                                 : personalData.interestedLanguages
                                    .map { languageDisplayName(forPrimaryCode: $0) }
                                    .joined(separator: ", "))
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        CurrentVersionPicker(history: history)
                    } label: {
                        HStack {
                            Text("Current version")
                            Spacer()
                            Text(currentVersionSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        CompareVersionsPicker()
                    } label: {
                        HStack {
                            Text("Compare versions")
                            Spacer()
                            Text(personalData.compareVersionIDs.isEmpty
                                 ? "Current only"
                                 : "\(personalData.compareVersionIDs.count) chosen")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        SourcesSettingsView()
                    } label: {
                        HStack {
                            Text("Sources")
                            Spacer()
                            Text(BibleSourceStore.shared.source(withID: BibleSourceStore.shared.defaultSourceID)?.name ?? "CrossWire")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Auxiliary") {
                    NavigationLink {
                        PanelModePicker()
                    } label: {
                        HStack {
                            Text("Current mode")
                            Spacer()
                            Text(currentModeSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        CommentaryModulePicker()
                    } label: {
                        HStack {
                            Text("Current commentary")
                            Spacer()
                            Text(personalData.commentaryModuleID.isEmpty
                                 ? "Automatic"
                                 : personalData.commentaryModuleID)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        ParallelSettingsView(history: history)
                    } label: {
                        HStack {
                            Text("Current parallel mode")
                            Spacer()
                            Text(personalData.parallelSyncMode ? "Sync" : "Separate")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        PanelHeightSettingsView()
                    } label: {
                        HStack {
                            Text("Panel height")
                            Spacer()
                            Text("\(personalData.panelHeightPercent)%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        DictionarySettingsView()
                    } label: {
                        HStack {
                            Text("Dictionary")
                            Spacer()
                            Text(dictionarySummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        StrongsFallbackPicker()
                    } label: {
                        HStack {
                            Text("Strong's fallback version")
                            Spacer()
                            Text(personalData.strongsFallbackVersionID.isEmpty
                                 ? "Automatic"
                                 : personalData.strongsFallbackVersionID)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await doExport() }
                    } label: {
                        Text("Export Data")
                    }
                    .disabled(working)
                    Button("Import Data") {
                        showingImporter = true
                    }
                    .disabled(working)
                    if working {
                        ProgressView(progressText).controlSize(.small)
                    }
                    if let msg = message,
                       msg.hasPrefix("Export") || msg.hasPrefix("Import") {
                        Text(msg).font(.callout).foregroundStyle(.secondary)
                    }

                    if Self.showICloudSync {
                        Toggle("iCloud Sync", isOn: Binding(
                            get: { iCloudSync.shared.isEnabled },
                            set: { newValue in
                                iCloudSync.shared.isEnabled = newValue
                                if newValue {
                                    // Immediately sync all data so the JSON files
                                    // (and the folder) appear in iCloud Drive.
                                    personalData.syncAllToiCloud(
                                        repositoryURL: "https://crosswire.org/ftpmirror/pub/sword/raw",
                                        installedModuleIDs: store.installedModules().map { $0.id })
                                }
                            }
                        ))
                        .disabled(!iCloudSync.shared.isAvailable)
                        if !iCloudSync.shared.isAvailable {
                            Text("Sign in to iCloud in the iOS Settings app to enable sync. " +
                                 "The developer must also enable the iCloud capability in Xcode " +
                                 "(Signing & Capabilities).")
                                .font(.callout).foregroundStyle(.secondary)
                        } else if iCloudSync.shared.isEnabled {
                            Text("Bookmarks, notes, settings, and history sync as JSON to the god-s-word folder in iCloud Drive. Private Bible versions go in god-s-word/private-repo/. " +
                                 "The folder appears in the Files app under iCloud Drive once sync is active.")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("Enable to sync your data to the god-s-word folder in iCloud Drive.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }

                    if Self.showGoogleDriveBackup {
                        if !GoogleDriveBackup.isConfigured {
                            Text("Google sign-in isn't configured in this build yet. " +
                                 "Add your GoogleOAuth.plist (see README) to enable Drive backup.")
                                .font(.callout).foregroundStyle(.secondary)
                        } else if driveBackup.isSignedIn {
                            HStack {
                                Text("Signed in")
                                Spacer()
                                Text(driveBackup.accountEmail ?? "").foregroundStyle(.secondary)
                            }
                            Button("Back up now") { Task { await doBackup() } }
                                .disabled(working)
                            Button("Restore from Drive") { Task { await doRestore() } }
                                .disabled(working)
                            Button("Sign out", role: .destructive) { driveBackup.signOut() }
                        } else {
                            Text("Back up your reading data — text size, layout, reading positions, " +
                                 "and which Bibles you installed — to a private folder in your " +
                                 "Google Drive. Nothing is uploaded until you sign in and tap Back up.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Sign in with Google") { Task { await doSignIn() } }
                                .disabled(working)
                        }
                        if working { ProgressView().controlSize(.small) }
                        if let message {
                            Text(message).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Export saves your data as JSON files, plus every downloaded module (Bibles, commentaries, dictionaries) as a .zip in the modules folder, to On My iPhone > GodsWord > god-s-word-export/. Share the folder via AirDrop or Files. After a reinstall, Import and select the JSON files and module .zip files to restore everything without downloading again. Modules already installed are skipped.")
                }

                Section("About") {
                    HStack { Text("Version"); Spacer(); Text(appVersion).foregroundStyle(.secondary) }
                    Text("God's Word is an independent reader, not affiliated with or endorsed by CrossWire Bible Society, the SWORD Project, Apple, Google, or any Bible publisher.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("This app includes no Bible text. Bibles and lexicons are downloaded by you from the CrossWire Bible Society module repository (crosswire.org) or imported by you. Each belongs to its copyright holder; check each module's license on crosswire.org before sharing or publishing it. Use is at your own responsibility.")
                        .font(.callout).foregroundStyle(.secondary)
                    NavigationLink("Licenses and notices") {
                        LicenseNoticeView()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.json, .zip],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task { await doImport(urls) }
                case .failure(let error):
                    message = "Import failed: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showingExportShare) {
                if let folder = exportFolder {
                    ShareSheet(items: [folder])
                }
            }
            .confirmationDialog("Restore backup?",
                                isPresented: $showingRestoreConfirm,
                                titleVisibility: .visible) {
                Button("Restore", role: .destructive) {
                    if let payload = pendingRestore {
                        Task { await applyRestore(payload) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces your text size, layout, reading positions, and installed-Bible list with the backup. Bible texts will be re-downloaded as needed.")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// The Current version row's value (REQ-LG-3): the version
    /// being read, else the saved last reading's, else "None".
    private var currentVersionSummary: String {
        history?.version.id
            ?? personalData.loadLastReading()?.moduleID
            ?? "None"
    }

    /// The Dictionary row's value: "Automatic" when neither lexicon
    /// is chosen, otherwise the chosen module IDs.
    private var dictionarySummary: String {
        let hebrew = personalData.dictionaryHebrewID
        let greek = personalData.dictionaryGreekID
        if hebrew.isEmpty && greek.isEmpty { return "Automatic" }
        return [hebrew, greek].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The Current mode row's value: the auxiliary panel's
    /// remembered start mode (REQ-AP-21), Notes when unset.
    private var currentModeSummary: String {
        (AuxiliaryPanelView.PanelTab(rawValue: personalData.panelTab) ?? .notes).rawValue
    }

    /// Manual export (REQ-BK-7): the JSON data files, every installed
    /// module as its own package zip in `modules/`, and every private
    /// version as a plain JSON file in `private/`.
    private func doExport() async {
        working = true; message = nil
        progressText = "Exporting your data…"
        defer { working = false }
        do {
            let folder = try personalData.exportToDocuments()
            progressText = "Packing downloaded modules…"
            let modulesFolder = folder.appendingPathComponent("modules", isDirectory: true)
            let store = self.store
            let count = try await Task.detached(priority: .userInitiated) {
                try store.exportPackages(to: modulesFolder)
            }.value
            progressText = "Packing private versions…"
            let privateFolder = folder.appendingPathComponent("private", isDirectory: true)
            let privateCount = try await Task.detached(priority: .userInitiated) {
                try PrivateBibleStore.exportCopies(from: PrivateBibleStore.baseDir,
                                                   to: privateFolder)
            }.value
            exportFolder = folder
            showingExportShare = true
            message = "Exported your data and \(count) module(s)"
                + (privateCount > 0 ? " and \(privateCount) private version(s)" : "")
                + " to Documents/god-s-word-export/"
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Manual import: JSON files restore data; module .zip files are
    /// installed unless that module is already installed; files that
    /// load as private versions restore through the private store
    /// (REQ-BK-7).
    private func doImport(_ urls: [URL]) async {
        working = true; message = nil
        progressText = "Importing…"
        defer { working = false }
        let zips = urls.filter { $0.pathExtension.lowercased() == "zip" }
        let others = urls.filter { $0.pathExtension.lowercased() != "zip" }

        let scoped = others.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

        // A picked file that loads as a private version belongs to
        // the private store, not the personal-data importer.
        var dataURLs: [URL] = []
        var privateURLs: [URL] = []
        for url in others {
            if PrivateBibleStore.load(from: url) != nil {
                privateURLs.append(url)
            } else {
                dataURLs.append(url)
            }
        }

        do {
            if !dataURLs.isEmpty { try personalData.importFrom(urls: dataURLs) }
        } catch {
            message = "Import failed: \(error.localizedDescription)"
            return
        }

        let store = self.store
        let have = Set(store.installedModules().map { $0.id })
        var installed = 0, skipped = 0
        var failed: [String] = []
        for (i, url) in zips.enumerated() {
            let name = url.deletingPathExtension().lastPathComponent
            if have.contains(name) { skipped += 1; continue }
            progressText = "Installing modules (\(i + 1) of \(zips.count))…"
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return false }
                return (try? store.install(packageData: [UInt8](data))) != nil
            }.value
            if ok { installed += 1 } else { failed.append(name) }
        }

        var privateRestored = 0, privateSkipped = 0
        if !privateURLs.isEmpty {
            let r = PrivateBibleStore.restoreCopies(from: privateURLs,
                                                    into: PrivateBibleStore.baseDir)
            privateRestored = r.restored
            privateSkipped = r.skipped
        }

        var parts = ["\(dataURLs.count) data file(s)"]
        if !zips.isEmpty {
            parts.append("\(installed) module(s) installed")
            if skipped > 0 { parts.append("\(skipped) already installed") }
        }
        if !privateURLs.isEmpty {
            parts.append("\(privateRestored) private version(s) restored")
            if privateSkipped > 0 { parts.append("\(privateSkipped) private already installed") }
        }
        var text = "Import complete: " + parts.joined(separator: ", ") + "."
        if !failed.isEmpty {
            text += " Couldn't install: " + failed.joined(separator: ", ") + "."
        }
        message = text
    }

    private func doSignIn() async {
        working = true; message = nil
        defer { working = false }
        do {
            try await driveBackup.signIn()
            message = "Signed in."
        } catch {
            message = error.localizedDescription
        }
    }

    private func doBackup() async {
        working = true; message = nil
        defer { working = false }
        do {
            let payload = personalData.makeBackup(installedModuleIDs: store.installedModules().map { $0.id })
            let date = try await driveBackup.backup(payload)
            let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
            message = "Backed up \(fmt.string(from: date))."
        } catch {
            message = error.localizedDescription
        }
    }

    private func doRestore() async {
        working = true; message = nil
        defer { working = false }
        do {
            guard let payload = try await driveBackup.restore() else {
                message = "No backup found in Drive."
                return
            }
            pendingRestore = payload
            showingRestoreConfirm = true
        } catch {
            message = error.localizedDescription
        }
    }

    private func applyRestore(_ payload: BackupPayload) async {
        personalData.applyBackup(payload)
        // Re-install any missing modules in the background.
        let installed = Set(store.installedModules().map { $0.id })
        let missing = payload.installedModuleIDs.filter { !installed.contains($0) }
        if missing.isEmpty {
            message = "Backup restored."
            return
        }
        message = "Restoring \(missing.count) Bible(s)…"
        let repo = SwordRepository(name: "CrossWire",
                                   baseURL: URL(string: "https://crosswire.org/ftpmirror/pub/sword/raw")!)
        for id in missing {
            do {
                let (data, _) = try await URLSession.shared.data(from: repo.packageURL(for: id))
                try store.install(packageData: [UInt8](data), moduleID: id)
            } catch {
                message = "Restored settings, but couldn't re-download \(id)."
                return
            }
        }
        message = "Backup restored."
    }
}

/// Wraps UIActivityViewController for sharing the export folder.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {}
}

/// One source section on the Current Version page: its versions
/// grouped by language — the Library's grouping (REQ-LG-3).
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

/// Settings > Bible version > Current version (REQ-LG-3): pick
/// the version being read from the installed versions, grouped
/// by source and language like the Library, or download a new
/// one. The list refreshes when the download page closes and
/// after an import.
struct CurrentVersionPicker: View {
    /// The live reading to switch in place; nil on a fresh
    /// launch, where the pick updates the saved last reading.
    let history: ReadingHistory?

    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.moduleStore) private var store
    @State private var groups: [SourceGroup] = []
    @State private var currentID = ""
    @State private var showingDownload = false
    @State private var showingImporter = false
    @State private var importTarget: BibleSource?
    @State private var importError: String?

    var body: some View {
        List {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
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
                } footer: {
                    if index == 0 {
                        Text("The version shown in the reader. Private imports appear here too.")
                    }
                }
            }
            Section {
                Button("Download a New Version…") { showingDownload = true }
            } footer: {
                Text("New versions download from the Add Bible page, the same repositories the Library uses.")
            }
        }
        .navigationTitle("Current Version")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .sheet(isPresented: $showingDownload, onDismiss: refresh) {
            RepositoryView()
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
    }

    /// Switches the reading to `version`, keeping the place
    /// being read — the chapter clamps to the new version's
    /// range, like the reader's own version picker. With no
    /// reading open, the pick becomes the saved last reading so
    /// the next book opened uses it.
    private func pick(_ version: BibleVersion) {
        currentID = version.id
        if let history {
            history.version = version
            let count = history.chapterCount
            if history.chapter > count {
                history.chapter = max(count, 1)
            }
        } else if let last = personalData.loadLastReading() {
            personalData.saveLastReading(moduleID: version.id,
                                         testament: last.testament,
                                         book: last.book,
                                         chapter: last.chapter)
        } else {
            personalData.saveLastReading(moduleID: version.id,
                                         testament: 1, book: 1, chapter: 1)
        }
    }

    /// Rebuild the source groups the way the Library does
    /// (REQ-LG-3): repository sources contribute their downloaded
    /// modules, local sources their private Bibles.
    private func refresh() {
        let sourceStore = BibleSourceStore.shared
        let installed = store.installedModules()
        var newGroups: [SourceGroup] = []
        for source in sourceStore.allSources {
            let versions: [BibleVersion]
            switch source.kind {
            case .repository:
                versions = installed
                    .filter { sourceStore.sourceID(forModule: $0.id) == source.id }
                    .filter { !$0.info.isCommentary && !$0.info.isDictionary }
                    .map(BibleVersion.sword)
            case .appFolder, .folder:
                versions = loadPrivateBibles(from: source).map(BibleVersion.private)
            }
            newGroups.append(makeGroup(source: source, versions: versions))
        }
        groups = newGroups
        currentID = history?.version.id
            ?? personalData.loadLastReading()?.moduleID ?? ""
    }

    /// Private Bibles in a local source's folder (security-scoped
    /// when it's a user-picked folder).
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

    /// Source section header: name, and the public base URL when
    /// there is one — the Library's header without its edit
    /// button (source editing stays in the Library and Sources).
    private func sourceHeader(_ source: BibleSource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(source.name)
            if let url = source.repositoryURL {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    /// A version row as the Library shows it — display name over
    /// ID, checkmarked when it is the version being read — except
    /// that tapping picks it as the current version.
    private func versionRow(_ version: BibleVersion) -> some View {
        Button {
            pick(version)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(version.displayName).font(.headline)
                    Text(version.id).font(.caption).foregroundStyle(.secondary)
                }
                if currentID == version.id {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
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
}

/// The auxiliary panel's start mode (REQ-AP-21): the mode
/// the panel opens with, restored from `PersonalData.panelTab`.
/// The panel writes the same setting whenever its mode
/// changes, so a pick here and a change there stay in sync.
struct PanelModePicker: View {
    @EnvironmentObject private var personalData: PersonalData

    private var current: AuxiliaryPanelView.PanelTab {
        AuxiliaryPanelView.PanelTab(rawValue: personalData.panelTab) ?? .notes
    }

    var body: some View {
        List {
            Section {
                ForEach(AuxiliaryPanelView.PanelTab.allCases, id: \.self) { mode in
                    Button {
                        personalData.panelTab = mode.rawValue
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if mode == current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            } footer: {
                Text("The mode the auxiliary panel opens with. Switching modes in the panel itself updates this too.")
            }
        }
        .navigationTitle("Current Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The auxiliary panel's height (REQ-AP-22): a slider from
/// 25% to 50% of the reader's height, snapping to the 5%
/// stops, writing `PersonalData.panelHeightPercent`. The
/// one height serves every mode — the panel's content
/// height is computed from it whichever mode is showing.
struct PanelHeightSettingsView: View {
    @EnvironmentObject private var personalData: PersonalData

    private var percent: Binding<Double> {
        Binding(
            get: { Double(personalData.panelHeightPercent) },
            set: { personalData.panelHeightPercent =
                PersonalData.clampedPanelHeightPercent(Int($0.rounded())) }
        )
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Text("\(personalData.panelHeightPercent)%")
                        .font(.largeTitle)
                    Slider(value: percent, in: 25...50, step: 5)
                    HStack {
                        Text("25%")
                        Spacer()
                        Text("50%")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } footer: {
                Text("The auxiliary panel's height as a share of the reading view — the same for every mode. The panel uses the new height as soon as you return to it.")
            }
        }
        .navigationTitle("Panel Height")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Parallel tab's remembered settings (REQ-PA-8): the mode
/// and each mode's version. These are the same PersonalData
/// values the panel's own sheets edit, so a change here shows
/// there and the other way around. A version row's checkmark
/// marks the version in effect: the remembered choice, or —
/// while none is remembered (or it was uninstalled) — the
/// REQ-PA-7 fallback the panel itself resolves.
struct ParallelSettingsView: View {
    /// The live reading, for the fallback's "isn't the one
    /// being read"; nil on a fresh launch, where the saved
    /// last reading stands in.
    let history: ReadingHistory?

    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.moduleStore) private var store
    @State private var versions: [BibleVersion] = []

    var body: some View {
        List {
            Section {
                Picker("Mode", selection: modeBinding) {
                    Text("Sync").tag(true)
                    Text("Separate").tag(false)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Mode")
            } footer: {
                Text("Sync shows the chapter being read in another version, the two views scrolling together. Separate shows any version, book, and chapter, scrolling on its own.")
            }

            versionSection(title: "Sync version",
                           storedID: personalData.parallelSyncVersionID) { version in
                personalData.parallelSyncVersionID = version.id
            }

            versionSection(title: "Separate version",
                           storedID: personalData.parallelSeparateVersionID) { version in
                personalData.parallelSeparateVersionID = version.id
            }
        }
        .navigationTitle("Parallel")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            versions = BibleVersion.allInstalled(in: store)
        }
    }

    private var modeBinding: Binding<Bool> {
        Binding(get: { personalData.parallelSyncMode },
                set: { personalData.parallelSyncMode = $0 })
    }

    /// The version being read, for the fallback rule.
    private var readingVersionID: String {
        history?.version.id
            ?? personalData.loadLastReading()?.moduleID ?? ""
    }

    /// The version in effect for a stored choice (REQ-PA-7).
    private func effectiveID(storedID: String) -> String? {
        if versions.contains(where: { $0.id == storedID }) {
            return storedID
        }
        return versions.first { $0.id != readingVersionID }?.id
            ?? versions.first?.id
    }

    /// One checkmark version list, in the Current Version
    /// picker's rows: short label, display name under it when
    /// the two differ, checkmark on the version in effect.
    private func versionSection(title: String, storedID: String,
                                pick: @escaping (BibleVersion) -> Void) -> some View {
        Section {
            ForEach(versions) { version in
                Button {
                    pick(version)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.shortLabel)
                                .foregroundStyle(.primary)
                            if version.displayName != version.shortLabel {
                                Text(version.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if effectiveID(storedID: storedID) == version.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        } header: {
            Text(title)
        }
    }
}
