// SwordRepository.swift
// Models a SWORD module repository (e.g. CrossWire) and parses its catalog.
// The catalog is mods.d.tar.gz: a gzipped tar of one .conf per module.
// Network fetching lives in the app; parsing here is pure and testable.

import Foundation

/// A Bible module listed in the repository catalog.
public struct ModuleInfo: Sendable {
    public let id: String
    public let description: String
    public let language: String
    public let dataPath: String
    public let versificationName: String
    public let version: String
    public let about: String

    /// True when God's Word v1 can download and render this module:
    /// zText/zText4 driver, ZIP compression, whole-book blocks, OSIS
    /// source, UTF-8 encoding, KJV/NRSV versification (an absent
    /// Versification line means the KJV default), not enciphered.
    public var isRenderable: Bool {
        guard ["ZTEXT", "ZTEXT4"].contains(conf.driver?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""),
              conf.compressType?.trimmingCharacters(in: .whitespaces).uppercased() == "ZIP",
              conf.blockType?.trimmingCharacters(in: .whitespaces).uppercased() == "BOOK",
              conf.sourceType?.trimmingCharacters(in: .whitespaces).uppercased() == "OSIS",
              conf.encoding?.trimmingCharacters(in: .whitespaces).uppercased() == "UTF-8",
              conf.cipherKey == nil
        else { return false }
        let v = conf.versification?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        return v.isEmpty || v == "KJV" || v == "NRSV"
    }

    public var versification: Versification? {
        let name = conf.versification?.trimmingCharacters(in: .whitespaces) ?? ""
        // An absent Versification line means the SWORD default, KJV
        // (e.g. NASB1995 and the NET Bible declare none) — REQ-SRC-4.
        return name.isEmpty ? .kjv : Versification.named(name)
    }

    /// Whether the module text is Chinese (for localized book names).
    public var isChinese: Bool {
        language.lowercased().hasPrefix("zh")
    }

