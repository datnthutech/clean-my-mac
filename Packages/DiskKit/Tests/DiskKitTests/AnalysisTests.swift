import XCTest
@testable import DiskKit

/// Builds small in-memory trees so analysis can be tested without touching the disk.
enum TreeBuilder {
    static func dir(_ path: String, parent: DirectoryNode? = nil, files: [(String, Int64)] = [], date: Date = Date()) -> DirectoryNode {
        let name = path == "/" ? "/" : (path as NSString).lastPathComponent
        let node = DirectoryNode(name: name, path: path, parent: parent, isPackage: PackageDetector.isPackage(name: name))
        node.files = files.map { FileEntry(name: $0.0, allocatedSize: $0.1, logicalSize: $0.1, modificationDate: date) }
        parent?.directories.append(node)
        return node
    }
}

final class CategorizerTests: XCTestCase {
    func testFolderRulesBeatExtensions() {
        let home = "/Users/test"
        let root = TreeBuilder.dir("/")
        let users = TreeBuilder.dir("/Users", parent: root)
        let homeNode = TreeBuilder.dir(home, parent: users)
        let library = TreeBuilder.dir("\(home)/Library", parent: homeNode)
        _ = TreeBuilder.dir("\(home)/Library/Caches", parent: library, files: [("blob.png", 500)])
        let docs = TreeBuilder.dir("\(home)/Documents", parent: homeNode, files: [("report.pdf", 100), ("song.mp3", 50), ("x.zip", 70)])
        let project = TreeBuilder.dir("\(home)/Documents/app", parent: docs)
        _ = TreeBuilder.dir("\(home)/Documents/app/node_modules", parent: project, files: [("index.js", 300)])
        let apps = TreeBuilder.dir("/Applications", parent: root)
        _ = TreeBuilder.dir("/Applications/Foo.app", parent: apps, files: [("Foo", 1000)])
        root.finalize()

        let report = Categorizer(homePath: home).report(for: root)
        XCTAssertEqual(report.totals[.caches], 500)
        XCTAssertEqual(report.totals[.documents], 100)
        XCTAssertEqual(report.totals[.music], 50)
        XCTAssertEqual(report.totals[.archives], 70)
        XCTAssertEqual(report.totals[.developer], 300)
        XCTAssertEqual(report.totals[.applications], 1000)
        XCTAssertEqual(report.categorizedBytes, root.allocatedSize)
        XCTAssertEqual(report.sortedTotals.first?.category, .applications)

        XCTAssertEqual(report.hotspots.first(where: { $0.kind == .nodeModules })?.bytes, 300)
        XCTAssertEqual(report.hotspots.first(where: { $0.kind == .userCaches })?.bytes, 500)
    }

    func testExtensionMapping() {
        XCTAssertEqual(Categorizer.category(forFileName: "IMG_0001.HEIC"), .media)
        XCTAssertEqual(Categorizer.category(forFileName: "setup.dmg"), .archives)
        XCTAssertEqual(Categorizer.category(forFileName: "Báo cáo.docx"), .documents)
        XCTAssertEqual(Categorizer.category(forFileName: "noext"), .other)
    }

    func testLargeFiles() {
        let root = TreeBuilder.dir("/data", files: [("a.mov", 500), ("b.txt", 5)])
        _ = TreeBuilder.dir("/data/sub", parent: root, files: [("c.zip", 800)])
        root.finalize()
        let large = LargeFileFinder.largestFiles(in: root, minimumSize: 100, limit: 10)
        XCTAssertEqual(large.map(\.name), ["c.zip", "a.mov"])
        XCTAssertEqual(large.first?.path, "/data/sub/c.zip")
        XCTAssertEqual(LargeFileFinder.largestFiles(in: root, minimumSize: 100, limit: 1).count, 1)
    }
}

final class DuplicateFinderTests: XCTestCase {
    let home = "/Users/test"

