// SourcesSettingsView.swift — Settings > Sources (REQ-SRC-2/3): pick the
// default download source, manage sources, and update the public source
// list on demand.

import SwiftUI

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
