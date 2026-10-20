// ReadingSettingsView.swift — text size + verse-by-verse + Strong's numbers,
// shared by the Settings screen and the reader's slide-in settings drawer.

import SwiftUI

struct ReadingSettingsView: View {
    @EnvironmentObject private var personalData: PersonalData
    /// Show the Strong's toggle (only when the current version supports it).
    var showStrongsOption: Bool = false

    var body: some View {
        Group {
            HStack {
                Text("Text size")
                Spacer()
                Stepper("\(Int(personalData.fontSize)) pt",
                        value: $personalData.fontSize, in: 12 ... 32, step: 1)
            }
            Toggle("Verse by verse", isOn: $personalData.verseByVerse)
            if showStrongsOption {
                Toggle("Strong's numbers", isOn: $personalData.showStrongs)
            }
            Text("In the beginning God created the heavens and the earth.")
                .font(.system(size: personalData.fontSize, design: .serif))
                .foregroundStyle(.secondary)
        }
    }
}
