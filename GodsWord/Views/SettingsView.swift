// SettingsView.swift — reading preferences, Google Drive backup, about.

import SwiftUI
import SwordReader
import UniformTypeIdentifiers

struct SettingsView: View {
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

                Section {
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
                } header: {
                    Text("Languages")
                } footer: {
                    Text("When languages are chosen here, the download lists for Bibles, commentaries, and dictionaries show only modules in those languages.")
                }

                Section {
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
                } header: {
                    Text("Compare")
                } footer: {
                    Text("The Compare action on selected verses shows them in the version you are reading plus the versions chosen here.")
                }

                Section {
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
                } header: {
                    Text("Dictionary")
                } footer: {
                    Text("The dictionaries Strong's definitions come from, one for Hebrew and one for Greek. More dictionaries download from the same repositories as Bibles.")
                }

                Section {
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
                } header: {
                    Text("Strong's")
                } footer: {
                    Text("When the version you are reading has no Strong's numbers, the panel's Strong's tab renders the selected verse from this version instead.")
                }

                Section {
                    NavigationLink {
                        CommentaryModulePicker()
                    } label: {
                        HStack {
                            Text("Commentary")
                            Spacer()
                            Text(personalData.commentaryModuleID.isEmpty
                                 ? "Automatic"
                                 : personalData.commentaryModuleID)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Auxiliary panel")
                } footer: {
                    Text("The panel below the reader has Notes, Commentary, and Strong's tabs. Commentary entries show for the book, chapter, or verse being read.")
                }

                Section {
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
                } header: {
                    Text("Sources")
                } footer: {
                    Text("Public repositories you can download Bibles and commentaries from. Pick the default, add your own, or update the public list.")
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
                } header: {
                    Text("Manual backup")
                } footer: {
                    Text("Export saves your data as JSON files, plus every downloaded module (Bibles, commentaries, dictionaries) as a .zip in the modules folder, to On My iPhone > GodsWord > god-s-word-export/. Share the folder via AirDrop or Files. After a reinstall, Import and select the JSON files and module .zip files to restore everything without downloading again. Modules already installed are skipped.")
                }

                if Self.showICloudSync {
                Section {
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
                } header: {
                    Text("iCloud")
                }
                }


                if Self.showGoogleDriveBackup {
                Section {
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
                } header: {
                    Text("Google Drive backup")
                }
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

    /// The Dictionary row's value: "Automatic" when neither lexicon
    /// is chosen, otherwise the chosen module IDs.
    private var dictionarySummary: String {
        let hebrew = personalData.dictionaryHebrewID
        let greek = personalData.dictionaryGreekID
        if hebrew.isEmpty && greek.isEmpty { return "Automatic" }
        return [hebrew, greek].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Manual export (REQ-BK-6): the JSON data files, and every installed
    /// module as its own package zip in `modules/`.
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
            exportFolder = folder
            showingExportShare = true
            message = "Exported your data and \(count) module(s) to Documents/god-s-word-export/"
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Manual import: JSON files restore data; module .zip files are
    /// installed unless that module is already installed.
    private func doImport(_ urls: [URL]) async {
        working = true; message = nil
        progressText = "Importing…"
        defer { working = false }
        let zips = urls.filter { $0.pathExtension.lowercased() == "zip" }
        let others = urls.filter { $0.pathExtension.lowercased() != "zip" }

        let scoped = others.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            if !others.isEmpty { try personalData.importFrom(urls: others) }
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

        var parts = ["\(others.count) data file(s)"]
        if !zips.isEmpty {
            parts.append("\(installed) module(s) installed")
            if skipped > 0 { parts.append("\(skipped) already installed") }
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
