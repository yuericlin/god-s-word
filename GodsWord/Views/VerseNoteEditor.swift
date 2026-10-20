// VerseNoteEditor.swift
// Sheet for viewing/editing the text note attached to one verse.

import SwiftUI

struct VerseNoteEditor: View {
    let reference: String
    @Binding var text: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .padding()
                .navigationTitle(reference)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(text)
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    // Focus after the sheet animation so the keyboard shows.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isFocused = true
                    }
                }
        }
    }
}
