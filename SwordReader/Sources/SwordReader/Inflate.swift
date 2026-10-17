// Inflate.swift
// Pure-Swift DEFLATE decompressor (RFC 1951) plus the zlib wrapper (RFC 1950)
// used by SWORD zText module blocks. No dependencies, works on Linux and iOS.

import Foundation

public enum InflateError: Error, Equatable {
    case truncated
    case invalidBlockType
    case invalidHuffmanCode
    case invalidLengthOrDistance
    case invalidStoredBlock
    case invalidZlibHeader
    case adlerMismatch
    case outputTooLarge
}

/// Reads bits LSB-first from a byte array, per RFC 1951.
struct BitReader {
    private let bytes: [UInt8]
    private var index: Int = 0
    private var buffer: UInt64 = 0
    private var available: Int = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { index >= bytes.count && available == 0 }

    /// Byte offset just past the last byte pulled into the bit buffer.
    /// Call after alignToByte() to learn where a deflate stream ended.
    var bytesConsumed: Int { index }

    mutating func readBits(_ count: Int) throws -> UInt32 {
        precondition(count >= 0 && count <= 32)
        while available < count {
            guard index < bytes.count else { throw InflateError.truncated }
            buffer |= UInt64(bytes[index]) << available
            index += 1
            available += 8
        }
        let mask: UInt64 = count == 64 ? .max : (UInt64(1) << count) - 1
        let value = UInt32(buffer & mask)
        buffer >>= count
        available -= count
        return value
    }

    mutating func readBit() throws -> UInt32 { try readBits(1) }

    mutating func alignToByte() {
        let skip = available % 8
        buffer >>= skip
        available -= skip
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        alignToByte()
        guard index + count <= bytes.count else { throw InflateError.truncated }
        let out = Array(bytes[index ..< index + count])
        index += count
        return out
    }

    mutating func readUInt16LE() throws -> UInt16 {
        let b = try readBytes(2)
        return UInt16(b[0]) | (UInt16(b[1]) << 8)
    }
}

/// Canonical Huffman decoder built from per-symbol code lengths.
struct HuffmanDecoder {
    private let maxBits: Int
    private let counts: [Int]   // counts[length], length in 1...maxBits
    private let offsets: [Int]  // offsets[length] = first symbol index for codes of `length`
    private let symbols: [Int]  // symbols in canonical order

    init(codeLengths: [Int]) throws {
        let maxBits = codeLengths.max() ?? 0
        guard maxBits > 0 && maxBits <= 16 else { throw InflateError.invalidHuffmanCode }
        self.maxBits = maxBits
        var counts = [Int](repeating: 0, count: maxBits + 1)
        for len in codeLengths where len > 0 { counts[len] += 1 }
        var offsets = [Int](repeating: 0, count: maxBits + 1)
        for len in 2 ... maxBits { offsets[len] = offsets[len - 1] + counts[len - 1] }
        var ordered = [Int]()
        ordered.reserveCapacity(codeLengths.count)
        for len in 1 ... maxBits {
            for (sym, l) in codeLengths.enumerated() where l == len { ordered.append(sym) }
        }
        self.counts = counts
        self.offsets = offsets
        self.symbols = ordered
    }

    /// Convenience: symbols already in canonical order need no reorder, but the
    /// general path above handles it. Kept simple and obviously correct.
    mutating func decode(_ reader: inout BitReader) throws -> Int {
        var code = 0
        var first = 0
        for len in 1 ... maxBits {
            code = (code << 1) | Int(try reader.readBit())
            let count = counts[len]
            if code >= first && code - first < count {
                return symbols[offsets[len] + (code - first)]
            }
            first = (first + count) << 1
        }
        throw InflateError.invalidHuffmanCode
    }
}

