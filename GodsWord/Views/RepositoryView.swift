// RepositoryView.swift — browse the CrossWire repository and download versions.

import SwiftUI
import SwordReader

struct RepositoryView: View {
    @Environment(\.moduleStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var modules: [ModuleInfo] = []
    @State private var query = ""
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var downloading: Set<String> = []
    @State private var installedIDs: Set<String> = []

    private let repository = SwordRepository(
        name: "CrossWire",
        baseURL: URL(string: "https://crosswire.org/ftpmirror/pub/sword/raw")!)

    private var filtered: [ModuleInfo] {
        let base = modules.filter { $0.isRenderable }
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter {
            $0.id.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading repository…")
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load", systemImage: "wifi.exclamationmark",
                                            description: Text(errorMessage))
                } else {
                    List(filtered, id: \.id) { mod in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mod.description).font(.headline)
                                Text("\(mod.id) · \(mod.language)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            statusView(for: mod)
                        }
                    }
                    .searchable(text: $query, prompt: "Search versions")
                }
            }
            .navigationTitle("Add Bible")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
        .onAppear { installedIDs = Set(store.installedModules().map { $0.id }) }
    }

    @ViewBuilder
    private func statusView(for mod: ModuleInfo) -> some View {
        if installedIDs.contains(mod.id) {
            Text("Installed").font(.caption).foregroundStyle(.secondary)
        } else if downloading.contains(mod.id) {
            ProgressView().controlSize(.small)
        } else {
            Button("Get") { Task { await download(mod) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: repository.catalogURL)
            modules = try SwordRepository.parseCatalog([UInt8](data))
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func download(_ mod: ModuleInfo) async {
        downloading.insert(mod.id)
        defer { downloading.remove(mod.id) }
        do {
            let (data, response) = try await URLSession.shared.data(from: repository.packageURL(for: mod.id))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ModuleStoreError.downloadFailed }
            try store.install(packageData: [UInt8](data), moduleID: mod.id)
            installedIDs.insert(mod.id)
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}
