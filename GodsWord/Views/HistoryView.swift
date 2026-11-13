// HistoryView.swift — full reading history log. Tapping an entry reports
// it through onSelect. An entry combines the visits to one chapter within
// 24 hours: it shows the earliest visit and every version read. Only the
// latest 20 entries are listed, followed by "…". Each entry renders on
// one line, in the Highlights row format (REQ-AP-11).

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
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.black)
            } else {
                ForEach(ReadingHistoryLog.visible(personalData.historyLog).entries) { entry in
                    Button {
                        onSelect?(entry)
                    } label: {
                        // One line per entry, built exactly like a
                        // Highlights row: the yellow bar overlaid in
                        // the text's leading padding, the row's own
                        // hairline below, the List separator hidden
                        // (REQ-AP-11).
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.entryText(entry))
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 14)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(red: 1.0, green: 0.9, blue: 0.0)
                                            .opacity(0.65))
                                        .frame(width: 4, height: 22)
                                }
                                .padding(.bottom, 11)
                            Rectangle()
                                .fill(Color(uiColor: .separator))
                                .frame(height: 0.5)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 11, leading: 16,
                                              bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.black)
                }
                .onDelete { offsets in
                    // The visible entries are the log's first 20, so the
                    // offsets are the log's offsets.
                    personalData.deleteHistory(at: offsets)
                }
                if ReadingHistoryLog.visible(personalData.historyLog).hasMore {
                    Text("…")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.black)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityLabel("Older history not shown")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        // No toolbar of its own: this list is embedded in the
        // reader's auxiliary panel, inside the reader's
        // navigation stack, so a toolbar Clear here surfaced
        // in the READER's navigation bar — top-right, beside
        // the version and chapter dropdowns (removed Nov 12,
        // 2026). Clearing the log lives in the hosting tab's
        // header (REQ-AP-11).
    }

    /// One entry on one line, in the note-row format the Highlights
    /// rows use: "Book Chapter · Version, Version - Nov 12, 8:15 PM"
    /// — every version read and the earliest visit's date and time,
    /// nothing dropped (REQ-AP-11).
    private static func entryText(_ entry: HistoryEntry) -> String {
        var text = "\(entry.bookName) \(entry.chapter)"
        if !entry.moduleIDs.isEmpty {
            text += " · \(entry.moduleIDs.joined(separator: ", "))"
        }
        text += " - \(earliestText(entry.earliest))"
        return text
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
