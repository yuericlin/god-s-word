// CommentaryService.swift — the commentaries available to the auxiliary
// panel: installed SWORD commentary modules (zCom) that the panel can
// render, plus loading of their entries via the shared ModuleLoader.
// A zCom module has the same .bzv/.bzs/.bzz layout as a zText Bible, so
// no separate reader is needed; entries come back as plain text, one per
// verse, with a single commentary entry repeated at every verse it
// covers (see CommentaryGrouping in SwordReader).

import Foundation
import SwordReader

/// Sendable (its only payload, InstalledModule, is Sendable) so the
/// panel can hand a module to the nonisolated async loaders below from
/// main-actor contexts without data-race errors.
public struct CommentaryModule: Identifiable, Equatable, Sendable {
    public let installed: InstalledModule

    public var id: String { installed.id }
    /// Full title, e.g. "Matthew Henry's Concise Commentary…".
    public var displayName: String { installed.info.description }
    /// Compact label: the module id (e.g. "MHCC").
    public var shortLabel: String { installed.id }
    /// The module's declared distribution license ("" when the conf
    /// declares none) — shown in the panel's info sheet (REQ-AP-8).
    public var license: String { installed.info.distributionLicense }
    /// The module's About text from its conf (copyright/publisher info).
    public var about: String { installed.info.about }

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
    /// commentary doesn't cover. Throws when the module can't be opened
    /// (damaged, missing, unsupported) so the caller can show an error
    /// state instead of mistaking the failure for a chapter the
    /// commentary doesn't cover (REQ-AP-13).
    public func loadChapter(testament: Int, book: Int, chapter: Int) async throws
        -> [(verse: Int, text: String)]
    {
        let mod = try await ModuleLoader.shared.module(for: installed)
        return mod.chapter(testament: testament, book: book, chapter: chapter)
            .filter { !$0.text.isEmpty }
    }
}
