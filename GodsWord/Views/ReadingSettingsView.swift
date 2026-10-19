// ReadingSettingsView.swift — text size + verse-by-verse, shared by the
// Settings screen and the reader's slide-in settings drawer.

import SwiftUI

struct ReadingSettingsView: View {
    @EnvironmentObject private var personalData: PersonalData

    var body: some View {
        Group {
            HStack {
                Text("Text size")
                Spacer()
                Stepper("\(Int(personalData.fontSize)) pt",
                        value: $personalData.fontSize, in: 12 ... 32, step: 1)
            }
            Toggle("Verse by verse", isOn: $personalData.verseByVerse)
            Text("The quick brown fox jumps over the lazy dog.")
                .font(.system(size: personalData.fontSize, design: .serif))
                .foregroundStyle(.secondary)
        }
    }
}
