/// Which verses a verse note was taken on (REQ-NT-22).
///
/// A verse note anchors at a single verse (REQ-NT-2), but when it
/// is saved from an editor opened on a multi-verse selection, the
/// app stores the whole selection as the note's scope, so the
/// Notes list and the editor can title the note with every verse
/// it covers ("John 3:4, 6"). This helper is the one rule both
/// save paths (reader and Notes panel) apply.
public enum NoteScopeLogic {

    /// The scope to store for a note saved from an editor opened
    /// with `selection` — nil when the editor was not opened from
    /// a selection (a flag tap, a Notes list row), which leaves
    /// any stored scope untouched. Only a multi-verse selection
    /// sets a scope: a single-verse save never shrinks one. The
    /// stored scope is the selection, sorted ascending.
    public static func storedScope(selection: [Int]?) -> [Int]? {
        guard let selection, selection.count > 1 else { return nil }
        return selection.sorted()
    }
}
