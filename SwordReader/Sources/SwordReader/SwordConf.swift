// SwordConf.swift
// Parser for SWORD module .conf files (mirrors SWConfig::load semantics:
// '#' comments, [Section] headers, key=value split at the first '=').

import Foundation

public struct SwordConf: Sendable {
    public let moduleID: String
    /// First occurrence wins for repeated keys (mirrors multimap read order for our keys).
    public let values: [String: String]

    public init(text: String) {
        var moduleID = ""
        var values = [String: String]()
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
            if values[key] == nil { values[key] = value }
        }
        self.moduleID = moduleID
        self.values = values
    }

    public subscript(key: String) -> String? { values[key] }

    public var dataPath: String? { self["DataPath"] }
    public var driver: String? { self["ModDrv"] }
    public var sourceType: String? { self["SourceType"] }
    public var encoding: String? { self["Encoding"] }
    public var compressType: String? { self["CompressType"] }
    public var blockType: String? { self["BlockType"] }
    public var versification: String? { self["Versification"] }
    public var language: String? { self["Lang"] }
    public var cipherKey: String? { self["CipherKey"] }

    public var displayName: String {
        values["Description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? moduleID
    }
}