    /// The module's catalog category, e.g. "Biblical Texts" or
    /// "Commentaries" (the conf's Category key; "" when absent).
    public var category: String {
        (conf["Category"] ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// Whether this module is stored in the "4" verse-index format
    /// (12-byte entries, 32-bit verse sizes) used by the zText4 /
    /// zCom4 drivers instead of the classic 10-byte format
    /// (REQ-AP-16). The reader opens the module accordingly.
    public var usesV4Storage: Bool {
        ["ZTEXT4", "ZCOM4"].contains(conf.driver?.trimmingCharacters(in: .whitespaces).uppercased() ?? "")
    }

    /// Whether this module uses a raw (uncompressed) driver —
    /// RawText / RawCom store each testament as a plain data file
    /// (ot / nt) plus a .vss index of 6-byte records (32-bit
    /// offset, 16-bit size) over the same heading-slot ordinals
    /// the compressed drivers use (REQ-AP-17). The reader opens
    /// the module accordingly.
    public var usesRawStorage: Bool {
        ["RAWTEXT", "RAWCOM"].contains(conf.driver?.trimmingCharacters(in: .whitespaces).uppercased() ?? "")
    }

    /// Whether this module is a commentary: its catalog category says so,
    /// or it uses a zCom driver. Commentaries are not Bible versions and
    /// never appear in the version lists.
    public var isCommentary: Bool {
        category.lowercased() == "commentaries"
            || ["ZCOM", "ZCOM4", "RAWCOM"].contains(conf.driver?.trimmingCharacters(in: .whitespaces).uppercased() ?? "")
    }

    /// True when the auxiliary panel can read this commentary: zCom
    /// or zCom4 driver, ZIP compression, whole-book blocks, OSIS or
    /// ThML source, UTF-8 text (an absent Encoding counts — TSK
    /// declares none and is UTF-8 text), KJV/NRSV versification,
    /// not enciphered. A zCom module has the same .bzv/.bzs/.bzz
    /// file layout as zText, so the existing SwordModule reader
    /// reads it (the "4" storage variant included, REQ-AP-16;
    /// verified against MHCC and TDavid). ThML entries pass through
    /// the same plain-text conversion as OSIS ones (verified
    /// against TSK, REQ-AP-14); CHAPTER-block modules (e.g.
    /// NETnotes) are still excluded — their storage differs
    /// (.czv/.czs/.czz files).
    ///
    /// RawCom modules qualify on the same terms, minus the
    /// compression terms (raw drivers store uncompressed entries
    /// and declare no CompressType / BlockType), and GBF joins
    /// OSIS / ThML as a source type: its tags pass through the
    /// same plain-text conversion (verified against DTN,
    /// REQ-AP-17).
    public var isCommentaryRenderable: Bool {
        guard isCommentary, conf.cipherKey == nil else { return false }
        let driver = conf.driver?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        let source = conf.sourceType?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        if ["ZCOM", "ZCOM4"].contains(driver) {
            guard conf.compressType?.trimmingCharacters(in: .whitespaces).uppercased() == "ZIP",
                  conf.blockType?.trimmingCharacters(in: .whitespaces).uppercased() == "BOOK",
                  ["OSIS", "THML"].contains(source)
            else { return false }
        } else if driver == "RAWCOM" {
            guard ["OSIS", "THML", "GBF"].contains(source) else { return false }
        } else { return false }
        let enc = conf.encoding?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        guard enc.isEmpty || enc == "UTF-8" else { return false }
        let v = conf.versification?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        return v.isEmpty || v == "KJV" || v == "NRSV"
    }

    /// Whether this module is a dictionary / lexicon: an LD (lexicon
    /// data) driver module that isn't a glossary or daily devotional
    /// (those use the LD drivers too but aren't dictionaries). Most
    /// dictionary confs declare no Category, so the driver is the
    /// discriminator.
    public var isDictionary: Bool {
        let driver = conf.driver?.trimmingCharacters(in: .whitespaces).uppercased()
        guard driver == "ZLD" || driver == "RAWLD" else { return false }
        let cat = category.lowercased()
        return cat != "glossaries" && cat != "daily devotional"
    }

    /// True when the app can download and read this dictionary: zLD
    /// with ZIP compression or uncompressed RawLD, not enciphered,
    /// UTF-8 text (an absent Encoding means the SWORD default —
    /// StrongsHebrew declares none and is UTF-8). Read positionally
    /// by StrongsLexicon for Strong's-keyed lexicons; other
    /// dictionaries download and install the same way.
    public var isDictionaryRenderable: Bool {
        guard isDictionary, conf.cipherKey == nil else { return false }
        let driver = conf.driver?.trimmingCharacters(in: .whitespaces).uppercased()
        if driver == "ZLD" {
            guard conf.compressType?.trimmingCharacters(in: .whitespaces).uppercased() == "ZIP"
            else { return false }
        }
        let enc = conf.encoding?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        return enc.isEmpty || enc == "UTF-8"
    }

    /// The language's primary subtag, lowercased: "zh-Hans" -> "zh",
    /// "EN" -> "en". Language filtering compares primary subtags, so
    /// a "zh" selection also covers zh-Hans / zh-Hant modules.
    public static func primaryLanguage(of code: String) -> String {
        code.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init) ?? ""
    }

    /// Whether this module passes a download-list language filter
    /// (REQ-LG-1): an empty selection passes everything; otherwise
    /// the module's primary language subtag must be selected. A
    /// module with no declared language passes only an empty filter.
    public func isInLanguages(_ selected: [String]) -> Bool {
        guard !selected.isEmpty else { return true }
        let mine = Self.primaryLanguage(of: language)
        guard !mine.isEmpty else { return false }
        return selected.contains { Self.primaryLanguage(of: $0) == mine }
    }

    /// The module's distribution license as declared in its .conf
    /// (DistributionLicense — e.g. "Public Domain", "Copyrighted"), or
    /// "" when the conf doesn't declare one. Shown in the panel's
    /// commentary info (REQ-AP-8): commentaries are often copyrighted,
    /// and this is the field the copyright holder fills in.
    public var distributionLicense: String {
        (conf["DistributionLicense"] ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// Whether the module carries Strong's numbers
    /// (GlobalOptionFilter=OSISStrongs in its .conf).
    public var supportsStrongs: Bool {
        conf.allValues["GlobalOptionFilter"]?.contains("OSISStrongs") ?? false
    }

    /// Directory holding the module's data files, relative to the module
    /// root with no leading "./" and a trailing "/". Bible DataPaths end
    /// with "/" and are already directories; lexicon DataPaths name the
    /// file base (e.g. ".../strongshebrew/strongshebrew"), so the last
    /// component is dropped.
    public var dataDir: String {
        var p = dataPath
        if p.hasPrefix("./") { p = String(p.dropFirst(2)) }
        if p.hasSuffix("/") { return p }
        guard let slash = p.lastIndex(of: "/") else { return "" }
        return String(p[...slash])
    }

    private let conf: SwordConf

    public init(conf: SwordConf) {
        self.conf = conf
        id = conf.moduleID
        description = conf.displayName
        language = (conf.language ?? "").trimmingCharacters(in: .whitespaces)
        dataPath = (conf.dataPath ?? "").trimmingCharacters(in: .whitespaces)
        versificationName = (conf.versification ?? "").trimmingCharacters(in: .whitespaces)
        version = (conf["Version"] ?? "").trimmingCharacters(in: .whitespaces)
        about = (conf["About"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum RepositoryError: Error, Equatable {
    case badGzip
    case badTar
    case emptyCatalog
}

/// A SWORD module repository root, e.g. https://crosswire.org/ftpmirror/pub/sword/raw
public struct SwordRepository: Sendable {
    public let baseURL: URL
    public let name: String

    public init(name: String, baseURL: URL) {
        self.name = name
        self.baseURL = baseURL
    }

    /// URL of the module catalog.
    public var catalogURL: URL { baseURL.appendingPathComponent("mods.d.tar.gz") }

    /// Download URL for a module package. The file name matches the module ID
    /// (e.g. KJV -> packages/KJV.zip), as published by CrossWire.
    public func packageURL(for moduleID: String) -> URL {
        baseURL.appendingPathComponent("packages/\(moduleID).zip")
    }

    /// Parse catalog data (the raw bytes of mods.d.tar.gz) into module infos.
    public static func parseCatalog(_ tarGz: [UInt8]) throws -> [ModuleInfo] {
        let tar: [UInt8]
        do {
            tar = try Inflate.decompressGzip(tarGz)
        } catch {
            throw RepositoryError.badGzip
        }
        let entries: [TarEntry]
        do {
            entries = try TarReader.read(tar)
        } catch {
            throw RepositoryError.badTar
        }
        var modules = [ModuleInfo]()
        for entry in entries where entry.name.hasSuffix(".conf") {
            // Tolerant decoding (REQ-AP-14): a conf with legacy
            // Windows-1252 bytes must not vanish from the catalog.
            let conf = SwordConf(text: SwordConf.decodeText(entry.bytes))
            guard !conf.moduleID.isEmpty else { continue }
            modules.append(ModuleInfo(conf: conf))
        }
        guard !modules.isEmpty else { throw RepositoryError.emptyCatalog }
        return modules.sorted { $0.id.lowercased() < $1.id.lowercased() }
    }
}
