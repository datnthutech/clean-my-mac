import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// One entry returned when listing a directory.
public struct RawEntry: Equatable, Sendable {
    public enum Kind: Sendable { case file, directory, symlink, other }

    public var name: String
    public var kind: Kind
    public var allocatedSize: Int64
    public var logicalSize: Int64
    public var modificationTime: TimeInterval
    public var device: Int64
    public var inode: UInt64
    public var linkCount: UInt32
}

public enum ScanError: Error, Equatable {
    case cannotOpen(path: String, errno: Int32)
    case readFailed(path: String, errno: Int32)
}

/// Lists one directory without following symlinks.
public protocol DirectoryReader: Sendable {
    func read(path: String) throws -> [RawEntry]
}

public enum DirectoryReaders {
    /// The fastest reader for the current platform: `getattrlistbulk` on macOS, `readdir` + `lstat` elsewhere.
    public static var best: DirectoryReader {
        #if os(macOS)
        return BulkDirectoryReader()
        #else
        return POSIXDirectoryReader()
        #endif
    }
}

/// Portable reader built on `opendir`/`readdir`/`lstat`. Used on Linux (tests) and as a reference on macOS.
public struct POSIXDirectoryReader: DirectoryReader {
    public init() {}

    public func read(path: String) throws -> [RawEntry] {
        guard let dir = opendir(path) else {
            throw ScanError.cannotOpen(path: path, errno: errno)
        }
        defer { closedir(dir) }

        var entries: [RawEntry] = []
        let base = path == "/" ? "" : path
        while let ent = readdir(dir) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) { ptr in
                String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." { continue }

            var info = stat()
            guard lstat(base + "/" + name, &info) == 0 else { continue }

            let type = info.st_mode & S_IFMT
            let kind: RawEntry.Kind
            switch type {
            case S_IFREG: kind = .file
            case S_IFDIR: kind = .directory
            case S_IFLNK: kind = .symlink
            default: kind = .other
            }
            #if canImport(Darwin)
            let mtime = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
            #else
            let mtime = TimeInterval(info.st_mtim.tv_sec) + TimeInterval(info.st_mtim.tv_nsec) / 1e9
            #endif
            entries.append(RawEntry(
                name: name,
                kind: kind,
                allocatedSize: Int64(info.st_blocks) * 512,
                logicalSize: Int64(info.st_size),
                modificationTime: mtime,
                device: Int64(info.st_dev),
                inode: UInt64(info.st_ino),
                linkCount: UInt32(info.st_nlink)
            ))
        }
        return entries
    }
}

/// Device id of the file system holding `path`, or nil when it cannot be stat'ed.
public func deviceID(ofPath path: String) -> Int64? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return Int64(info.st_dev)
}