    func testGroupsByNormalizedNameAcrossVolumes() {
        let old = Date(timeIntervalSince1970: 1000)
        let new = Date(timeIntervalSince1970: 2000)
        // "Báo cáo.pdf" decomposed (NFD, as macOS stores it) vs precomposed (NFC), different case.
        let nfd = "Ba\u{301}o ca\u{301}o.pdf"
        let nfc = "BÁO CÁO.pdf"
        let a = TreeBuilder.dir("\(home)/Documents", files: [(nfd, 3_000_000)], date: new)
        let b = TreeBuilder.dir("/Volumes/T7/Backup", files: [(nfc, 2_000_000), ("unique.mov", 9_000_000)], date: old)
        a.finalize(); b.finalize()

        let groups = DuplicateFinder.find(in: [
            DuplicateSource(volumeName: "Macintosh HD", root: a),
            DuplicateSource(volumeName: "T7", root: b),
        ], homePath: home)

        XCTAssertEqual(groups.count, 1)
        let group = groups[0]
        XCTAssertEqual(group.files.count, 2)
        XCTAssertEqual(group.newest?.volumeName, "Macintosh HD")
        XCTAssertEqual(group.totalSize, 5_000_000)
        XCTAssertEqual(group.reclaimableSize, 2_000_000)
    }

    func testSkipsSmallHiddenDeveloperAndLibraryFiles() {
        let root = TreeBuilder.dir(home)
        _ = TreeBuilder.dir("\(home)/a", parent: root, files: [("tiny.txt", 10), (".DS_Store", 5_000_000), ("same.bin", 2_000_000)])
        _ = TreeBuilder.dir("\(home)/b", parent: root, files: [("tiny.txt", 10), (".DS_Store", 5_000_000)])
        _ = TreeBuilder.dir("\(home)/node_modules", parent: root, files: [("same.bin", 2_000_000)])
        _ = TreeBuilder.dir("\(home)/Library", parent: root, files: [("same.bin", 2_000_000)])
        _ = TreeBuilder.dir("\(home)/Thing.app", parent: root, files: [("same.bin", 2_000_000)])
        root.finalize()

        XCTAssertTrue(DuplicateFinder.find(in: [DuplicateSource(volumeName: "HD", root: root)], homePath: home).isEmpty)

        let loose = DuplicateOptions(minimumSize: 0, skipDeveloperFolders: false, skipLibraryAndSystem: false, skipHiddenFiles: false)
        let groups = DuplicateFinder.find(in: [DuplicateSource(volumeName: "HD", root: root)], options: loose, homePath: home)
        XCTAssertEqual(Set(groups.map(\.key)), ["tiny.txt", ".ds_store", "same.bin"])
        XCTAssertEqual(groups.first { $0.key == "same.bin" }?.files.count, 3) // the .app package is still skipped
    }

    func testRemovingPathsDropsResolvedGroups() {
        let root = TreeBuilder.dir("/x", files: [("a.bin", 2_000_000)])
        _ = TreeBuilder.dir("/x/y", parent: root, files: [("a.bin", 2_000_000)])
        root.finalize()
        let groups = DuplicateFinder.find(in: [DuplicateSource(volumeName: "HD", root: root)], homePath: home)
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(DuplicateFinder.removing(paths: ["/x/y/a.bin"], from: groups).isEmpty)
    }
}

final class TreemapTests: XCTestCase {
    func testTilesFillBoundsWithoutOverlap() {
        let items: [(id: String, value: Double)] = [("a", 6), ("b", 6), ("c", 4), ("d", 3), ("e", 2), ("f", 2), ("g", 1), ("zero", 0)]
        let bounds = LayoutRect(x: 0, y: 0, width: 600, height: 400)
        let tiles = TreemapLayout.squarify(items, in: bounds)

        XCTAssertEqual(tiles.count, 7)
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.rect.area }, bounds.area, accuracy: 0.001)
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.rect.x, -0.001)
            XCTAssertGreaterThanOrEqual(tile.rect.y, -0.001)
            XCTAssertLessThanOrEqual(tile.rect.x + tile.rect.width, 600.001)
            XCTAssertLessThanOrEqual(tile.rect.y + tile.rect.height, 400.001)
        }
        for i in 0..<tiles.count {
            for j in (i + 1)..<tiles.count {
                let a = tiles[i].rect, b = tiles[j].rect
                let overlapW = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
                let overlapH = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                XCTAssertFalse(overlapW > 0.001 && overlapH > 0.001, "\(tiles[i].id) overlaps \(tiles[j].id)")
            }
        }
        // Area proportional to value: "a" (6/24) gets a quarter.
        XCTAssertEqual(tiles.first { $0.id == "a" }!.rect.area, bounds.area * 6 / 24, accuracy: 0.001)
    }

    func testEmptyInput() {
        XCTAssertTrue(TreemapLayout.squarify([(id: "a", value: 0.0)], in: LayoutRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        XCTAssertTrue(TreemapLayout.squarify([(id: "a", value: 1.0)], in: LayoutRect(x: 0, y: 0, width: 0, height: 10)).isEmpty)
    }
}
