import Foundation
import Compression

enum ZipError: LocalizedError {
    case notAZip, unsupported, corrupt
    var errorDescription: String? {
        switch self {
        case .notAZip: return "This file isn't a valid EPUB (ZIP) archive."
        case .unsupported: return "This archive uses a compression method PaperFront can't read."
        case .corrupt: return "The archive appears to be damaged."
        }
    }
}

/// Just enough of a ZIP reader to open EPUB files (stored + deflate entries).
struct MiniZip {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let localOffset: Int
    }

    private let data: Data
    private(set) var entries: [Entry] = []

    init(data: Data) throws {
        self.data = Data(data) // normalise indices to start at 0
        guard self.data.count > 22 else { throw ZipError.notAZip }

        var eocd = -1
        var i = self.data.count - 22
        let lowest = max(0, self.data.count - 22 - 65535)
        while i >= lowest {
            if self.data[i] == 0x50, self.data[i + 1] == 0x4b, self.data[i + 2] == 0x05, self.data[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let count = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        for _ in 0..<count {
            guard p + 46 <= self.data.count, u32(p) == 0x02014b50 else { throw ZipError.corrupt }
            let method = u16(p + 10)
            let csize = Int(u32(p + 20))
            let size = Int(u32(p + 24))
            let nameLen = Int(u16(p + 28))
            let extraLen = Int(u16(p + 30))
            let commentLen = Int(u16(p + 32))
            let offset = Int(u32(p + 42))
            guard p + 46 + nameLen <= self.data.count else { throw ZipError.corrupt }
            let nameData = self.data.subdata(in: (p + 46)..<(p + 46 + nameLen))
            let name = String(decoding: nameData, as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: csize, size: size, localOffset: offset))
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.name == name } ?? entries.first { $0.name.lowercased() == name.lowercased() }
    }

    func read(_ entry: Entry) throws -> Data {
        let h = entry.localOffset
        guard h + 30 <= data.count, u32(h) == 0x04034b50 else { throw ZipError.corrupt }
        let start = h + 30 + Int(u16(h + 26)) + Int(u16(h + 28))
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count else { throw ZipError.corrupt }
        let raw = data.subdata(in: start..<end)

        switch entry.method {
        case 0:
            return raw
        case 8:
            guard entry.size > 0 else { return Data() }
            var out = [UInt8](repeating: 0, count: entry.size)
            let written = raw.withUnsafeBytes { src -> Int in
                guard let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return out.withUnsafeMutableBufferPointer { dst in
                    compression_decode_buffer(dst.baseAddress!, entry.size, s, raw.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.size else { throw ZipError.corrupt }
            return Data(out)
        default:
            throw ZipError.unsupported
        }
    }

    private func u16(_ o: Int) -> UInt16 {
        UInt16(data[o]) | UInt16(data[o + 1]) << 8
    }

    private func u32(_ o: Int) -> UInt32 {
        UInt32(data[o]) | UInt32(data[o + 1]) << 8 | UInt32(data[o + 2]) << 16 | UInt32(data[o + 3]) << 24
    }
}
