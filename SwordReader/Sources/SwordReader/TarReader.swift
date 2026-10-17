// TarReader.swift
// Minimal POSIX tar reader (regular files only). Used to unpack the
// repository catalog mods.d.tar.gz after gunzip.

import Foundation

public enum TarError: Error, Equatable {
    case truncated
    case invalidHeader
}

public struct TarEntry {
    public let name: String
    public let bytes: [UInt8]
}

private func cString(_ d: [UInt8], _ offset: Int, _ maxLen: Int) -> String {
    var end = offset
    while end < offset + maxLen && d[end] != 0 { end += 1 }
    return String(bytes: Array(d[offset ..< end]), encoding: .utf8) ?? ""
}

private func octal(_ d: [UInt8], _ offset: Int, _ len: Int) -> Int {
    var s = ""
    for i in offset ..< offset + len {
        let c = d[i]
        if c == 0 || c == 32 { continue }
        s.append(Character(UnicodeScalar(c)))
    }
    return Int(s, radix: 8) ?? 0
}

public enum TarReader {
    public static func read(_ data: [UInt8]) throws -> [TarEntry] {
        var entries = [TarEntry]()
        var p = 0
        var zeroBlocks = 0
        while p + 512 <= data.count {
            let block = Array(data[p ..< p + 512])
            if block.allSatisfy({ $0 == 0 }) {
                zeroBlocks += 1
                if zeroBlocks == 2 { break }
                p += 512
                continue
            }
            zeroBlocks = 0
            let name = cString(block, 0, 100)
            let prefix = cString(block, 345, 155)
            let fullName = prefix.isEmpty ? name : prefix + "/" + name
            let size = octal(block, 124, 12)
            let typeflag = block[156]
            guard !fullName.isEmpty else { throw TarError.invalidHeader }
            p += 512
            let isFile = typeflag == 0 || typeflag == 48 // '\0' or '0'
            if isFile && size > 0 {
                guard p + size <= data.count else { throw TarError.truncated }
                entries.append(TarEntry(name: fullName, bytes: Array(data[p ..< p + size])))
            }
            p += (size + 511) / 512 * 512
        }
        return entries
    }
}
