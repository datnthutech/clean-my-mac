#if os(macOS)
import Darwin
import Foundation

/// Fast directory reader using `getattrlistbulk(2)`: one system call returns the
/// name, type and size of many entries at once instead of one `lstat` per file.
public struct BulkDirectoryReader: DirectoryReader {
    // Attribute bits (sys/attr.h). Declared locally as UInt32 so the high bit imports cleanly.
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnDevID: UInt32 = 0x0000_0002
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnModTime: UInt32 = 0x0000_0400
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004
    private static let fileDataLength: UInt32 = 0x0000_0200

    // vtype values (sys/vnode.h)
    private static let vReg: UInt32 = 1
    private static let vDir: UInt32 = 2
    private static let vLnk: UInt32 = 5

    private static let bufferSize = 256 * 1024

    public init() {}

    public func read(path: String) throws -> [RawEntry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ScanError.cannotOpen(path: path, errno: errno) }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        request.commonattr = Self.cmnReturnedAttrs | Self.cmnName | Self.cmnDevID
            | Self.cmnObjType | Self.cmnModTime | Self.cmnFileID
        request.fileattr = Self.fileLinkCount | Self.fileAllocSize | Self.fileDataLength

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var entries: [RawEntry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, Self.bufferSize, 0)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw ScanError.readFailed(path: path, errno: errno)
            }
            var cursor = UnsafeRawPointer(buffer)
            for _ in 0..<Int(count) {
                let entryStart = cursor
                let length = Int(cursor.loadUnaligned(as: UInt32.self))
                if let entry = Self.parse(entryStart + 4) {
                    entries.append(entry)
                }
                cursor = entryStart + length
            }
        }
        return entries
    }

    /// Parses one record. Attributes appear in bit order and only when present in the returned set.
    private static func parse(_ start: UnsafeRawPointer) -> RawEntry? {
        var field = start
        let returnedCommon = field.loadUnaligned(as: UInt32.self)
        let returnedFile = (field + 12).loadUnaligned(as: UInt32.self)
        field += MemoryLayout<attribute_set_t>.size

        var name = ""
        if returnedCommon & cmnName != 0 {
            let offset = Int(field.loadUnaligned(as: Int32.self))
            let length = Int((field + 4).loadUnaligned(as: UInt32.self))
            if length > 1 {
                let bytes = UnsafeRawBufferPointer(start: field + offset, count: length - 1)
                name = String(decoding: bytes, as: UTF8.self)
            }
            field += MemoryLayout<attrreference_t>.size
        }
        var device: Int64 = 0
        if returnedCommon & cmnDevID != 0 {
            device = Int64(field.loadUnaligned(as: Int32.self))
            field += MemoryLayout<dev_t>.size
        }
        var objType: UInt32 = 0
        if returnedCommon & cmnObjType != 0 {
            objType = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<fsobj_type_t>.size
        }
        var modTime: TimeInterval = 0
        if returnedCommon & cmnModTime != 0 {
            let seconds = field.loadUnaligned(as: Int.self)
            let nanos = (field + MemoryLayout<Int>.size).loadUnaligned(as: Int.self)
            modTime = TimeInterval(seconds) + TimeInterval(nanos) / 1e9
            field += MemoryLayout<timespec>.size
        }
        var inode: UInt64 = 0
        if returnedCommon & cmnFileID != 0 {
            inode = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }
        var linkCount: UInt32 = 1
        if returnedFile & fileLinkCount != 0 {
            linkCount = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }
        var allocated: Int64 = 0
        if returnedFile & fileAllocSize != 0 {
            allocated = field.loadUnaligned(as: Int64.self)
            field += MemoryLayout<off_t>.size
        }
        var logical: Int64 = 0
        if returnedFile & fileDataLength != 0 {
            logical = field.loadUnaligned(as: Int64.self)
            field += MemoryLayout<off_t>.size
        }

        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        let kind: RawEntry.Kind
        switch objType {
        case vReg: kind = .file
        case vDir: kind = .directory
        case vLnk: kind = .symlink
        default: kind = .other
        }
        return RawEntry(
            name: name,
            kind: kind,
            allocatedSize: allocated,
            logicalSize: logical,
            modificationTime: modTime,
            device: device,
            inode: inode,
            linkCount: linkCount
        )
    }
}
#endif
