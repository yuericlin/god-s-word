// SwordConf.swift
// Parser for SWORD module .conf files (mirrors SWConfig::load semantics:
// '#' comments, [Section] headers, key=value split at the first '=').

import Foundation

public struct SwordConf: Sendable {
    public let moduleID: String
    /// First occurrence wins for repeated keys (mirrors multimap read order for our keys).
    public let values: [String: String]
    /// Every occurrence, in file order (e.g. repeated GlobalOptionFilter lines).
    public let allValues: [String: [String]]

    public init(text: String) {
        var moduleID = ""
        var values = [String: String]()
        var allValues = [String: [String]]()
        var content = text
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                if let end = line.firstIndex(of: "]") {
                    moduleID = String(line[line.index(after: line.startIndex) ..< end])
                }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex ..< eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            allValues[key, default: []].append(value)
            if values[key] == nil { values[key] = value }
        }
        self.moduleID = moduleID
        self.values = values
        self.allValues = allValues
    }

    public subscript(key: String) -> String? { values[key] }

    /// Decodes raw .conf bytes to text. Confs are supposed to be
    /// UTF-8, but older packages — Bible.org's above all — carry
    /// Windows-1252 bytes (® © “ ” ’) in fields like About and
    /// Copyright. Strict UTF-8 decoding rejected those confs
    /// outright, which made their modules fail to install
    /// ("no conf found") or vanish from repository catalogs
    /// (REQ-AP-14). Decode as UTF-8 when valid, else Windows-1252
    /// (which also covers Latin-1), else Latin-1 so it never fails.
    public static func decodeText(_ bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .windowsCP1252)
            ?? String(bytes: bytes, encoding: .isoLatin1)
            ?? ""
    }

    public var dataPath: String? { self["DataPath"] }
    public var driver: String? { self["ModDrv"] }
    public var sourceType: String? { self["SourceType"] }
    public var encoding: String? { self["Encoding"] }
    public var compressType: String? { self["CompressType"] }
    public var blockType: String? { self["BlockType"] }
    public var versification: String? { self["Versification"] }
    public var language: String? { self["Lang"] }
    /// The module's unlock key, when it is actually locked. Some confs
    /// carry an empty `CipherKey=` line (e.g. the NET Bible, NA28);
    /// in SWORD semantics that means not enciphered.
    public var cipherKey: String? {
        guard let key = self["CipherKey"]?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty else { return nil }
        return key
    }

    public var displayName: String {
        values["Description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? moduleID
    }
}
