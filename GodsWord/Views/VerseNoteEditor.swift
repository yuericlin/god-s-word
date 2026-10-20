// VerseNoteEditor.swift
// Sheet for viewing/editing the text note attached to one verse.
// The note text is passed in at creation time and stored in @State via
// init, so the editor always opens with the correct content (no onAppear
// timing issues). Saves/deletes via PersonalData using the note key.

import SwiftUI

struct VerseNoteEditor: View {
    let reference: String
    let noteKey: String
    /// The note text when the editor opened; Save is disabled while unchanged.
    private let originalText: String
    @EnvironmentObject private var personalData: PersonalData
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text: String
    @State private var showingDeleteConfirm = false

    init(reference: String, noteKey: String, initialText: String) {
        self.reference = reference
        self.noteKey = noteKey
        self.originalText = initialText
        _text = State(initialValue: initialText)
    }

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
                    ToolbarItemGroup(placement: .confirmationAction) {
                        if !originalText.isEmpty {
                            Button("Delete", role: .destructive) {
                                showingDeleteConfirm = true
                            }
                        }
                        Button("Save") {
                            personalData.setVerseNote(text, forKey: noteKey)
                            dismiss()
                        }
                        .disabled(text == originalText)
                    }
                }
                .confirmationDialog("Delete this note?",
                                    isPresented: $showingDeleteConfirm,
                                    titleVisibility: .visible) {
                    Button("Delete Note", role: .destructive) {
                        personalData.setVerseNote(nil, forKey: noteKey)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
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
