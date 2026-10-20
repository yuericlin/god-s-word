// CompareView.swift — the Compare panel for the selected verses, and the
// setting that chooses which versions it shows.
// The panel always shows the version being read; the versions ticked in
// the Compare setting (Settings > Compare, or the Versions button here)
// are shown with it. With nothing ticked, only the current version shows.

import SwiftUI
import SwordReader

struct CompareView: View {
    let current: BibleVersion
    let available: [BibleVersion]
    let testament: Int
    let book: Int
    let chapter: Int
    let bookTitle: String
    /// Sorted verse numbers of the selection.
    let selectedVerses: [Int]

    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.dismiss) private var dismiss
    /// version id -> verse number -> text, filled in as chapters load.
    @State private var texts: [String: [Int: String]] = [:]
    @State private var showingVersions = false

    /// The current version first, then the Compare setting's versions.
    private var versions: [BibleVersion] {
        let ids = CompareVersions.ids(current: current.id,
                                      configured: personalData.compareVersionIDs,
                                      available: available.map(\.id))
        return ids.compactMap { id in
            id == current.id ? current : available.first { $0.id == id }
        }
    }

    private var title: String {
        "\(bookTitle) \(chapter):\(VerseFormatting.verseListString(selectedVerses))"
    }

    /// Reload when the set of versions changes (the chapter is fixed while
    /// the panel is open).
    private var loadKey: String {
        versions.map(\.id).joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(versions) { version in
                    Section {
                        rows(for: version)
                    } header: {
                        header(for: version)
                    }
                }
                if versions.count == 1 {
                    Section {
                        Text("Only the version you are reading is shown. Choose more with the Versions button, or in Settings.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingVersions = true
                    } label: {
                        Label("Versions", systemImage: "books.vertical")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingVersions) {
                CompareVersionsPicker()
            }
            .task(id: loadKey) { await load() }
        }
    }

    private func header(for version: BibleVersion) -> some View {
        HStack(spacing: 6) {
            Text(version.shortLabel).font(.headline)
            if version.displayName != version.shortLabel {
                Text(version.displayName).font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    @ViewBuilder
    private func rows(for version: BibleVersion) -> some View {
        if let chapterTexts = texts[version.id] {
            ForEach(selectedVerses, id: \.self) { verse in
                verseRow(verse, text: chapterTexts[verse])
            }
        } else {
            ProgressView()
        }
    }

    /// One verse. Numbers show only when several verses are selected
    /// (as in Copy); a verse the version lacks shows a dash.
    private func verseRow(_ verse: Int, text: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if selectedVerses.count > 1 {
                Text("\(verse)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let text, !text.isEmpty {
                Text(text)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: personalData.fontSize, design: .serif))
        .textSelection(.enabled)
    }

    private func load() async {
        for version in versions where texts[version.id] == nil {
            let rows = (try? await version.loadChapter(testament: testament,
                                                       book: book,
                                                       chapter: chapter)) ?? []
            texts[version.id] = Dictionary(rows.map { ($0.verse, $0.text) },
                                           uniquingKeysWith: { first, _ in first })
        }
    }
}

/// Chooses the versions the Compare panel shows (besides the current one).
/// Used from Settings > Compare and from the Compare panel itself.
struct CompareVersionsPicker: View {
    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.moduleStore) private var store
    @State private var versions: [BibleVersion] = []

    var body: some View {
        List {
            Section {
                ForEach(versions) { version in
                    Button {
                        personalData.toggleCompareVersion(version.id)
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
                            if personalData.compareVersionIDs.contains(version.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            } footer: {
                Text("Compare always shows the version you are reading. With none chosen here it shows only that version; otherwise it shows the chosen versions too.")
            }
        }
        .navigationTitle("Compare versions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { versions = BibleVersion.allInstalled(in: store) }
    }
}
