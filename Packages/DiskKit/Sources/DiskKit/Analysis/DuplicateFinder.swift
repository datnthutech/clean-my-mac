import Foundation

public struct DuplicateOptions: Codable, Equatable, Sendable {
    /// Files smaller than this are ignored (tiny files are rarely worth cleaning and create noise).
    public var minimumSize: Int64
    /// Skip folders full of same-named files by design (node_modules, .git, build output…).
    public var skipDeveloperFolders: Bool
    /// Skip `~/Library` and system folders — app data that should not be deduplicated by hand.
    public var skipLibraryAndSystem: Bool
    /// Skip names starting with "." (e.g. `.DS_Store`).
    public var skipHiddenFiles: Bool

    public init(minimumSize: Int64 = ByteFormatter.megabyte, skipDeveloperFolders: Bool = true,
                skipLibraryAndSystem: Bool = true, skipHiddenFiles: Bool = true) {
        self.minimumSize = minimumSize
        self.skipDeveloperFolders = skipDeveloperFolders
        self.skipLibraryAndSystem = skipLibraryAndSystem
        self.skipHiddenFiles = skipHiddenFiles
    }

    public static let developerFolderNames: Set<String> = [
        "node_modules", ".git", ".svn", ".hg", "DerivedData", "Pods", ".build", "build", ".gradle",
        "__pycache__", ".venv", "venv", "vendor", ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd",
    ]
}

public struct DuplicateFile: Hashable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let volumeName: String
    public let allocatedSize: Int64
    public let modificationDate: Date
}

/// Files sharing the same name (case-insensitive, Unicode-normalized).
public struct DuplicateGroup: Hashable, Sendable, Identifiable {
    public var id: String { key }
    /// Normalized comparison key.
    public let key: String
    /// Name as it appears on disk (from the newest copy).
    public let displayName: String
    /// Newest first: the first file is the suggested one to keep.
    public let files: [DuplicateFile]

    public var totalSize: Int64 { files.reduce(0) { $0 + $1.allocatedSize } }
    /// Space freed by keeping only the newest copy.
    public var reclaimableSize: Int64 { totalSize - (files.first?.allocatedSize ?? 0) }
    public var newest: DuplicateFile? { files.first }
}

public struct DuplicateSource: Sendable {
    public let volumeName: String
    public let root: DirectoryNode

    public init(volumeName: String, root: DirectoryNode) {
        self.volumeName = volumeName
        self.root = root
    }
}

public enum DuplicateFinder {
    /// Comparison key: Unicode NFC (macOS stores names decomposed, so "Báo cáo" typed vs on disk differ in bytes)
    /// and case-insensitive (APFS default).
    public static func normalizedKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    public static func find(in sources: [DuplicateSource], options: DuplicateOptions = DuplicateOptions(),
                            homePath: String = NSHomeDirectory()) -> [DuplicateGroup] {
        let blockedPrefixes: [String] = options.skipLibraryAndSystem
            ? ["\(homePath)/Library", "/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/opt", "/cores",
               "/Applications"]
            : []

        var buckets: [String: [DuplicateFile]] = [:]
        var displayNames: [String: String] = [:]

        for source in sources {
            source.root.forEachFile(shouldDescend: { dir in
                if dir.isPackage { return false }
                if options.skipDeveloperFolders && DuplicateOptions.developerFolderNames.contains(dir.name) { return false }
                if options.skipHiddenFiles && dir.name.hasPrefix(".") { return false }
                if blockedPrefixes.contains(where: { dir.path == $0 }) { return false }
                return true
            }) { dir, file in
                guard file.allocatedSize >= options.minimumSize else { return }
                if options.skipHiddenFiles && file.name.hasPrefix(".") { return }
                let key = normalizedKey(file.name)
                buckets[key, default: []].append(DuplicateFile(
                    path: dir.childPath(file.name),
                    volumeName: source.volumeName,
                    allocatedSize: file.allocatedSize,
                    modificationDate: file.modificationDate
                ))
                if displayNames[key] == nil { displayNames[key] = file.name.precomposedStringWithCanonicalMapping }
            }
        }

        return buckets.compactMap { key, files -> DuplicateGroup? in
            guard files.count >= 2 else { return nil }
            let sorted = files.sorted {
                $0.modificationDate != $1.modificationDate ? $0.modificationDate > $1.modificationDate : $0.path < $1.path
            }
            let name = (sorted.first.map { ($0.path as NSString).lastPathComponent } ?? displayNames[key] ?? key)
                .precomposedStringWithCanonicalMapping
            return DuplicateGroup(key: key, displayName: name, files: sorted)
        }
        .sorted {
            $0.reclaimableSize != $1.reclaimableSize ? $0.reclaimableSize > $1.reclaimableSize : $0.key < $1.key
        }
    }

    /// Drops deleted paths from the groups and removes groups that no longer have duplicates.
    public static func removing(paths: Set<String>, from groups: [DuplicateGroup]) -> [DuplicateGroup] {
        groups.compactMap { group in
            let remaining = group.files.filter { !paths.contains($0.path) }
            guard remaining.count >= 2 else { return nil }
            return DuplicateGroup(key: group.key, displayName: group.displayName, files: remaining)
        }
        .sorted { $0.reclaimableSize > $1.reclaimableSize }
    }
}
