// ReadingHistoryLog.swift
// Pure, testable reading-history logic (REQ-HI-3, REQ-HI-7..9).
//
// One entry is one chapter. Reading it again within 24 hours of the entry's
// earliest visit joins that entry (a new timestamp, and the version if it is
// new) instead of adding another; after that it starts a new entry. The log
// is most-recent-first.

import Foundation

/// One chapter in the reading history, with every visit and version that
/// belongs to it. Decodes the older one-visit format
/// (`moduleID` + `timestamp`) too.
public struct ReadingHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var bookName: String
    public let testament: Int
    public let book: Int
    public let chapter: Int
    /// Versions read, least recently used first.
    public var moduleIDs: [String]
    /// Visit times.
    public var timestamps: [Date]

    public init(id: UUID = UUID(), bookName: String, testament: Int, book: Int,
                chapter: Int, moduleIDs: [String], timestamps: [Date]) {
        self.id = id
        self.bookName = bookName
        self.testament = testament
        self.book = book
        self.chapter = chapter
        self.moduleIDs = moduleIDs
        self.timestamps = timestamps
    }

    /// The version used most recently (what tapping the entry opens).
    public var moduleID: String { moduleIDs.last ?? "" }
    /// When the entry started: its earliest visit.
    public var earliest: Date { timestamps.min() ?? .distantPast }
    /// Its latest visit.
    public var lastVisit: Date { timestamps.max() ?? .distantPast }

    func isSameChapter(as other: ReadingHistoryEntry) -> Bool {
        testament == other.testament && book == other.book && chapter == other.chapter
    }

    /// Notes a visit in `moduleID` at `date`. The version always counts (and
    /// becomes the most recent); a reload within `visitGap` of the last visit
    /// is not a new visit, so it adds no timestamp.
    mutating func noteVisit(moduleID: String, at date: Date) {
        moduleIDs.removeAll { $0 == moduleID }
        moduleIDs.append(moduleID)
        if let last = timestamps.max(),
           date.timeIntervalSince(last) < ReadingHistoryLog.visitGap {
            return
        }
        timestamps.append(date)
    }

    /// Folds a newer entry for the same chapter into this one.
    mutating func absorb(_ newer: ReadingHistoryEntry) {
        timestamps = (timestamps + newer.timestamps).sorted()
        for id in newer.moduleIDs {
            moduleIDs.removeAll { $0 == id }
            moduleIDs.append(id)
        }
        bookName = newer.bookName
    }

    // MARK: Codable (legacy: moduleID + timestamp)

    private enum CodingKeys: String, CodingKey {
        case id, bookName, testament, book, chapter, moduleIDs, timestamps
        case moduleID, timestamp   // older one-visit format
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bookName = try c.decode(String.self, forKey: .bookName)
        testament = try c.decode(Int.self, forKey: .testament)
        book = try c.decode(Int.self, forKey: .book)
        chapter = try c.decode(Int.self, forKey: .chapter)
        if let ids = try c.decodeIfPresent([String].self, forKey: .moduleIDs) {
            moduleIDs = ids
        } else if let one = try c.decodeIfPresent(String.self, forKey: .moduleID) {
            moduleIDs = [one]
        } else {
            moduleIDs = []
        }
        if let times = try c.decodeIfPresent([Date].self, forKey: .timestamps) {
            timestamps = times
        } else if let one = try c.decodeIfPresent(Date.self, forKey: .timestamp) {
            timestamps = [one]
        } else {
            timestamps = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(bookName, forKey: .bookName)
        try c.encode(testament, forKey: .testament)
        try c.encode(book, forKey: .book)
        try c.encode(chapter, forKey: .chapter)
        try c.encode(moduleIDs, forKey: .moduleIDs)
        try c.encode(timestamps, forKey: .timestamps)
    }
}

public enum ReadingHistoryLog {
    /// Visits to a chapter join its entry while within this long of the
    /// entry's earliest visit (REQ-HI-7).
    public static let mergeWindow: TimeInterval = 24 * 60 * 60
    /// A reload this soon after the last visit adds no timestamp.
    public static let visitGap: TimeInterval = 60
    /// Entries kept (REQ-HI-2).
    public static let limit = 100
    /// Entries shown before the "…" row (REQ-HI-9).
    public static let displayLimit = 20

    /// Records a visit. Joins the most recent entry for the same chapter
    /// that started within `mergeWindow` of `now` (moving it to the front);
    /// otherwise adds a new entry at the front. Capped at `limit`.
    public static func recording(moduleID: String, bookName: String,
                                 testament: Int, book: Int, chapter: Int,
                                 at now: Date = Date(),
                                 into log: [ReadingHistoryEntry],
                                 limit: Int = ReadingHistoryLog.limit)
        -> [ReadingHistoryEntry]
    {
        var out = log
        if let i = out.firstIndex(where: {
            $0.testament == testament && $0.book == book && $0.chapter == chapter
                && now.timeIntervalSince($0.earliest) < mergeWindow
        }) {
            var entry = out.remove(at: i)
            entry.bookName = bookName
            entry.noteVisit(moduleID: moduleID, at: now)
            out.insert(entry, at: 0)
        } else {
            out.insert(ReadingHistoryEntry(bookName: bookName, testament: testament,
                                           book: book, chapter: chapter,
                                           moduleIDs: [moduleID], timestamps: [now]),
                       at: 0)
        }
        if out.count > limit { out = Array(out.prefix(limit)) }
        return out
    }

    /// Merges entries recorded before combining existed: for each chapter,
    /// entries that start within `mergeWindow` of an earlier entry's start
    /// become one. Most recent first. Safe to apply repeatedly.
    public static func combined(_ log: [ReadingHistoryEntry]) -> [ReadingHistoryEntry] {
        var out: [ReadingHistoryEntry] = []
        for entry in log.sorted(by: { $0.earliest < $1.earliest }) {
            if let i = out.lastIndex(where: {
                $0.isSameChapter(as: entry)
                    && entry.earliest.timeIntervalSince($0.earliest) < mergeWindow
            }) {
                out[i].absorb(entry)
            } else {
                out.append(entry)
            }
        }
        return out.sorted { $0.lastVisit > $1.lastVisit }
    }

    /// The entries to show (the most recent `displayLimit`) and whether more
    /// exist, in which case the list ends with "…".
    public static func visible(_ log: [ReadingHistoryEntry])
        -> (entries: [ReadingHistoryEntry], hasMore: Bool)
    {
        (Array(log.prefix(displayLimit)), log.count > displayLimit)
    }
}
