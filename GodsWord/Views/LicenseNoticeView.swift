// LicenseNoticeView.swift — licenses and notices, linked from Settings > About.
// Mirrors the "Licensing and Bible texts" section of the README.

import SwiftUI

struct LicenseNoticeView: View {
    var body: some View {
        List {
            Section("This app") {
                Text("God's Word app and library code: MIT License, Copyright (c) 2026 Eric Lin.")
                Text("The app contains no Bible text, lexicon, or dictionary. All of them are downloaded or imported by you.")
            }
            Section("Bible texts and modules") {
                Text("Bible texts and lexicon modules are not covered by the MIT license. Each belongs to its copyright holder. Some are public domain (for example the KJV in the United States); others are still under copyright.")
                Text("CrossWire hosts a module only if it is public domain or the copyright holder gave permission. Check each module's copyright and license on crosswire.org before sharing, publishing, or screenshotting it.")
                Text("Locked (encrypted) modules are not offered by this app, and the app never tries to unlock them.")
            }
            Section("Third-party sources") {
                Text("Module repository: CrossWire Bible Society, crosswire.org (SWORD Project).")
                Text("Versification tables: generated from verse counts in SWORD 1.9.0 source, which is GPL-2 licensed. The tables hold counts and names, not code or text. Whether this needs more than a notice is under review.")
                Text("To report a copyright concern about a module: copyright@crosswire.org.")
                Text("Google Drive backup uses Google APIs. Apple, iPhone, App Store, and iCloud are Apple Inc. trademarks. Google and Google Drive are Google LLC trademarks.")
            }
            Section("No warranty") {
                Text("Bible content is supplied by its publishers \"as is.\" This app does not check or endorse it.")
            }
        }
        .navigationTitle("Licenses and notices")
        .navigationBarTitleDisplayMode(.inline)
    }
}
