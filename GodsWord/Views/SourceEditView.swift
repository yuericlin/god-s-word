// SourceEditView.swift — add or edit a Bible source. A source is a name
// plus either a repository URL (downloadable) or a local folder (private
// JSON Bibles). Built-ins can be renamed/relocated; only custom sources
// can be deleted (their version files are kept).

import SwiftUI
import UniformTypeIdentifiers

struct SourceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var urlString: String
    @State private var folderBookmark: Data?
    @State private var folderName: String?
    @State private var kindIsURL: Bool
    @State private var showingFolderPicker = false
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?

    private let source: BibleSource?   // nil = adding a new source
    private let isNew: Bool

    init(source: BibleSource? = nil) {
        self.source = source
        self.isNew = source == nil
        _name = State(initialValue: source?.name ?? "")
        if case .repository(let url) = source?.kind {
            _urlString = State(initialValue: url.absoluteString)
        } else {
            _urlString = State(initialValue: "")
        }
        if case .folder(let bookmark) = source?.kind {
            _folderBookmark = State(initialValue: bookmark)
        }
        _kindIsURL = State(initialValue: {
            if let s = source { return s.repositoryURL != nil }
            return true
        }())
    }

    /// Whether the name/URL/folder fields are editable for this source.
    private var canEditLocation: Bool {
        guard let source else { return true }
        // The built-in Private source lives in app storage; only its name
        // is editable.
        return source.id != BibleSourceStore.`private`.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Source name", text: $name)
                }
                if canEditLocation {
                    if isNew {
                        Section("Type") {
                            Picker("Type", selection: $kindIsURL) {
                                Text("Repository URL").tag(true)
                                Text("Local folder").tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    if kindIsURL {
                        Section("URL") {
                            TextField("https://…", text: $urlString)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    } else {
                        Section("Folder") {
                            if let folderName {
                                Text(folderName).foregroundStyle(.secondary)
                            }
                            Button("Choose folder…") { showingFolderPicker = true }
                        }
                    }
                } else {
                    Section {
                        Text("This source uses the app's private storage.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                if !isNew, let source, !source.isBuiltIn {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Text("Delete source")
                        }
                    } footer: {
                        Text("The source is removed from the library, but its version files stay on your device.")
                    }
                }
            }
            .navigationTitle(isNew ? "Add Source" : "Edit Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .fileImporter(isPresented: $showingFolderPicker,
                          allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do {
                        let bookmark = try url.bookmarkData(
                            options: [.withSecurityScope],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil)
                        folderBookmark = bookmark
                        folderName = url.lastPathComponent
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                case .failure(let e):
                    errorMessage = e.localizedDescription
                }
            }
            .confirmationDialog("Delete this source?",
                                isPresented: $showingDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete source", role: .destructive) {
                    if let source { BibleSourceStore.shared.delete(source) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if !canEditLocation { return true }
        if kindIsURL {
            return URL(string: urlString.trimmingCharacters(in: .whitespaces)) != nil
                && !urlString.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return folderBookmark != nil
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let store = BibleSourceStore.shared
        if isNew {
            let id = UUID().uuidString
            let kind: SourceKind
            if kindIsURL {
                guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
                    errorMessage = "That isn't a valid URL."
                    return
                }
                kind = .repository(url)
            } else {
                guard let bookmark = folderBookmark else {
                    errorMessage = "Pick a folder first."
                    return
                }
                kind = .folder(bookmark: bookmark)
            }
            store.save(BibleSource(id: id, name: trimmedName, kind: kind, isBuiltIn: false))
        } else if var source {
            source.name = trimmedName
            if canEditLocation, kindIsURL,
               let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) {
                source.kind = .repository(url)
            }
            // A custom folder source keeps its existing folder on edit.
            store.save(source)
        }
        dismiss()
    }
}
