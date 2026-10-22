// ModuleStore.swift
// Installs, lists, and deletes Bible modules. Modules live in
// Application Support/Modules/<ModuleID>/ preserving the SWORD layout.

import Foundation
import SwordReader

public struct InstalledModule: Identifiable, Sendable, Equatable {
    public let id: String
    public let info: ModuleInfo
    public let moduleDir: URL

    public static func == (lhs: InstalledModule, rhs: InstalledModule) -> Bool { lhs.id == rhs.id }
}

public final class ModuleStore: Sendable {
    public let baseDir: URL

    public init(baseDir: URL? = nil) {
        if let baseDir {
            self.baseDir = baseDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                      in: .userDomainMask).first!
            self.baseDir = appSupport.appendingPathComponent("Modules", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.baseDir,
                                                 withIntermediateDirectories: true)
    }

    /// All installed modules, sorted by display name.
    public func installedModules() -> [InstalledModule] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: baseDir,
                                                     includingPropertiesForKeys: nil,
                                                     options: .skipsHiddenFiles) else { return [] }
        var out = [InstalledModule]()
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let confURL = findConf(in: dir),
                  let text = confText(at: confURL)
            else { continue }
            let conf = SwordConf(text: text)
            let info = ModuleInfo(conf: conf)
            let moduleDir = dir.appendingPathComponent(info.dataDir, isDirectory: true)
            out.append(InstalledModule(id: info.id, info: info, moduleDir: moduleDir))
        }
        return out.sorted { $0.info.description < $1.info.description }
    }

    public func isInstalled(_ moduleID: String) -> Bool {
        installedModules().contains { $0.id == moduleID }
    }

    /// Install a module from its package zip data (a download, or one
    /// written by `exportPackages`). With `moduleID` nil the package's own
    /// id is used; otherwise it must match.
    @discardableResult
    public func install(packageData: [UInt8], moduleID: String? = nil) throws -> InstalledModule {
        let reader = try ZipReader(data: packageData)
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        for entry in reader.entries where !entry.name.hasSuffix("/") {
            // A package from a file the user picked: never write outside tmp.
            guard !entry.name.hasPrefix("/"),
                  !entry.name.split(separator: "/").contains("..")
            else { throw ZipError.invalidName }
            let dest = tmp.appendingPathComponent(entry.name)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(try reader.data(for: entry)).write(to: dest)
        }
        guard let confURL = findConf(in: tmp),
              let text = confText(at: confURL)
        else { throw ModuleStoreError.noConfFound }
        let conf = SwordConf(text: text)
        let id = moduleID ?? conf.moduleID
        guard !id.isEmpty, !id.contains("/"), !id.contains("..")
        else { throw ModuleStoreError.noConfFound }
        guard conf.moduleID == id else { throw ModuleStoreError.idMismatch }
        let dest = baseDir.appendingPathComponent(id, isDirectory: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tmp, to: dest)
        // findConf again under the final location for the module dir
        guard let finalConf = findConf(in: dest),
              let finalText = confText(at: finalConf)
        else { throw ModuleStoreError.noConfFound }
        let info = ModuleInfo(conf: SwordConf(text: finalText))
        return InstalledModule(id: info.id, info: info,
                               moduleDir: dest.appendingPathComponent(info.dataDir, isDirectory: true))
    }

    /// Writes every installed module — Bibles, commentaries, dictionaries
    /// and the rest — to `folder` as `<ModuleID>.zip`, each in the layout of
    /// a CrossWire package, so importing them later (after a reinstall)
    /// needs no trip back to the download sources (REQ-BK-6). Zips left
    /// from an earlier export are removed first. Returns the module count.
    @discardableResult
    public func exportPackages(to folder: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for old in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where old.pathExtension.lowercased() == "zip" {
            try fm.removeItem(at: old)
        }
        var count = 0
        for module in installedModules() {
            let root = baseDir.appendingPathComponent(module.id, isDirectory: true)
            guard fm.fileExists(atPath: root.path) else { continue }
            let zip = try ZipWriter.archive(directory: root)
            try Data(zip).write(to: folder.appendingPathComponent("\(module.id).zip"),
                                options: .atomic)
            count += 1
        }
        return count
    }

    public func delete(_ moduleID: String) throws {
        let dir = baseDir.appendingPathComponent(moduleID, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Reads a .conf file tolerantly (REQ-AP-14): strict UTF-8
    /// rejected older packages whose confs carry Windows-1252
    /// bytes, misreported as "no conf found" at install time.
    private func confText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SwordConf.decodeText([UInt8](data))
    }

    private func findConf(in dir: URL) -> URL? {
        let fm = FileManager.default
        // Fast path: mods.d/<lowercased id>.conf is the CrossWire convention.
        if let subs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                  options: .skipsHiddenFiles) {
            for sub in subs where sub.lastPathComponent == "mods.d" {
                if let confs = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil,
                                                           options: .skipsHiddenFiles) {
                    return confs.first { $0.pathExtension.lowercased() == "conf" }
                }
            }
        }
        // Fallback: recursive scan.
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "conf" {
            return url
        }
        return nil
    }
}

public enum ModuleStoreError: Error {
    case noConfFound
    case idMismatch
    case downloadFailed
}
