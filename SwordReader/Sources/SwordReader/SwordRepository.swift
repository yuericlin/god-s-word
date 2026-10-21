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
    /// zText driver, ZIP compression, whole-book blocks, OSIS source,
    /// UTF-8 encoding, KJV/NRSV versification, not enciphered.
    public var isRenderable: Bool {
        guard conf.driver?.trimmingCharacters(in: .whitespaces) == "zText",
              conf.compressType?.trimmingCharacters(in: .whitespaces) == "ZIP",
              conf.blockType?.trimmingCharacters(in: .whitespaces) == "BOOK",
              conf.sourceType?.trimmingCharacters(in: .whitespaces) == "OSIS",
              conf.encoding?.trimmingCharacters(in: .whitespaces).uppercased() == "UTF-8",
              conf.cipherKey == nil
        else { return false }
        let v = conf.versification?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        return v == "KJV" || v == "NRSV"
    }

    public var versification: Versification? {
        Versification.named(conf.versification?.trimmingCharacters(in: .whitespaces) ?? "")
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

    /// Whether this module is a commentary: its catalog category says so,
    /// or it uses the zCom driver. Commentaries are not Bible versions and
    /// never appear in the version lists.
    public var isCommentary: Bool {
        category.lowercased() == "commentaries"
            || conf.driver?.trimmingCharacters(in: .whitespaces) == "zCom"
    }

    /// True when the auxiliary panel can read this commentary: zCom
    /// driver, ZIP compression, whole-book blocks, OSIS source, UTF-8
    /// encoding, KJV/NRSV versification, not enciphered. A zCom module
    /// has the same .bzv/.bzs/.bzz file layout as zText, so the existing
    /// SwordModule reader reads it unmodified (verified against MHCC).
    /// ThML commentaries (e.g. TSK) are not renderable yet.
    public var isCommentaryRenderable: Bool {
        guard isCommentary,
              conf.driver?.trimmingCharacters(in: .whitespaces) == "zCom",
              conf.compressType?.trimmingCharacters(in: .whitespaces) == "ZIP",
              conf.blockType?.trimmingCharacters(in: .whitespaces) == "BOOK",
              conf.sourceType?.trimmingCharacters(in: .whitespaces) == "OSIS",
              conf.encoding?.trimmingCharacters(in: .whitespaces).uppercased() == "UTF-8",
              conf.cipherKey == nil
        else { return false }
        let v = conf.versification?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        return v == "KJV" || v == "NRSV"
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
            guard let text = String(bytes: entry.bytes, encoding: .utf8) else { continue }
            let conf = SwordConf(text: text)
            guard !conf.moduleID.isEmpty else { continue }
            modules.append(ModuleInfo(conf: conf))
        }
        guard !modules.isEmpty else { throw RepositoryError.emptyCatalog }
        return modules.sorted { $0.id.lowercased() < $1.id.lowercased() }
    }
}
