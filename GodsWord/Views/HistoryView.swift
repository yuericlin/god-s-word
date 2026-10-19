// HistoryView.swift — full reading history log. Tapping an entry jumps
// back to that location.

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var personalData: PersonalData
    var onSelect: ((HistoryEntry) -> Void)?

    var body: some View {
        List {
            if personalData.historyLog.isEmpty {
                Text("No reading history yet. Chapters you read will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(personalData.historyLog) { entry in
                    Button {
                        onSelect?(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.bookName) \(entry.chapter)")
                                .font(.headline)
                            HStack(spacing: 4) {
                                Text(entry.moduleID)
                                Text("·")
                                Text(entry.timestamp, style: .relative)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    personalData.deleteHistory(at: offsets)
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
}
