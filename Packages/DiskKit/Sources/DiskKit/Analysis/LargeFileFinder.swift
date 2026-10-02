import Foundation

public struct LargeFile: Hashable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let allocatedSize: Int64
    public let modificationDate: Date
    public let category: StorageCategory
}

public enum LargeFileFinder {
    /// The `limit` largest files of at least `minimumSize` bytes, largest first.
    public static func largestFiles(in root: DirectoryNode, minimumSize: Int64 = 100 * ByteFormatter.megabyte, limit: Int = 200) -> [LargeFile] {
        var found: [LargeFile] = []
        root.forEachFile { dir, file in
            guard file.allocatedSize >= minimumSize else { return }
            found.append(LargeFile(
                path: dir.childPath(file.name),
                name: file.name,
                allocatedSize: file.allocatedSize,
                modificationDate: file.modificationDate,
                category: Categorizer.category(forFileName: file.name)
            ))
        }
        found.sort { $0.allocatedSize > $1.allocatedSize }
        return Array(found.prefix(limit))
    }
}
