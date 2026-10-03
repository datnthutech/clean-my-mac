import XCTest
@testable import DiskKit

final class ScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("diskkit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, bytes: Int) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func testScanBuildsTreeWithSortedSizes() throws {
        try write("big/movie.mov", bytes: 300_000)
        try write("big/nested/clip.mp4", bytes: 200_000)
        try write("small/note.txt", bytes: 10_000)
        try write("top.pdf", bytes: 50_000)

        let result = DiskScanner(threadCount: 4).scan(ScanTarget(rootPath: root.path))

        XCTAssertEqual(result.totalFiles, 4)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(result.root.directories.map(\.name), ["big", "small"])
        let big = try XCTUnwrap(result.root.directories.first)
        XCTAssertGreaterThanOrEqual(big.allocatedSize, 500_000)
        XCTAssertEqual(big.fileCount, 2)
        XCTAssertEqual(result.root.allocatedSize,
                       result.root.directories.reduce(0) { $0 + $1.allocatedSize } + result.root.files.reduce(0) { $0 + $1.allocatedSize })
    }

    func testHardLinksAreCountedOnce() throws {
        try write("a/original.bin", bytes: 400_000)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("b"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: root.appendingPathComponent("a/original.bin"),
                                         to: root.appendingPathComponent("b/link.bin"))

        let result = DiskScanner().scan(ScanTarget(rootPath: root.path))
        XCTAssertEqual(result.totalFiles, 1)
        XCTAssertLessThan(result.totalAllocated, 800_000)
    }

    func testSymlinksAreNotFollowed() throws {
        try write("real/data.bin", bytes: 100_000)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"),
                                                   withDestinationURL: root.appendingPathComponent("real"))
        let result = DiskScanner().scan(ScanTarget(rootPath: root.path))
        XCTAssertEqual(result.totalFiles, 1)
        XCTAssertEqual(result.root.directories.map(\.name), ["real"])
    }

    func testExcludedPathsAreSkipped() throws {
        try write("keep/a.bin", bytes: 1000)
        try write("skip/b.bin", bytes: 1000)
        let target = ScanTarget(rootPath: root.path, excludedPaths: [root.appendingPathComponent("skip").path])
        let result = DiskScanner().scan(target)
        XCTAssertEqual(result.root.directories.map(\.name), ["keep"])
    }

    func testOtherDevicesAreSkipped() throws {
        try write("x/a.bin", bytes: 1000)
        let target = ScanTarget(rootPath: root.path, allowedDevices: [-12345])
        let result = DiskScanner().scan(target)
        XCTAssertTrue(result.root.directories.isEmpty)
        XCTAssertEqual(result.root.files.count, 0)
    }

    func testCancelledScanStopsEarly() throws {
        for i in 0..<50 { try write("d\(i)/f.bin", bytes: 100) }
        let progress = ScanProgress()
        progress.cancel()
        let result = DiskScanner().scan(ScanTarget(rootPath: root.path), progress: progress)
        XCTAssertTrue(result.wasCancelled)
        XCTAssertLessThan(result.totalFiles, 50)
    }

    func testProgressCountsFiles() throws {
        for i in 0..<10 { try write("f\(i).bin", bytes: 100) }
        let progress = ScanProgress()
        _ = DiskScanner().scan(ScanTarget(rootPath: root.path), progress: progress)
        XCTAssertEqual(progress.snapshot().filesScanned, 10)
    }

    func testUnreadableRootIsReported() {
        let result = DiskScanner().scan(ScanTarget(rootPath: root.path + "/does-not-exist"))
        XCTAssertTrue(result.root.isUnreadable)
        XCTAssertEqual(result.unreadableDirectories, 1)
    }

    func testRemoveItemUpdatesAncestors() throws {
        try write("a/b/c.bin", bytes: 100_000)
        try write("a/d.bin", bytes: 100_000)
        let result = DiskScanner().scan(ScanTarget(rootPath: root.path))
        let before = result.root.allocatedSize
        let path = root.appendingPathComponent("a/b").path
        let removed = try XCTUnwrap(result.root.removeItem(atPath: path))
        XCTAssertGreaterThan(removed, 0)
        XCTAssertEqual(result.root.allocatedSize, before - removed)
        XCTAssertEqual(result.root.fileCount, 1)
        XCTAssertNil(result.root.node(atPath: path))
        XCTAssertNil(result.root.removeItem(atPath: root.appendingPathComponent("missing").path))
    }

    func testPackageDetection() {
        XCTAssertTrue(PackageDetector.isPackage(name: "Xcode.app"))
        XCTAssertTrue(PackageDetector.isPackage(name: "Photos Library.photoslibrary"))
        XCTAssertFalse(PackageDetector.isPackage(name: "notes.txt"))
        XCTAssertFalse(PackageDetector.isPackage(name: ".app"))
    }

    #if os(macOS)
    /// The fast getattrlistbulk reader must agree with the portable lstat reader.
    func testBulkReaderMatchesPOSIXReader() throws {
        try write("one.bin", bytes: 123_456)
        try write("dir/two.bin", bytes: 1)
        try write("Tiếng Việt.txt", bytes: 42)
        let bulk = try BulkDirectoryReader().read(path: root.path).sorted { $0.name < $1.name }
        let posix = try POSIXDirectoryReader().read(path: root.path).sorted { $0.name < $1.name }
        XCTAssertEqual(bulk.map(\.name), posix.map(\.name))
        XCTAssertEqual(bulk.map(\.kind), posix.map(\.kind))
        for (b, p) in zip(bulk, posix) where b.kind == .file {
            XCTAssertEqual(b.allocatedSize, p.allocatedSize, b.name)
            XCTAssertEqual(b.logicalSize, p.logicalSize, b.name)
            XCTAssertEqual(b.inode, p.inode, b.name)
            XCTAssertEqual(b.device, p.device, b.name)
            XCTAssertEqual(b.modificationTime, p.modificationTime, accuracy: 1, b.name)
        }
    }
    #endif
}
