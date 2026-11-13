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
                    // system-styled buttons — the pill, its edge
                    // padding, and the buttons' press feel are
                    // exactly the system's. The spacing is
                    // negative (-18) to overlap the two buttons'
                    // transparent inner padding (~28pt of the
                    // ~36pt gap measured at spacing 8), leaving
                    // the labels ~10pt apart — the same as the
                    // pill's edge-to-label padding. (Plain-style
                    // buttons were tried first: the toolbar
                    // clipped their labels and stripped the
                    // pill's edge padding. Nov 12, 2026.)
                    ToolbarItem(placement: .cancellationAction) {
                        HStack(spacing: -18) {
                            Button("Cancel") { dismiss() }
                            // Read: the editor's one navigation
                            // action, beside Cancel (REQ-NT-21).
                            if let onReadChapter {
                                Button("Read") {
                                    onReadChapter()
                                    dismiss()
                                }
                                // Blue, pinned two ways: the
                                // label style and the bar tint —
                                // inside the toolbar's glass pill
                                // either one alone can be
                                // overridden by the bar.
                                .foregroundStyle(.blue)
                                .tint(.blue)
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        HStack(spacing: -18) {
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
