// ModuleLoader.swift
// Caches open SwordModule instances so chapter rendering stays fast.

import Foundation
import SwordReader

public actor ModuleLoader {
    public static let shared = ModuleLoader()
    private var cache = [String: SwordModule]()

    public func module(for installed: InstalledModule) throws -> SwordModule {
        if let hit = cache[installed.id] { return hit }
        guard let v11n = installed.info.versification else { throw LoaderError.unsupported }
        let mod = try SwordModule(moduleDir: installed.moduleDir, versification: v11n,
                                  format: installed.info.usesV4Storage ? .zVerse4 : .zVerse)
        if cache.count > 3 { cache.removeAll() }
        cache[installed.id] = mod
        return mod
    }

    public func evict(_ moduleID: String) { cache.removeValue(forKey: moduleID) }
    public func evictAll() { cache.removeAll() }
}

public enum LoaderError: Error {
    case unsupported
}
