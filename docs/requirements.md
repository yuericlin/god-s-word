# God's Word — User Requirements

Captured from user directives (Oct 19, 2026). These are the source of truth for
behavior; each requirement has corresponding tests in `SwordReaderTests` or
`GodsWordTests` (where the logic is testable outside SwiftUI).

## Standing principles

- **Implement without changing rendering.** Never alter the native paragraph text
  rendering to add a feature; layer interactions on top (e.g., invisible links).
- **The simpler the better.** Prefer the minimal implementation that satisfies the
  requirement.

---

## 1. Verse picker

### Selection
- **REQ-VP-1:** Tapping a verse selects it. The selected verse shows a light sky
  blue highlight (`UIColor(0.53, 0.81, 0.98, alpha 0.55)` via `backgroundColor`).
- **REQ-VP-2:** Tapping a selected verse again unselects it.
- **REQ-VP-3:** Multiple verses can be selected at once.
- **REQ-VP-4:** Selection is cleared when the testament, book, or chapter changes.
- **REQ-VP-5:** Selection is KEPT when the Bible version changes (same chapter,
  different version).

### Implementation constraint
- Verses are tappable via invisible `verse://N` links on the native
  `AttributedString`. Link styling is neutralized (`underlineStyle = []`,
  `foregroundColor = .primary` unless the run already has a color) so rendering
  is pixel-identical to the original paragraph.

---

## 2. Copy

### Format
- **REQ-CP-1:** The clipboard text puts the verse(s) between two double quotes.
- **REQ-CP-2:** After the closing quote: book name, chapter, verses, then the
  Bible version. Format: `"text" Book Chapter:Verses Version`.
- **REQ-CP-3:** If only one verse is selected, the verse number is NOT included
  in the quoted text.
- **REQ-CP-4:** If multiple verses are selected, each verse's number IS included
  before its text inside the quotes (`"1 text 2 text"`).
- **REQ-CP-5:** Verse ranges in the reference are compressed: `[1,2,3,5]` →
  `"1-3, 5"`.

### Examples
Single (KJV Gen 1:1):
```
"In the beginning God created the heaven and the earth." Genesis 1:1 KJV
```
Multiple (KJV Gen 1:1-2):
```
"1 In the beginning God created the heaven and the earth. 2 And the earth was without form, and void; and darkness was upon the face of the deep." Genesis 1:1-2 KJV
```

---

## 3. Notes

### Anchoring
- **REQ-NT-1:** A note is scoped to either the entire chapter OR the selected
  verses.
- **REQ-NT-2:** When created from selected verses, the note anchors to the
  FIRST selected verse (lowest number). The note indicator appears only there.
- **REQ-NT-3:** A chapter note is anchored at verse 1.
- **REQ-NT-4:** Long-press on empty reading area offers "Take Notes", which
  creates a chapter note (anchored at verse 1).

### Indicator
- **REQ-NT-5:** A verse with a note shows a yellow background highlight on its
  verse number (`UIColor(1.0, 0.9, 0.45, alpha 0.55)`).
- **REQ-NT-6:** Tapping the highlighted verse number opens the note editor.
  (The highlight uses `backgroundColor`, which — unlike `foregroundColor` — is
  not overridden by link styling.)

### Editor
- **REQ-NT-7:** The note editor auto-focuses on appear: cursor shows and the
  keyboard comes up (via `@FocusState` with a 0.4s delay after the sheet
  animation).
- **REQ-NT-8:** The editor is self-contained: it loads the note text from
  `PersonalData` using the note key on appear, and saves via `PersonalData` on
  Save. Callers pass only the key and reference string.

### Storage
- **REQ-NT-9:** Notes persist in `UserDefaults` (`gw.verseNotes.v1`).
- **REQ-NT-10:** Notes are included in Drive backup payloads (v5). Applying an
  old backup never wipes existing notes.
- **REQ-NT-11:** Note storage key format: `"{moduleID}:{testament}:{book}:{chapter}:{verse}"`.

---

## 4. Bookmarks panel

### Sections
- **REQ-BP-1:** The panel has two sections: **Bookmarks** and **Notes**.
- **REQ-BP-2:** The Bookmarks section shows ribbon bookmarks (horizontal row).
  Tapping a bookmark jumps to its chapter. (Hold-1-second for Mark/Edit/Delete
  — see bookmarks spec.)
- **REQ-BP-3:** The Notes section lists every verse with a note, sorted by
  (module, testament, book, chapter, verse).
- **REQ-BP-4:** Each note row shows the reference (`"Book Chapter:Verse"`) and a
  2-line preview of the note text.
- **REQ-BP-5:** Tapping a note in the list opens the note editor for that note
  (does NOT jump to the verse).

### Actions
- **REQ-BP-6:** "Add Bookmark" button at the bottom creates a bookmark at the
  current chapter and opens the edit sheet.
- **REQ-BP-7:** "Add Note" button next to "Add Bookmark" opens the note editor.
  The note is scoped to the selected verses if any are selected, otherwise to
  the entire chapter (anchored at verse 1).

---

## 5. Strong's numbers

- **REQ-ST-1:** The "Strong's numbers" toggle appears in Settings only when the
  current version supports Strong's (conf lists `GlobalOptionFilter=OSISStrongs`).
  KJV and ChiUns both support it.
- **REQ-ST-2:** Strong's numbers default to hidden.
- **REQ-ST-3:** When enabled, tappable Strong's numbers appear after words in
  both paragraph and verse-by-verse modes.
- **REQ-ST-4:** Tapping a number downloads the Strong's Hebrew/Greek lexicon
  from CrossWire on first use, then shows the dictionary entry.
- **REQ-ST-5:** ChiUns-specific numbers H9001–H9004 (Hebrew inseparable
  prepositions: לְ "to/for", בְּ "in/with", כְּ "as/like") show built-in
  bilingual definitions; they have no standard Strong's entry.
- **REQ-ST-6:** Morphology codes hiding in lemmas (Hebrew > 8674, Greek > 5624)
  are filtered out and never displayed.

---

## 6. Gestures (final map, Oct 19)

- Right edge swipe left = forward (versions → books → chapters → reader; at
  reader opens bookmarks panel).
- Right edge swipe right = backward.
- Left edge = settings/history drawer (reader only).
- Middle swipes turn chapters.
