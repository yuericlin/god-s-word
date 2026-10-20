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
    @State private var selectedSourceID = BibleSourceStore.crossWire.id

    /// All remote (repository) sources the user can download from.
    private var repositorySources: [BibleSource] {
        BibleSourceStore.shared.allSources.filter { $0.repositoryURL != nil }
    }

    private var selectedSource: BibleSource {
        repositorySources.first { $0.id == selectedSourceID } ?? BibleSourceStore.crossWire
    }

    private var repository: SwordRepository {
        let url = selectedSource.repositoryURL ?? BibleSourceStore.crossWire.repositoryURL!
        return SwordRepository(name: selectedSource.name, baseURL: url)
    }

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
                    VStack(spacing: 0) {
                        if repositorySources.count > 1 {
                            Picker("Source", selection: $selectedSourceID) {
                                ForEach(repositorySources) { source in
                                    Text(source.name).tag(source.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding()
                        }
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
        .onChange(of: selectedSourceID) { Task { await load() } }
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
            // Tag the module with the source it was downloaded from so it
            // appears under that source in the library.
            BibleSourceStore.shared.setSourceID(selectedSourceID, forModule: mod.id)
            installedIDs.insert(mod.id)
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}
