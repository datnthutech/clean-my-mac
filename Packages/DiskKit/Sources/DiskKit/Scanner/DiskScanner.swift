import Foundation

/// Walks a directory tree in parallel and builds a `DirectoryNode` tree with accurate on-disk sizes.
///
/// Accuracy rules:
/// - sizes are allocated bytes (what deleting the file actually frees), not logical length;
/// - a hard-linked file is counted once;
/// - symlinks are never followed and other volumes are never entered (see `ScanTarget`).
public final class DiskScanner: @unchecked Sendable {
    private let reader: DirectoryReader
    private let threadCount: Int

    public init(reader: DirectoryReader = DirectoryReaders.best, threadCount: Int? = nil) {
        self.reader = reader
        // I/O bound: a few more threads than cores keeps SSD queues full without thrashing.
        let cores = ProcessInfo.processInfo.activeProcessorCount
        self.threadCount = max(1, threadCount ?? min(cores * 2, 16))
    }

    /// Scans synchronously. Call from a background thread; cancel through `progress.cancel()`.
    public func scan(_ target: ScanTarget, progress: ScanProgress = ScanProgress()) -> ScanResult {
        let started = Date()
        let rootPath = Self.normalize(target.rootPath)
        let rootName = rootPath == "/" ? "/" : (rootPath as NSString).lastPathComponent
        let root = DirectoryNode(name: rootName, path: rootPath, parent: nil)

        let engine = Engine(reader: reader, target: target, progress: progress)
        engine.run(root: root, threads: threadCount)
        root.finalize()

        return ScanResult(
            target: target,
            root: root,
            startedAt: started,
            duration: Date().timeIntervalSince(started),
            unreadableDirectories: progress.snapshot().unreadableDirectories,
            wasCancelled: progress.isCancelled
        )
    }

    static func normalize(_ path: String) -> String {
        if path == "/" { return path }
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}

private struct HardlinkKey: Hashable {
    let device: Int64
    let inode: UInt64
}

/// Shared work stack drained by a fixed pool of threads.
private final class Engine: @unchecked Sendable {
    private let reader: DirectoryReader
    private let target: ScanTarget
    private let progress: ScanProgress

    private let condition = NSCondition()
    private var pending: [DirectoryNode] = []
    private var active = 0

    private let linkLock = NSLock()
    private var seenHardlinks = Set<HardlinkKey>()

    init(reader: DirectoryReader, target: ScanTarget, progress: ScanProgress) {
        self.reader = reader
        self.target = target
        self.progress = progress
    }

    func run(root: DirectoryNode, threads: Int) {
        pending = [root]
        let group = DispatchGroup()
        for index in 0..<threads {
            group.enter()
            let thread = Thread { [self] in
                workerLoop()
                group.leave()
            }
            thread.name = "DiskScanner-\(index)"
            thread.qualityOfService = .userInitiated
            thread.stackSize = 1 << 20
            thread.start()
        }
        group.wait()
    }

    private func workerLoop() {
        while true {
            condition.lock()
            while pending.isEmpty && active > 0 && !progress.isCancelled {
                condition.wait()
            }
            if pending.isEmpty || progress.isCancelled {
                condition.broadcast()
                condition.unlock()
                return
            }
            let node = pending.removeLast()
            active += 1
            condition.unlock()

            let children = process(node)

            condition.lock()
            pending.append(contentsOf: children)
            active -= 1
            condition.broadcast()
            condition.unlock()
        }
    }

    private func process(_ node: DirectoryNode) -> [DirectoryNode] {
        let entries: [RawEntry]
        do {
            entries = try reader.read(path: node.path)
        } catch {
            node.isUnreadable = true
            progress.recordUnreadable()
            return []
        }

        var subdirectories: [DirectoryNode] = []
        var files: [FileEntry] = []
        files.reserveCapacity(entries.count)
        var bytes: Int64 = 0

        for entry in entries {
            switch entry.kind {
            case .directory:
                let path = node.childPath(entry.name)
                if target.excludedPaths.contains(path) { continue }
                if let allowed = target.allowedDevices, !allowed.contains(entry.device) { continue }
                let child = DirectoryNode(
                    name: entry.name,
                    path: path,
                    parent: node,
                    isPackage: PackageDetector.isPackage(name: entry.name)
                )
                child.modificationDate = Date(timeIntervalSince1970: entry.modificationTime)
                subdirectories.append(child)
            case .file:
                if entry.linkCount > 1 && !claimHardlink(HardlinkKey(device: entry.device, inode: entry.inode)) {
                    continue
                }
                files.append(FileEntry(
                    name: entry.name,
                    allocatedSize: entry.allocatedSize,
                    logicalSize: entry.logicalSize,
                    modificationDate: Date(timeIntervalSince1970: entry.modificationTime)
                ))
                bytes += entry.allocatedSize
            case .symlink, .other:
                continue
            }
        }
        node.files = files
        node.directories = subdirectories
        progress.record(files: files.count, bytes: bytes, path: node.path)
        return subdirectories
    }

    /// Returns true the first time a hard-linked inode is seen.
    private func claimHardlink(_ key: HardlinkKey) -> Bool {
        linkLock.lock(); defer { linkLock.unlock() }
        return seenHardlinks.insert(key).inserted
    }
}
