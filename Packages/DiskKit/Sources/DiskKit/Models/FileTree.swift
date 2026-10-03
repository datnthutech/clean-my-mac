import Foundation

/// A regular file found during a scan. Stored inline in its parent directory to keep memory low.
public struct FileEntry: Hashable, Sendable {
    public let name: String
    /// Bytes actually occupied on disk (allocated blocks). This is what frees up when the file is deleted.
    public let allocatedSize: Int64
    /// The file's logical length.
    public let logicalSize: Int64
    public let modificationDate: Date

    public init(name: String, allocatedSize: Int64, logicalSize: Int64, modificationDate: Date) {
        self.name = name
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.modificationDate = modificationDate
    }
}

/// A directory in the scanned tree.
///
/// Thread-safety: during a scan each node is written only by the worker that lists it,
/// and read only after all workers have finished. After the scan, mutate on one thread only.
public final class DirectoryNode: @unchecked Sendable, Identifiable {
    public let name: String
    public let path: String
    public private(set) weak var parent: DirectoryNode?
    public let isPackage: Bool
    public internal(set) var modificationDate: Date?
    public internal(set) var files: [FileEntry] = []
    public internal(set) var directories: [DirectoryNode] = []
    /// True when the directory could not be listed (usually missing Full Disk Access).
    public internal(set) var isUnreadable = false

    /// Recursive totals, filled in by `finalize()`.
    public internal(set) var allocatedSize: Int64 = 0
    public internal(set) var fileCount: Int = 0

    public var id: String { path }

    public init(name: String, path: String, parent: DirectoryNode?, isPackage: Bool = false) {
        self.name = name
        self.path = path
        self.parent = parent
        self.isPackage = isPackage
    }

    public func childPath(_ childName: String) -> String {
        path == "/" ? "/" + childName : path + "/" + childName
    }

    /// Computes recursive sizes bottom-up and sorts children largest first. Iterative to survive deep trees.
    func finalize() {
        var postOrder: [DirectoryNode] = []
        var stack: [DirectoryNode] = [self]
        while let node = stack.popLast() {
            postOrder.append(node)
            stack.append(contentsOf: node.directories)
        }
        for node in postOrder.reversed() {
            var size: Int64 = 0
            var count = 0
            for file in node.files {
                size += file.allocatedSize
            }
            count += node.files.count
            for dir in node.directories {
                size += dir.allocatedSize
                count += dir.fileCount
            }
            node.allocatedSize = size
            node.fileCount = count
            node.files.sort { $0.allocatedSize > $1.allocatedSize }
            node.directories.sort { $0.allocatedSize > $1.allocatedSize }
        }
    }

    /// Finds a descendant (or self) by absolute path.
    public func node(atPath target: String) -> DirectoryNode? {
        if target == path { return self }
        let prefix = path == "/" ? "/" : path + "/"
        guard target.hasPrefix(prefix) else { return nil }
        let remainder = target.dropFirst(prefix.count)
        var current: DirectoryNode = self
        for component in remainder.split(separator: "/") {
            guard let next = current.directories.first(where: { $0.name == component }) else { return nil }
            current = next
        }
        return current
    }

    /// Removes a file or sub-directory at `target` (after it was moved to Trash) and updates ancestor totals.
    /// Returns the number of bytes removed, or nil when the path is not in this tree.
    @discardableResult
    public func removeItem(atPath target: String) -> Int64? {
        let parentPath = (target as NSString).deletingLastPathComponent
        let itemName = (target as NSString).lastPathComponent
        guard let owner = node(atPath: parentPath.isEmpty ? "/" : parentPath) else { return nil }

        var removedBytes: Int64 = 0
        var removedFiles = 0
        if let index = owner.directories.firstIndex(where: { $0.name == itemName }) {
            removedBytes = owner.directories[index].allocatedSize
            removedFiles = owner.directories[index].fileCount
            owner.directories.remove(at: index)
        } else if let index = owner.files.firstIndex(where: { $0.name == itemName }) {
            removedBytes = owner.files[index].allocatedSize
            removedFiles = 1
            owner.files.remove(at: index)
        } else {
            return nil
        }
        var cursor: DirectoryNode? = owner
        while let node = cursor {
            node.allocatedSize -= removedBytes
            node.fileCount -= removedFiles
            if node === self { break }
            cursor = node.parent
        }
        return removedBytes
    }

    /// Visits every file in the subtree. Return false from `shouldDescend` to skip a directory.
    public func forEachFile(
        shouldDescend: (DirectoryNode) -> Bool = { _ in true },
        _ body: (DirectoryNode, FileEntry) -> Void
    ) {
        var stack: [DirectoryNode] = [self]
        while let node = stack.popLast() {
            for file in node.files { body(node, file) }
            for dir in node.directories where shouldDescend(dir) { stack.append(dir) }
        }
    }
}

/// Outcome of scanning one volume.
public struct ScanResult: @unchecked Sendable {
    public let target: ScanTarget
    public let root: DirectoryNode
    public let startedAt: Date
    public let duration: TimeInterval
    public let unreadableDirectories: Int
    public let wasCancelled: Bool

    public var totalAllocated: Int64 { root.allocatedSize }
    public var totalFiles: Int { root.fileCount }
}