private let lengthBases: [Int] =
    [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
     35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
private let lengthExtras: [Int] =
    [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
     3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
private let distanceBases: [Int] =
    [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
     257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
     8193, 12289, 16385, 24577]
private let distanceExtras: [Int] =
    [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
     7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

private func fixedLiteralDecoder() throws -> HuffmanDecoder {
    var lengths = [Int](repeating: 0, count: 288)
    for i in 0 ..< 144 { lengths[i] = 8 }
    for i in 144 ..< 256 { lengths[i] = 9 }
    for i in 256 ..< 280 { lengths[i] = 7 }
    for i in 280 ..< 288 { lengths[i] = 8 }
    return try HuffmanDecoder(codeLengths: lengths)
}

private func fixedDistanceDecoder() throws -> HuffmanDecoder {
    return try HuffmanDecoder(codeLengths: [Int](repeating: 5, count: 32))
}

private let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

/// Maximum decompressed output accepted from a single block (safety cap).
private let maxOutputSize = 256 * 1024 * 1024

public enum Inflate {
    /// Decompress a raw DEFLATE stream (RFC 1951), as used in ZIP entries.
    public static func decompressRawDeflate(_ data: [UInt8]) throws -> [UInt8] {
        try decompressRawDeflateCounted(data).output
    }

    /// Decompress a raw DEFLATE stream, also reporting how many input bytes
    /// the stream consumed (the stream may be followed by padding/checksums).
    static func decompressRawDeflateCounted(_ data: [UInt8]) throws -> (output: [UInt8], consumed: Int) {
        var reader = BitReader(data)
        var output = [UInt8]()
        output.reserveCapacity(min(data.count * 3, 1 << 20))
        var isFinal = false
        while !isFinal {
            isFinal = try reader.readBit() == 1
            let blockType = try reader.readBits(2)
            switch blockType {
            case 0: // stored (no compression)
                reader.alignToByte()
                let len = Int(try reader.readUInt16LE())
                let nlen = try reader.readUInt16LE()
                guard len ^ 0xFFFF == Int(nlen) else { throw InflateError.invalidStoredBlock }
                let chunk = try reader.readBytes(len)
                guard output.count + chunk.count <= maxOutputSize else { throw InflateError.outputTooLarge }
                output.append(contentsOf: chunk)
            case 1: // fixed Huffman
                var lit = try fixedLiteralDecoder()
                var dist = try fixedDistanceDecoder()
                try decodeHuffmanBlock(reader: &reader, lit: &lit, dist: &dist, output: &output)
            case 2: // dynamic Huffman
                let hlit = Int(try reader.readBits(5)) + 257
                let hdist = Int(try reader.readBits(5)) + 1
                let hclen = Int(try reader.readBits(4)) + 4
                var clLengths = [Int](repeating: 0, count: 19)
                for i in 0 ..< hclen { clLengths[codeLengthOrder[i]] = Int(try reader.readBits(3)) }
                var clDecoder = try HuffmanDecoder(codeLengths: clLengths)
                var lengths = [Int]()
                lengths.reserveCapacity(hlit + hdist)
                while lengths.count < hlit + hdist {
                    let sym = try clDecoder.decode(&reader)
                    switch sym {
                    case 0 ... 15:
                        lengths.append(sym)
                    case 16:
                        let repeatCount = Int(try reader.readBits(2)) + 3
                        guard let last = lengths.last else { throw InflateError.invalidHuffmanCode }
                        lengths.append(contentsOf: repeatElement(last, count: repeatCount))
                    case 17:
                        let repeatCount = Int(try reader.readBits(3)) + 3
                        lengths.append(contentsOf: repeatElement(0, count: repeatCount))
                    case 18:
                        let repeatCount = Int(try reader.readBits(7)) + 11
                        lengths.append(contentsOf: repeatElement(0, count: repeatCount))
                    default:
                        throw InflateError.invalidHuffmanCode
                    }
                }
                guard lengths.count == hlit + hdist else { throw InflateError.invalidHuffmanCode }
                var lit = try HuffmanDecoder(codeLengths: Array(lengths[0 ..< hlit]))
                var dist = try HuffmanDecoder(codeLengths: Array(lengths[hlit ..< hlit + hdist]))
                try decodeHuffmanBlock(reader: &reader, lit: &lit, dist: &dist, output: &output)
            default:
                throw InflateError.invalidBlockType
            }
        }
        reader.alignToByte()
        return (output, reader.bytesConsumed)
    }

    private static func decodeHuffmanBlock(reader: inout BitReader,
                                          lit: inout HuffmanDecoder,
                                          dist: inout HuffmanDecoder,
                                          output: inout [UInt8]) throws {
        while true {
            let sym = try lit.decode(&reader)
            if sym < 256 {
                guard output.count + 1 <= maxOutputSize else { throw InflateError.outputTooLarge }
                output.append(UInt8(sym))
            } else if sym == 256 {
                return
            } else if sym <= 285 {
                let li = sym - 257
                let length = lengthBases[li] + Int(try reader.readBits(lengthExtras[li]))
                let dsym = try dist.decode(&reader)
                guard dsym < 30 else { throw InflateError.invalidLengthOrDistance }
                let distance = distanceBases[dsym] + Int(try reader.readBits(distanceExtras[dsym]))
                guard distance >= 1 && distance <= output.count else { throw InflateError.invalidLengthOrDistance }
                guard output.count + length <= maxOutputSize else { throw InflateError.outputTooLarge }
                for _ in 0 ..< length {
                    output.append(output[output.count - distance])
                }
            } else {
                throw InflateError.invalidLengthOrDistance
            }
        }
    }

    /// Decompress a zlib-wrapped stream (RFC 1950), as used in SWORD .bzz blocks.
    /// The Adler-32 checksum immediately follows the deflate stream; any
    /// trailing padding (SWORD pads blocks) is ignored, mirroring zlib.
    public static func decompressZlib(_ data: [UInt8]) throws -> [UInt8] {
        guard data.count >= 6 else { throw InflateError.truncated }
        let cmf = Int(data[0]), flg = Int(data[1])
        guard (cmf * 256 + flg) % 31 == 0, cmf & 0x0F == 8, flg & 0x20 == 0
        else { throw InflateError.invalidZlibHeader }
        let body = Array(data[2...])
        let (output, consumed) = try decompressRawDeflateCounted(body)
        let adlerAt = 2 + consumed
        guard adlerAt + 4 <= data.count else { throw InflateError.truncated }
        let stored = (UInt32(data[adlerAt]) << 24)
            | (UInt32(data[adlerAt + 1]) << 16)
            | (UInt32(data[adlerAt + 2]) << 8)
            | UInt32(data[adlerAt + 3])
        guard adler32(output) == stored else { throw InflateError.adlerMismatch }
        return output
    }

    /// Decompress a gzip member (RFC 1952), as used for mods.d.tar.gz.
    /// The CRC32/ISIZE trailer is validated lightly (ISIZE); trailing data
    /// after the member is ignored.
    public static func decompressGzip(_ data: [UInt8]) throws -> [UInt8] {
        guard data.count >= 18, data[0] == 0x1F, data[1] == 0x8B, data[2] == 0x08
        else { throw InflateError.invalidZlibHeader }
        let flg = data[3]
        var p = 10
        if flg & 0x04 != 0 { // FEXTRA
            guard p + 2 <= data.count else { throw InflateError.truncated }
            let xlen = Int(data[p]) | (Int(data[p + 1]) << 8)
            p += 2 + xlen
        }
        if flg & 0x08 != 0 { // FNAME
            while p < data.count && data[p] != 0 { p += 1 }
            p += 1
        }
        if flg & 0x10 != 0 { // FCOMMENT
            while p < data.count && data[p] != 0 { p += 1 }
            p += 1
        }
        if flg & 0x02 != 0 { p += 2 } // FHCRC
        guard p <= data.count else { throw InflateError.truncated }
        let (output, consumed) = try decompressRawDeflateCounted(Array(data[p...]))
        let trailerAt = p + consumed
        guard trailerAt + 8 <= data.count else { throw InflateError.truncated }
        let isize = UInt32(data[trailerAt + 4]) | (UInt32(data[trailerAt + 5]) << 8)
            | (UInt32(data[trailerAt + 6]) << 16) | (UInt32(data[trailerAt + 7]) << 24)
        guard isize == UInt32(output.count & 0xFFFF_FFFF) else { throw InflateError.adlerMismatch }
        return output
    }

    /// Adler-32 checksum (RFC 1950).
    public static func adler32(_ data: [UInt8]) -> UInt32 {
        let mod: UInt32 = 65521
        var a: UInt32 = 1, b: UInt32 = 0
        var i = 0
        while i < data.count {
            let chunk = min(data.count - i, 5552)
            for j in i ..< i + chunk {
                a &+= UInt32(data[j])
                b &+= a
            }
            a %= mod; b %= mod
            i += chunk
        }
        return (b << 16) | a
    }
}
