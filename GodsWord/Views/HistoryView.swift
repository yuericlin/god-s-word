// HistoryView.swift — full reading history log. Tapping an entry jumps
// back to that location. An entry combines the visits to one chapter within
// 24 hours: it shows the earliest visit and every version read. Only the
// latest 20 entries are listed, followed by "…".

import SwiftUI
import SwordReader

struct HistoryView: View {
    @EnvironmentObject private var personalData: PersonalData
    var onSelect: ((HistoryEntry) -> Void)?

    var body: some View {
        List {
            if personalData.historyLog.isEmpty {
                Text("No reading history yet. Chapters you read will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ReadingHistoryLog.visible(personalData.historyLog).entries) { entry in
                    Button {
                        onSelect?(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.bookName) \(entry.chapter)")
                                .font(.headline)
                            HStack(spacing: 4) {
                                Text(entry.moduleIDs.joined(separator: ", "))
                                Text("·")
                                Text(Self.earliestText(entry.earliest))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    // The visible entries are the log's first 20, so the
                    // offsets are the log's offsets.
                    personalData.deleteHistory(at: offsets)
                }
                if ReadingHistoryLog.visible(personalData.historyLog).hasMore {
                    Text("…")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityLabel("Older history not shown")
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

    /// The entry's earliest visit as a date and time; the year only when
    /// it isn't this year.
    private static func earliestText(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: Date(),
                                               toGranularity: .year)
        let style: Date.FormatStyle = sameYear
            ? .dateTime.month(.abbreviated).day().hour().minute()
            : .dateTime.year().month(.abbreviated).day().hour().minute()
        return date.formatted(style)
    }
}
