// SettingsView.swift — reading preferences, Google Drive backup, about.

import SwiftUI
import SwordReader

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
    /// Called when the user taps a history entry; the presenter navigates.
    var onSelectHistoryEntry: ((HistoryEntry) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section("Reading") {
                    ReadingSettingsView()
                }

                Section("History") {
                    NavigationLink {
                        HistoryView(onSelect: { entry in
                            dismiss()
                            onSelectHistoryEntry?(entry)
                        })
                    } label: {
                        HStack {
                            Text("Reading History")
                            Spacer()
                            if !personalData.historyLog.isEmpty {
                                Text("\(personalData.historyLog.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

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

                Section {
                    Button("Export Data") {
                        do {
                            exportFolder = try personalData.exportToDocuments()
                            showingExportShare = true
                            message = "Exported to Documents/god-s-word-export/"
                        } catch {
                            message = "Export failed: \(error.localizedDescription)"
                        }
                    }
                    Button("Import Data") {
                        showingImporter = true
                    }
                    if let message, message.hasPrefix("Export") || message.hasPrefix("Import") {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Manual backup")
                } footer: {
                    Text("Export saves JSON files to On My iPhone > GodsWord > god-s-word-export/. Share them via AirDrop or Files. Import restores from selected JSON files.")
                }

                Section {
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

                Section("About") {
                    HStack { Text("Version"); Spacer(); Text(appVersion).foregroundStyle(.secondary) }
                    Text("Bible texts download on demand from the CrossWire Bible Society module repository (crosswire.org). Texts belong to their respective copyright holders.")
                        .font(.callout).foregroundStyle(.secondary)
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
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: true) { result in
                do {
                    let urls = try result.get()
                    try personalData.importFrom(urls: urls)
                    message = "Import complete: \(urls.count) file(s)."
                } catch {
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
