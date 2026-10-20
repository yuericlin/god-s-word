// VerseNoteEditor.swift
// Sheet for viewing/editing the text note attached to one verse.
// Self-contained: loads/saves via PersonalData using the note key,
// so callers don't need to manage text state (avoids sheet timing issues).

import SwiftUI

struct VerseNoteEditor: View {
    let reference: String
    let noteKey: String
    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

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
                            personalData.setVerseNote(text, forKey: noteKey)
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    // Load the note text when the sheet appears.
                    text = personalData.verseNote(forKey: noteKey) ?? ""
                    // Focus after the sheet animation so the keyboard shows.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isFocused = true
                    }
                }
        }
    }
}
