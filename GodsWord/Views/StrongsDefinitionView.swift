// StrongsDefinitionView.swift — shows a Strong's dictionary entry.
// Downloads the Hebrew/Greek lexicon on first use. References
// inside an entry are tappable and open the referenced entry in
// place; a pair of arrows at the bottom walks back and forward
// through the entries viewed (REQ-ST-7/8).

import SwiftUI
import SwordReader

struct StrongsDefinitionView: View {
    let key: String
    @Environment(\.dismiss) private var dismiss
    @State private var currentKey: String
    @State private var backStack: [String] = []
    @State private var forwardStack: [String] = []
    @State private var definition: String?
    @State private var loadError: String?

    init(key: String) {
        self.key = key
        _currentKey = State(initialValue: key)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let definition {
                    ScrollView {
                        Text(attributed(definition))
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
            .navigationTitle(currentKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                // Back / forward through the entries viewed in
                // this session (REQ-ST-8): forward is enabled
                // only after going back, like a browser.
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button { goBack() } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(backStack.isEmpty)
                        Button { goForward() } label: {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .disabled(forwardStack.isEmpty)
                        Spacer()
                    }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "strongs", let host = url.host,
                      !host.isEmpty else { return .systemAction }
                navigate(to: host.uppercased())
                return .handled
            })
            .task(id: currentKey) { await load() }
        }
    }

    /// The entry text with its cross-references as links
    /// (REQ-ST-7); the openURL environment above intercepts the
    /// taps and navigates in place.
    private func attributed(_ definition: String) -> AttributedString {
        var out = AttributedString()
        for segment in StrongsReferences.segments(in: definition,
                                                  currentKey: currentKey) {
            switch segment {
            case .text(let s):
                out += AttributedString(s)
            case .reference(let refKey, let display):
                var run = AttributedString(display)
                run.link = URL(string: "strongs://\(refKey)")
                out += run
            }
        }
        return out
    }

    /// Opens another entry from a tapped reference: the current
    /// entry goes on the back stack and the forward side clears.
    private func navigate(to newKey: String) {
        guard newKey != currentKey else { return }
        backStack.append(currentKey)
        forwardStack.removeAll()
        currentKey = newKey
    }

    private func goBack() {
        guard let target = backStack.popLast() else { return }
        forwardStack.append(currentKey)
        currentKey = target
    }

    private func goForward() {
        guard let target = forwardStack.popLast() else { return }
        backStack.append(currentKey)
        currentKey = target
    }

    private func load() async {
        definition = nil
        loadError = nil
        do {
            if let def = try await StrongsService.shared.definition(for: currentKey) {
                definition = def
            } else {
                loadError = "No dictionary entry for \(currentKey)."
            }
        } catch {
            loadError = "The dictionary couldn't be downloaded. Check your connection and try again."
        }
    }
}
