# God's Word

A minimalistic iPhone Bible reader. Download any Bible version from the
[CrossWire Bible Society](https://crosswire.org) module repository and read
one chapter at a time — nothing else.

> **Disclaimer.** God's Word is an independent, unofficial reader. It is not
> affiliated with, endorsed by, or sponsored by CrossWire Bible Society, the
> SWORD Project, Apple, Google, or any Bible publisher. The app contains no
> Bible text: every Bible, lexicon, and dictionary you read is downloaded by
> you from a third-party repository or imported by you. Those texts belong to
> their copyright holders, and you are responsible for using them within their
> licenses. See [Licensing and Bible texts](#licensing-and-bible-texts).

## Features

- **Any version, on demand** — browse the CrossWire repository inside the app
  and download Bible modules (KJV, 和合本, and 100+ more). No bundled text,
  no account needed.
- **One chapter at a time** — a calm reader: Library → Books → Chapters → text.
  Swipe or tap to move between chapters. Verse numbers, adjustable text size.
- **Auxiliary panel** — below the chapter: your notes at book, chapter, and
  verse level; a downloaded CrossWire commentary (e.g. MHCC) at the same
  three levels; and the selected verse rendered with Strong's numbers
  (from a fallback version you choose when the one you're reading has none).
- **Fast and offline** — a pure-Swift SWORD module reader with no third-party
  dependencies. Downloaded Bibles live on your iPhone and read fully offline.
- **Private by default** — your data (installed Bibles, reading positions, text
  size) stays in iPhone local storage. Optionally back it up to your own
  Google Drive — only with your consent, after you sign in.

## Install

### Option A — install the .ipa from GitHub Releases (no Mac needed)

Every push to `main` builds an unsigned `.ipa` (see Releases).

1. Download `GodsWord-unsigned.ipa` from the latest
   [Release](../../releases).
2. Install it with a free Apple ID using either:
   - **Sideloadly** (https://sideloadly.io): connect your iPhone, drag the
     `.ipa` in, enter your Apple ID — it signs and installs the app.
   - **AltStore** (https://altstore.io): add the `.ipa` via AltStore/AltServer
     with your Apple ID.
3. Free Apple IDs must re-sign every 7 days (Sideloadly/AltStore handle this
   with a refresh).

### Option B — build from source in Xcode

1. Open `GodsWord.xcodeproj` in Xcode 16+.
2. Set your development team (Signing & Capabilities) and a unique bundle ID.
3. Run on your iPhone.

### App Store (later)

Publishing to the App Store needs the Apple Developer Program ($99/year) and
App Store Connect setup: signed release builds, screenshots, privacy
declaration (the app collects nothing; Drive backup is opt-in), and review.
The codebase is already structured for it — no code changes needed.

## Google Drive backup setup (optional, one time)

The backup feature needs your own Google OAuth client (Google doesn't allow
sharing one). Without it, the app works fully — the Backup section in Settings
just explains the setup.

1. Go to [Google Cloud Console](https://console.cloud.google.com), create a
   project, and enable the **Google Drive API**.
2. *APIs & Services → Credentials → Create Credentials → OAuth client ID*,
   type **iOS**. Use the bundle ID you build with
   (default `com.yuericlin.godsword`).
3. Copy the generated **Client ID** (`….apps.googleusercontent.com`).
4. Copy `GodsWord/GoogleOAuth.plist.template` to `GodsWord/GoogleOAuth.plist`
   (git-ignored) and paste your client ID as `ClientID`.
5. In `GodsWord/Info.plist`, replace the `CFBundleURLSchemes` placeholder with
   `com.googleusercontent.apps.<YOUR_CLIENT_ID>` (the numeric part before
   `.apps.googleusercontent.com`).
6. Rebuild. Settings → Google Drive backup → Sign in with Google.

The app requests only the `drive.appdata` scope: it can see nothing in your
Drive except its own private app folder. The refresh token is stored in the
iOS Keychain. Sign out any time to revoke local access.

## Architecture

```
SwordReader/          Swift package, zero dependencies, tested on Linux + iOS
  Inflate.swift       RFC 1951 DEFLATE + RFC 1950 zlib (SWORD .bzz blocks)
  ZipReader.swift     module packages (*.zip)
  TarReader.swift     repository catalog (mods.d.tar.gz)
  SwordConf.swift     module .conf metadata
  Versification.swift verse-index math (mirrors SWORD's VersificationMgr)
  VersificationData.swift  generated KJV/NRSV tables (from SWORD canon.h; see README licensing)
  SwordModule.swift   zText reader (index + cached decompressed blocks)
  OsisPlain.swift     OSIS markup → plain display text
  SwordRepository.swift catalog parsing + download URLs

GodsWord/             SwiftUI iPhone app (iOS 17+)
  Views/              Library → Books → Chapters → Reader, Repository, Settings
  Services/           ModuleStore (install/delete), PersonalData (local),
                      GoogleDriveBackup (opt-in OAuth, no SDK), ModuleLoader
```

`SwordReader` is a clean-room, pure-Swift reader of the SWORD zText format
(little-endian 10-byte verse / 12-byte block indexes, zlib blocks, KJV/NRSV
versification). It was verified against real CrossWire modules: all 31,102
KJV verses render with zero chapter mismatches, plus the full catalog parses
(400+ modules). See `research/` for the format notes and verification scripts.

## Repository & versions

The default repository is CrossWire's
(`https://crosswire.org/ftpmirror/pub/sword/raw`). The app lists modules it can
render (zText, ZIP, whole-book blocks, OSIS, UTF-8, KJV/NRSV versification).
The app does not yet display a module's copyright or license text. Check
CrossWire's module info page for each module before you rely on it (see
[Before you distribute or publish](#before-you-distribute-or-publish)).

## Licensing and Bible texts

### What this repository licenses

- **App and library code** (`GodsWord/`, `SwordReader/`, `tools/`, `research/`,
  `docs/`): MIT, see [LICENSE](LICENSE).
- **SWORD format:** the module format was implemented from reading the SWORD
  sources and format documentation. No SWORD source code is copied into this
  repository, with the one exception below.
- **Versification tables** (`VersificationData.swift`,
  `research/proto/versification.json`) were generated from the verse-count
  tables in SWORD 1.9.0's `include/canon.h` (KJV) and `include/canon_nrsv.h`
  (NRSV). The SWORD software is licensed under the **GNU GPL v2** (per the
  packaged copyright notices of SWORD and its Debian package). The tables hold
  book names and verse counts, not code and not verse text. Whether that
  makes them a derivative of GPL-licensed source is a legal question we have
  not settled. Options before a commercial release: get legal advice, or
  regenerate the tables from a non-GPL source of verse counts.
- **ChiUns-specific Strong's entries** (H9001–H9004, `StrongsLexicon.swift`) are
  prose written for this project, not copied from a module.

### What this repository does not license

- **Bible texts.** No Bible text is stored in this repository or the app. Texts
  are downloaded by you from CrossWire, or imported by you as private files.
  The MIT license does not cover them.
- **Lexicons and dictionaries** (Strong's and others) downloaded from CrossWire
  are third-party works with their own licenses.
- **App icon and name** (`AppIcon-1024.png`, "God's Word") belong to this
  project. Check the name before reusing it elsewhere.

### CrossWire's module policy

CrossWire's copyright policy (wiki.crosswire.org/Copyright) says:

- CrossWire hosts a module only if the text is public domain, or the copyright
  holder has given CrossWire written permission.
- Some modules are **locked**: they are encrypted with a `CipherKey` and need
  a key from the copyright holder. This app does not offer locked modules, and
  it never tries to decrypt or unlock one. Keys bought for other programs
  don't work with SWORD.
- CrossWire's permission covers its hosting. In our reading, it does not by
  itself give you, or this app's users, the right to redistribute a module in
  another product. Check each module's own terms.

### Before you distribute or publish

Downloaded modules are not public domain by default. Some Bible versions are
(for example the KJV in the United States); others are still under copyright.
Before you ship a build, publish screenshots of a particular text, or share a
module file:

1. Look up the module's copyright and license on CrossWire's module info page
   (crosswire.org, by module ID). The app does not show this yet, and the
   CrossWire copyright pages could not be fetched while writing this, so
   confirm the page content yourself.
2. Confirm the license permits the use you intend: personal reading, public
   distribution, or redistribution of the module file.
3. Do not bundle copyrighted modules or their data files in the app or in a
   public release. Ask the copyright holder for permission first.
4. Do not copy, mirror, or re-host module files, and do not try to unlock
   locked modules.
5. For an App Store release, have a lawyer review the module list, the app
   name, the icon, and the SWORD-derived tables above.

To report a copyright concern about a module, write to copyright@crosswire.org.

Private Bible files you import (JSON, see `docs/requirements.md` REQ-IC-11)
are your responsibility. Import only texts you have the right to use.

### Third-party names and trademarks

"Apple", "iPhone", "App Store", and "iCloud" are trademarks of Apple Inc.
"Google" and "Google Drive" are trademarks of Google LLC. "SWORD" and
"CrossWire" are names of the CrossWire Bible Society and its SWORD Project; we
have not checked their trademark registrations. "Strong's" refers to Strong's
Concordance. "God's Word" is also the name of a published Bible translation;
this app is not affiliated with that translation.

### No warranty for Bible content

Bible texts, lexicon entries, and translations are supplied by their
publishers "as is." This project does not check their accuracy and does not
add, correct, or endorse their content.

## Privacy

- Your data (installed Bibles, reading positions, bookmarks, notes, history,
  text size) is stored on your iPhone, or in your own iCloud Drive if you turn
  on iCloud sync.
- Google Drive backup is off until you sign in. It uses the `drive.appdata`
  scope only (see above). Backups are written to your own Drive.
- The app has no analytics, advertising, or developer-run server. Downloads go
  straight from CrossWire's repository to your device.
- Notes and bookmarks are never sent to the developer.

## License

App code: MIT (see LICENSE). Bible texts, lexicon modules, and the GPL-2
SWORD-derived data noted above are not covered by the MIT license; see
[Licensing and Bible texts](#licensing-and-bible-texts).
