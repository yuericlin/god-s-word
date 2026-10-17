// ZipReader.swift
// Minimal ZIP archive reader (stored + deflated entries, UTF-8 names).
// Used to unpack SWORD module packages (*.zip) from the repository.

import Foundation

public enum ZipError: Error, Equatable {
    case notAZip
    case truncated
    case unsupportedMethod(UInt16)
    case encryptedNotSupported
    case invalidName
}

public struct ZipEntry {
    public let name: String
    public let method: UInt16
    public let compressedSize: UInt32
    public let uncompressedSize: UInt32
    public let localHeaderOffset: UInt32
}

private func u16(_ d: [UInt8], _ o: Int) -> UInt16 { UInt16(d[o]) | (UInt16(d[o + 1]) << 8) }
private func u32(_ d: [UInt8], _ o: Int) -> UInt32 {
    UInt32(d[o]) | (UInt32(d[o + 1]) << 8) | (UInt32(d[o + 2]) << 16) | (UInt32(d[o + 3]) << 24)
}

public struct ZipReader {
    private let data: [UInt8]
    public let entries: [ZipEntry]

    public init(data: [UInt8]) throws {
        self.data = data
        // Find End Of Central Directory (search backwards, allow comment).
        var eocd = -1
        var i = data.count - 22
        while i >= 0 && i >= data.count - 22 - 65557 {
            if u32(data, i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let cdCount = Int(u16(data, eocd + 10))
        let cdOffset = Int(u32(data, eocd + 16))
        var entries = [ZipEntry]()
        var p = cdOffset
        for _ in 0 ..< cdCount {
            guard p + 46 <= data.count, u32(data, p) == 0x0201_4B50 else { throw ZipError.truncated }
            let flags = u16(data, p + 8)
            let method = u16(data, p + 10)
            let compSize = u32(data, p + 20)
            let uncompSize = u32(data, p + 24)
            let nameLen = Int(u16(data, p + 28))
            let extraLen = Int(u16(data, p + 30))
            let commentLen = Int(u16(data, p + 32))
            let localOff = u32(data, p + 42)
            guard p + 46 + nameLen <= data.count else { throw ZipError.truncated }
            let nameBytes = Array(data[p + 46 ..< p + 46 + nameLen])
            let isUTF8 = (flags & 0x0800) != 0
            let name: String
            if isUTF8 {
                guard let s = String(bytes: nameBytes, encoding: .utf8) else { throw ZipError.invalidName }
                name = s
            } else {
                name = String(bytes: nameBytes, encoding: .utf8)
                    ?? nameBytes.map { String(format: "%%%02X", $0) }.joined()
            }
            if (flags & 0x0001) != 0 { throw ZipError.encryptedNotSupported }
            entries.append(ZipEntry(name: name, method: method,
                                    compressedSize: compSize, uncompressedSize: uncompSize,
                                    localHeaderOffset: localOff))
            p += 46 + nameLen + extraLen + commentLen
        }
        self.entries = entries
    }

    public func data(for entry: ZipEntry) throws -> [UInt8] {
        let p = Int(entry.localHeaderOffset)
        guard p + 30 <= data.count, u32(data, p) == 0x0403_4B50 else { throw ZipError.truncated }
        let nameLen = Int(u16(data, p + 26))
        let extraLen = Int(u16(data, p + 28))
        let dataStart = p + 30 + nameLen + extraLen
        let dataEnd = dataStart + Int(entry.compressedSize)
        guard dataEnd <= data.count else { throw ZipError.truncated }
        let raw = Array(data[dataStart ..< dataEnd])
        switch entry.method {
        case 0:
            return raw
        case 8:
            return try Inflate.decompressRawDeflate(raw)
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    public func entry(named name: String) -> ZipEntry? {
        entries.first { $0.name == name }
    }
}
