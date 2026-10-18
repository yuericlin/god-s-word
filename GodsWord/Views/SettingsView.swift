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

    var body: some View {
        NavigationStack {
            List {
                Section("Reading") {
                    HStack {
                        Text("Text size")
                        Spacer()
                        Stepper("\(Int(personalData.fontSize)) pt",
                                value: $personalData.fontSize, in: 12 ... 32, step: 1)
                    }
                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: personalData.fontSize, design: .serif))
                        .foregroundStyle(.secondary)
                }

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
                        Text("Back up your reading data — text size, reading positions, " +
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
                Text("This replaces your text size, reading positions, and installed-Bible list with the backup. Bible texts will be re-downloaded as needed.")
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
