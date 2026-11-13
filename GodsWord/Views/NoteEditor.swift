// NoteEditor.swift
// The one sheet for viewing/editing a note — verse, chapter,
// and book notes alike. The note text is passed in at creation
// time and stored in @State via init, so the editor always
// opens with the correct content (no onAppear timing issues).
// Saves/deletes go through the caller's onSave closure
// (nil = delete), so the caller decides which store the note
// belongs to.

import SwiftUI

/// The one note editor — verse, chapter, and book notes alike
/// (REQ-NT-14/15). Self-contained text, Save/Delete via the
/// `onSave` closure (nil = delete) — without a storage key, so
/// the caller decides which store the note belongs to.
struct NoteEditor: View {
    let reference: String
    /// When set, a "Read" button beside Cancel (top left)
    /// moves the reader to the note's chapter, then dismisses
    /// (REQ-NT-21). The editor itself only edits — its title
    /// is never a jump target.
    let onReadChapter: (() -> Void)?
    private let originalText: String
    private let onSave: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text: String
    @State private var showingDeleteConfirm = false

    init(reference: String, initialText: String,
         seedText: String = "",
         onReadChapter: (() -> Void)? = nil,
         onSave: @escaping (String?) -> Void) {
        self.reference = reference
        self.originalText = initialText
        self.onReadChapter = onReadChapter
        self.onSave = onSave
        // A brand-new note (no saved text) opens pre-filled
        // with the seed (the selected verses' text, or book +
        // chapter); originalText stays empty so Save is
        // enabled and Delete stays hidden.
        _text = State(initialValue: initialText.isEmpty ? seedText : initialText)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .padding()
                .navigationTitle(reference)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Each side's pair sits in one HStack of
                    // plain buttons: the 10pt stack spacing is
                    // then the true gap between the two labels —
                    // the same as the pill's edge-to-label
                    // padding. (With the system button style,
                    // each label also carries its own padding
                    // and the visible gap balloons past 30pt;
                    // a ToolbarItemGroup's spacing is not ours
                    // to set at all.)
                    ToolbarItem(placement: .cancellationAction) {
                        HStack(spacing: 10) {
                            Button("Cancel") { dismiss() }
                            // Read: the editor's one navigation
                            // action, beside Cancel (REQ-NT-21).
                            if let onReadChapter {
                                Button("Read") {
                                    onReadChapter()
                                    dismiss()
                                }
                                .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        HStack(spacing: 10) {
                            if !originalText.isEmpty {
                                Button("Delete", role: .destructive) {
                                    showingDeleteConfirm = true
                                }
                            }
                            Button("Save") {
                                onSave(text)
                                dismiss()
                            }
                            .disabled(text == originalText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .confirmationDialog("Delete this note?",
                                    isPresented: $showingDeleteConfirm,
                                    titleVisibility: .visible) {
                    Button("Delete Note", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isFocused = true
                    }
                }
        }
    }
}
