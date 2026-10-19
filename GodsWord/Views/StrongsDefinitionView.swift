// StrongsDefinitionView.swift — shows a Strong's dictionary entry.
// Downloads the Hebrew/Greek lexicon on first use.

import SwiftUI

struct StrongsDefinitionView: View {
    let key: String
    @Environment(\.dismiss) private var dismiss
    @State private var definition: String?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let definition {
                    ScrollView {
                        Text(definition)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else if let loadError {
                    ContentUnavailableView("Couldn't load entry", systemImage: "exclamationmark.triangle",
                                            description: Text(loadError))
                } else {
                    ProgressView("Loading Strong's dictionary…")
                }
            }
            .navigationTitle(key)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            if let def = try await StrongsService.shared.definition(for: key) {
                definition = def
            } else {
                loadError = "No dictionary entry for \(key)."
            }
        } catch {
            loadError = "The dictionary couldn't be downloaded. Check your connection and try again."
        }
    }
}
