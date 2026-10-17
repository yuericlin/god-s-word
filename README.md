# God's Word

A minimalistic iPhone Bible reader. Download any Bible version from the
[CrossWire Bible Society](https://crosswire.org) module repository and read
one chapter at a time — nothing else.

## Features

- **Any version, on demand** — browse the CrossWire repository inside the app
  and download Bible modules (KJV, 和合本, and 100+ more). No bundled text,
  no account needed.
- **One chapter at a time** — a calm reader: Library → Books → Chapters → text.
  Swipe or tap to move between chapters. Verse numbers, adjustable text size.
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
  VersificationData.swift  generated KJV/NRSV tables (from SWORD's canon.h)
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

The default repository is CrossWire's (`https://crosswire.org/ftpmirror/pub/sword/raw`).
The app lists modules it can render (zText, ZIP, whole-book blocks, OSIS,
UTF-8, KJV/NRSV versification). Bible texts belong to their respective
copyright holders — check each module's `About` text for its license.

## License

App code: MIT (see LICENSE). SWORD module *format* knowledge is clean-room
from reading the SWORD sources; no SWORD code is included.
