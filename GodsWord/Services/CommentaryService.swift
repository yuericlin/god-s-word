// CommentaryService.swift — the commentaries available to the auxiliary
// panel: installed SWORD commentary modules (zCom) that the panel can
// render, plus loading of their entries via the shared ModuleLoader.
// A zCom module has the same .bzv/.bzs/.bzz layout as a zText Bible, so
// no separate reader is needed; entries come back as plain text, one per
// verse, with a single commentary entry repeated at every verse it
// covers (see CommentaryGrouping in SwordReader).

import Foundation
import SwordReader

public struct CommentaryModule: Identifiable, Equatable {
    public let installed: InstalledModule

    public var id: String { installed.id }
    /// Full title, e.g. "Matthew Henry's Concise Commentary…".
    public var displayName: String { installed.info.description }
    /// Compact label: the module id (e.g. "MHCC").
    public var shortLabel: String { installed.id }

    public static func == (lhs: CommentaryModule, rhs: CommentaryModule) -> Bool {
        lhs.id == rhs.id
    }

    /// All installed commentaries the panel can render, in library order
    /// (ModuleStore sorts by display name).
    public static func allInstalled(in store: ModuleStore) -> [CommentaryModule] {
        store.installedModules()
            .filter { $0.info.isCommentaryRenderable }
            .map { CommentaryModule(installed: $0) }
    }

    /// The commentary to show: the user's setting when that module is
    /// still installed, otherwise the first installed commentary.
    public static func resolve(settingID: String,
                               installed: [CommentaryModule]) -> CommentaryModule? {
        if let chosen = installed.first(where: { $0.id == settingID }) {
            return chosen
        }
        return installed.first
    }

    /// Chapter count of a book in this commentary's versification.
    public func chapterCount(testament: Int, book: Int) -> Int {
        installed.info.versification?
            .book(testament: testament, book: book)?.chapters ?? 0
    }

    /// One chapter's entries as (verse, plain text), skipping verses the
    /// commentary doesn't cover.
    public func loadChapter(testament: Int, book: Int, chapter: Int) async
        -> [(verse: Int, text: String)]
    {
        guard let mod = try? await ModuleLoader.shared.module(for: installed)
        else { return [] }
        return mod.chapter(testament: testament, book: book, chapter: chapter)
            .filter { !$0.text.isEmpty }
    }
}
