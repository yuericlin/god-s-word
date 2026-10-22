// HistoryView.swift — full reading history log. Tapping an entry jumps
// back to that location. An entry combines the visits to one chapter within
// 24 hours: it shows the versions read and the time of its earliest visit.
// The list is split by day and holds the last 30 days of reading.

import SwiftUI
import SwordReader

struct HistoryView: View {
    @EnvironmentObject private var personalData: PersonalData
    var onSelect: ((HistoryEntry) -> Void)?

    var body: some View {
        let all = ReadingHistoryLog.sections(personalData.historyLog)
        List {
            if all.isEmpty {
                Text("No reading history yet. Chapters you read will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(all) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    } header: {
                        Text(Self.dayTitle(section.day))
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !personalData.historyLog.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) {
                        personalData.clearHistory()
                    }
                }
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        Button {
            onSelect?(entry)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.bookName) \(entry.chapter)")
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(entry.moduleIDs.joined(separator: ", "))
                    Text("·")
                    Text(entry.earliest, format: .dateTime.hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        // Each entry can be deleted on its own, whatever day it is under.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                personalData.deleteHistory(ids: [entry.id])
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                personalData.deleteHistory(ids: [entry.id])
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// "Today", "Yesterday", or e.g. "Mon, Oct 19" (with the year when it
    /// isn't this year).
    private static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = cal.isDate(day, equalTo: Date(), toGranularity: .year)
        let style: Date.FormatStyle = sameYear
            ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
            : .dateTime.year().month(.abbreviated).day()
        return day.formatted(style)
    }
}
