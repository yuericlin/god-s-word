// ReaderView.swift — renders one chapter at a time.
// Reads and writes the shared ReadingHistory, so the pickers and the
// version menu always reflect the current selection.

import SwiftUI
import SwordReader

struct ReaderView: View {
    let history: ReadingHistory
    @Binding var path: NavigationPath

    @Environment(\.moduleStore) private var store
    @EnvironmentObject private var personalData: PersonalData
    @State private var verses: [(verse: Int, text: String)] = []
    @State private var loadError: String?
    @State private var showingSettings = false
    @State private var showingFullSettings = false
    @State private var availableModules: [InstalledModule] = []
    @State private var viewSize: CGSize = .zero

    /// Binding for the book picker: selecting a book jumps to its chapter 1.
    private var bookPickerSelection: Binding<Int> {
        Binding(
            get: { history.overallBookIndex },
            set: { history.setBook(overall: $0) }
        )
    }

    private var chapterPickerSelection: Binding<Int> {
        Binding(get: { history.chapter }, set: { go(toChapter: $0) })
    }

    /// Binding for the version picker next to the book title. Keeps the same
    /// reference, clamped to the new version's chapter count.
    private var versionSelection: Binding<String> {
        Binding(
            get: { history.module.id },
            set: { newID in
                guard newID != history.module.id,
                      let mod = availableModules.first(where: { $0.id == newID }) else { return }
                history.module = mod
                let count = history.chapterCount
                if history.chapter > count {
                    history.chapter = max(count, 1)
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                if let loadError {
                    ContentUnavailableView("Couldn't open chapter", systemImage: "exclamationmark.triangle",
                                            description: Text(loadError))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Color.clear.frame(height: 0).id("top")
                                if personalData.verseByVerse {
                                    ForEach(verses, id: \.verse) { v in
                                        Text(attributedVerse(number: v.verse, text: v.text))
                                            .font(.system(size: personalData.fontSize, design: .serif))
                                            .lineSpacing(6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else {
                                    // Paragraph mode: no paragraph info in the modules,
                                    // so the whole chapter flows as one paragraph.
                                    Text(attributedParagraph())
                                        .font(.system(size: personalData.fontSize, design: .serif))
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding()
                        }
                        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
                        .onChange(of: history.chapter) { proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
            // Slide-in settings drawer, opened with a left-edge swipe.
            if showingSettings {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { showingSettings = false }
                settingsDrawer
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingSettings)
        .background(DrawerEdgeGesture { showingSettings = true }.frame(width: 0, height: 0))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Version", selection: versionSelection) {
                            ForEach(availableModules, id: \.id) { mod in
                                Text(mod.id).tag(mod.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(history.module.id)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Menu {
                        Picker("Book", selection: bookPickerSelection) {
                            ForEach(0..<66, id: \.self) { i in
                                Text(history.bookName(overall: i)).tag(i)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(history.bookTitle)
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button { go(toChapter: history.chapter - 1) } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(!canGo(toChapter: history.chapter - 1))
                    Spacer()
                    if history.chapterCount > 0 {
                        Menu {
                            Picker("Chapter", selection: chapterPickerSelection) {
                                ForEach(1...history.chapterCount, id: \.self) { c in
                                    Text("\(c)").tag(c)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(history.chapter) / \(history.chapterCount)")
                                Image(systemName: "chevron.down")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(history.chapter) / \(history.chapterCount)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { go(toChapter: history.chapter + 1) } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(!canGo(toChapter: history.chapter + 1))
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    guard !showingSettings else { return }
                    let w = viewSize.width
                    if value.startLocation.x < 28 && value.translation.width > 50 {
                        // Left-edge swipe: open the settings drawer (fallback;
                        // the UIKit edge recognizer handles it primarily).
                        showingSettings = true
                    } else if w > 0 && value.startLocation.x > w - 20 && value.translation.width < -40 {
                        // Right-edge swipe: step back to the chapter picker.
                        if !path.isEmpty, allowStepBack() { path.removeLast() }
                    } else if value.translation.width < -60 {
                        // Middle swipe left: next chapter.
                        go(toChapter: history.chapter + 1)
                    } else if value.translation.width > 60 {
                        // Middle swipe right: previous chapter.
                        go(toChapter: history.chapter - 1)
                    }
                }
        )
        .task(id: chapterKey) { await load() }
        .onAppear { availableModules = store.installedModules() }
        .sheet(isPresented: $showingFullSettings) {
            SettingsView(onSelectHistoryEntry: { entry in
                if let mod = availableModules.first(where: { $0.id == entry.moduleID }) {
                    history.module = mod
                    history.testament = entry.testament
                    history.book = entry.book
                    history.chapter = entry.chapter
                }
                showingFullSettings = false
            })
        }
    }

    /// Slide-in settings panel with reading options and a link to full settings.
    /// Closes with the X button, a tap outside, or a left-drag on the edge handle.
    /// (The close drag lives only on the handle so it never fights the toggle.)
    private var settingsDrawer: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Settings").font(.headline)
                    Spacer()
                    Button { showingSettings = false } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                }
                ReadingSettingsView()
                Spacer()
                Button("More Settings…") {
                    showingSettings = false
                    showingFullSettings = true
                }
            }
            .padding()
            .frame(width: 288)
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 5, height: 48)
                Spacer()
            }
            .frame(width: 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width < -30 { showingSettings = false }
                    }
            )
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private var chapterKey: String {
        "\(history.module.id)-\(history.testament)-\(history.book)-\(history.chapter)"
    }

    private func canGo(toChapter c: Int) -> Bool {
        // Same-book navigation only; cross-book comes via the chapter picker.
        c >= 1 && c <= history.chapterCount
    }

    private func go(toChapter c: Int) {
        guard canGo(toChapter: c) else { return }
        history.chapter = c
    }

    private func attributedVerse(number: Int, text: String) -> AttributedString {
        var num = AttributedString("\(number) ")
        num.font = .system(size: personalData.fontSize * 0.65, design: .serif)
        num.foregroundColor = .secondary
        num.baselineOffset = personalData.fontSize * 0.25
        let body = AttributedString(text)
        return num + AttributedString(" ") + body
    }

    /// Whole chapter as one flowing paragraph (paragraph mode). Verse numbers
    /// stay inline; verses are joined with spaces.
    private func attributedParagraph() -> AttributedString {
        var out = AttributedString("")
        for (i, v) in verses.enumerated() {
            if i > 0 { out += AttributedString(" ") }
            out += attributedVerse(number: v.verse, text: v.text)
        }
        return out
    }

    private func load() async {
        loadError = nil
        do {
            let mod = try await ModuleLoader.shared.module(for: history.module)
            let rendered = mod.chapter(testament: history.testament, book: history.book,
                                       chapter: history.chapter)
            guard !rendered.isEmpty else {
                loadError = "This chapter has no text in this version."
                return
            }
            verses = rendered
            personalData.savePosition(ReadingPosition(testament: history.testament,
                                                      book: history.book,
                                                      chapter: history.chapter),
                                      for: history.module.id)
            personalData.saveLastReading(moduleID: history.module.id,
                                          testament: history.testament,
                                          book: history.book,
                                          chapter: history.chapter)
            personalData.recordHistory(moduleID: history.module.id,
                                        bookName: history.bookTitle,
                                        testament: history.testament,
                                        book: history.book,
                                        chapter: history.chapter)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Gives the settings drawer a hard claim on the left edge while reading.
/// Installs a dedicated screen-edge pan recognizer on the navigation
/// controller's view and makes the system's back-swipe wait for it
/// (`require(toFail:)`), so a left-edge swipe reliably opens the drawer
/// instead of popping back to the chapter list. Everything is installed on
/// appear and torn down on disappear, so other screens keep their swipe-back.
/// The "< Chapters" back button keeps working everywhere.
private struct DrawerEdgeGesture: UIViewControllerRepresentable {
    var onOpen: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        EdgeGestureViewController(onOpen: onOpen)
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        (vc as? EdgeGestureViewController)?.onOpen = onOpen
    }

    final class EdgeGestureViewController: UIViewController {
        var onOpen: () -> Void
        private weak var navView: UIView?
        private var edgePan: UIScreenEdgePanGestureRecognizer?

        init(onOpen: @escaping () -> Void) {
            self.onOpen = onOpen
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navController = navigationController,
                  let navView = navigationController?.view,
                  let pop = navController.interactivePopGestureRecognizer else { return }
            if edgePan == nil {
                let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
                pan.edges = .left
                // The drawer wins the left edge; the back button still pops.
                pop.require(toFail: pan)
                navView.addGestureRecognizer(pan)
                edgePan = pan
            }
            self.navView = navView
            navController.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let pan = edgePan {
                navView?.removeGestureRecognizer(pan)
                edgePan = nil
            }
            navView = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        @objc private func handleEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            if recognizer.state == .ended {
                onOpen()
            }
        }
    }
}
