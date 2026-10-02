import Foundation

/// What to scan and where to stop.
public struct ScanTarget: Hashable, Sendable {
    /// Absolute path of the directory to scan (usually a volume's mount point).
    public let rootPath: String
    /// Only descend into directories living on one of these devices. `nil` = no restriction.
    /// Keeps the scanner from wandering into other mounted volumes.
    public let allowedDevices: Set<Int64>?
    /// Absolute paths that are skipped entirely (e.g. `/System/Volumes` to avoid counting firmlinked data twice).
    public let excludedPaths: Set<String>

    public init(rootPath: String, allowedDevices: Set<Int64>? = nil, excludedPaths: Set<String> = []) {
        self.rootPath = rootPath
        self.allowedDevices = allowedDevices
        self.excludedPaths = excludedPaths
    }
}

/// Live counters shared between the scanner threads and the UI. Read via `snapshot()`.
public final class ScanProgress: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        public var filesScanned: Int = 0
        public var directoriesScanned: Int = 0
        public var bytesScanned: Int64 = 0
        public var currentPath: String = ""
        public var unreadableDirectories: Int = 0
    }

    private let lock = NSLock()
    private var state = Snapshot()
    private var cancelled = false

    public init() {}

    public func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func record(files: Int, bytes: Int64, path: String) {
        lock.lock()
        state.filesScanned += files
        state.bytesScanned += bytes
        state.directoriesScanned += 1
        state.currentPath = path
        lock.unlock()
    }

    func recordUnreadable() {
        lock.lock(); state.unreadableDirectories += 1; lock.unlock()
    }
}

/// Bundles that Finder shows as a single item. Treated as one unit for duplicates and categories.
public enum PackageDetector {
    public static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "appex", "xpc",
        "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary",
        "xcarchive", "xcodeproj", "xcworkspace", "playground",
        "pages", "numbers", "key", "rtfd", "fcpbundle", "logicx", "imovielibrary",
        "lproj", "sparsebundle", "dSYM", "mlmodelc",
    ]

    public static func isPackage(name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let ext = name[name.index(after: dot)...]
        return packageExtensions.contains(String(ext)) || packageExtensions.contains(ext.lowercased())
    }
}
