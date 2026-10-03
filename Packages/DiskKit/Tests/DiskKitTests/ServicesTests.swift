import XCTest
@testable import DiskKit

final class ByteFormatterTests: XCTestCase {
    func testDecimalUnitsAndLocaleSeparators() {
        let en = Locale(identifier: "en_US")
        let vi = Locale(identifier: "vi_VN")
        XCTAssertEqual(ByteFormatter.string(0, locale: en), "0 B")
        XCTAssertEqual(ByteFormatter.string(999, locale: en), "999 B")
        XCTAssertEqual(ByteFormatter.string(1_500, locale: en), "2 KB")
        XCTAssertEqual(ByteFormatter.string(8_200_000_000, locale: en), "8.2 GB")
        XCTAssertEqual(ByteFormatter.string(8_200_000_000, locale: vi), "8,2 GB")
        XCTAssertEqual(ByteFormatter.string(256_000_000_000, locale: en), "256 GB")
        XCTAssertEqual(ByteFormatter.string(1_000_000_000_000, locale: en), "1 TB")
    }
}

final class VolumeClassifierTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(VolumeClassifier.kind(for: VolumeAttributes(path: "/", isLocal: true, isInternal: true, isRootFileSystem: true)), .system)
        XCTAssertEqual(VolumeClassifier.kind(for: VolumeAttributes(path: "/Volumes/T7", isLocal: true, isInternal: false, isEjectable: true)), .external)
        XCTAssertEqual(VolumeClassifier.kind(for: VolumeAttributes(path: "/Volumes/USB", isLocal: true, isRemovable: true)), .external)
        XCTAssertEqual(VolumeClassifier.kind(for: VolumeAttributes(path: "/Volumes/Data2", isLocal: true, isInternal: true, isRemovable: false, isEjectable: false)), .internalDrive)
        XCTAssertNil(VolumeClassifier.kind(for: VolumeAttributes(path: "/Volumes/NAS", isLocal: false)))
        XCTAssertNil(VolumeClassifier.kind(for: VolumeAttributes(path: "/System/Volumes/Data", isLocal: true)))
        XCTAssertNil(VolumeClassifier.kind(for: VolumeAttributes(path: "/Volumes/Recovery", isLocal: true, isBrowsable: false)))
    }

    func testVolumeRatios() {
        let volume = VolumeInfo(name: "HD", path: "/", kind: .system, format: "APFS", totalBytes: 200, availableBytes: 50)
        XCTAssertEqual(volume.usedBytes, 150)
        XCTAssertEqual(volume.freeRatio, 0.25, accuracy: 0.0001)
    }
}

final class HealthTests: XCTestCase {
    let gb = ByteFormatter.gigabyte

    func testStartupDiskUsesAbsoluteAndRatioLimits() {
        let policy = HealthPolicy.default
        XCTAssertEqual(policy.severity(freeBytes: 8 * gb, totalBytes: 1000 * gb, isStartupDisk: true), .critical)
        XCTAssertEqual(policy.severity(freeBytes: 15 * gb, totalBytes: 100 * gb, isStartupDisk: true), .warning)
        XCTAssertEqual(policy.severity(freeBytes: 40 * gb, totalBytes: 500 * gb, isStartupDisk: true), .warning) // 8%
        XCTAssertEqual(policy.severity(freeBytes: 60 * gb, totalBytes: 500 * gb, isStartupDisk: true), .ok) // 12%, >20 GB
        XCTAssertEqual(policy.severity(freeBytes: 100 * gb, totalBytes: 500 * gb, isStartupDisk: true), .ok)
    }

    func testExternalDiskUsesRatioOnly() {
        let policy = HealthPolicy.default
        XCTAssertEqual(policy.severity(freeBytes: 9 * gb, totalBytes: 64 * gb, isStartupDisk: false), .ok)
        XCTAssertEqual(policy.severity(freeBytes: 5 * gb, totalBytes: 64 * gb, isStartupDisk: false), .warning)
        XCTAssertEqual(policy.severity(freeBytes: 2 * gb, totalBytes: 64 * gb, isStartupDisk: false), .critical)
    }

    func testSummaryOrdersBySeverityThenSize() {
        let volume = VolumeInfo(name: "Macintosh HD", path: "/", kind: .system, format: "APFS", totalBytes: 256 * gb, availableBytes: 8 * gb)
        let docker = DockerReport(
            binary: "/usr/local/bin/docker", serverVersion: "27",
            danglingImages: [DockerImage(id: "a", repository: "<none>", tag: "<none>", sizeBytes: 6 * gb, sizeText: "6GB", createdSince: "")],
            diskUsage: [DockerDiskUsage(kind: .buildCache, totalCount: 1, active: 0, sizeBytes: 3 * gb, reclaimableBytes: 3 * gb)],
            virtualDiskBytes: nil)
        let input = SummaryInput(
            volumes: [volume],
            hotspotsByVolume: ["/": [
                Hotspot(kind: .xcodeDerivedData, path: "/d", bytes: 15 * gb, itemCount: 1),
                Hotspot(kind: .trash, path: "/t", bytes: 2 * gb, itemCount: 1),
                Hotspot(kind: .userCaches, path: "/c", bytes: 100, itemCount: 1),
                Hotspot(kind: .downloads, path: "/dl", bytes: 5 * gb, itemCount: 1),
            ]],
            duplicateGroups: 37, duplicateReclaimable: gb / 2,
            docker: docker, fullDiskAccessGranted: false)

        let findings = SummaryBuilder.findings(from: input)
        XCTAssertEqual(findings.first?.severity, .critical)
        XCTAssertEqual(findings.first?.id, "space-/")
        XCTAssertEqual(findings.map(\.severity), findings.map(\.severity).sorted(by: >))
        XCTAssertTrue(findings.contains { $0.id == "docker-dangling" && $0.severity == .warning })
        XCTAssertTrue(findings.contains { $0.id == "docker-build-cache" && $0.severity == .info })
        XCTAssertTrue(findings.contains { $0.id == "fda" })
        XCTAssertTrue(findings.contains { $0.id == "duplicates" })
        XCTAssertFalse(findings.contains { $0.id.hasSuffix("userCaches") })
        XCTAssertFalse(findings.contains { $0.id.hasSuffix("downloads") })
        let counts = SummaryBuilder.counts(findings)
        XCTAssertEqual(counts[.critical], 1)
    }
}

final class TrashGuardTests: XCTestCase {
    let guardrail = TrashGuard(homePath: "/Users/dat", appBundlePath: "/Applications/CleanMyMac.app", volumeRoots: ["/Volumes/T7"])

    func testProtectedLocations() {
        XCTAssertEqual(guardrail.decision(for: "/System/Library/Kernels"), .protected(reason: .systemLocation))
        XCTAssertEqual(guardrail.decision(for: "/usr/bin/ls"), .protected(reason: .systemLocation))
        XCTAssertEqual(guardrail.decision(for: "/"), .protected(reason: .volumeRoot))
        XCTAssertEqual(guardrail.decision(for: "/Volumes/T7"), .protected(reason: .volumeRoot))
        XCTAssertEqual(guardrail.decision(for: "/Volumes/Other/"), .protected(reason: .volumeRoot))
        XCTAssertEqual(guardrail.decision(for: "/Users/dat"), .protected(reason: .essentialFolder))
        XCTAssertEqual(guardrail.decision(for: "/Users/dat/Library"), .protected(reason: .essentialFolder))
        XCTAssertEqual(guardrail.decision(for: "/Users/dat/Documents/"), .protected(reason: .essentialFolder))
        XCTAssertEqual(guardrail.decision(for: "/Applications/CleanMyMac.app/Contents"), .protected(reason: .applicationItself))
        XCTAssertEqual(guardrail.decision(for: "relative/path"), .protected(reason: .notAbsolute))
        XCTAssertEqual(guardrail.decision(for: "/Users/dat/Documents/../Library"), .protected(reason: .essentialFolder))
    }

    func testAllowedLocations() {
        XCTAssertTrue(guardrail.isAllowed("/Users/dat/Downloads/big.dmg"))
        XCTAssertTrue(guardrail.isAllowed("/Users/dat/Library/Caches/com.foo"))
        XCTAssertTrue(guardrail.isAllowed("/Users/dat/Library/Developer/Xcode/DerivedData"))
        XCTAssertTrue(guardrail.isAllowed("/Applications/Unused.app"))
        XCTAssertTrue(guardrail.isAllowed("/Volumes/T7/Archive/old.mov"))
    }

    func testDeletionLogRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString)/log.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = DeletionLog(fileURL: url)
        XCTAssertTrue(log.load().isEmpty)
        try log.append([DeletionRecord(kind: .file, path: "/a", bytes: 1), DeletionRecord(kind: .dockerImage, path: "sha", bytes: 2)])
        try log.append([DeletionRecord(kind: .folder, path: "/b", bytes: 3)])
        let records = log.load()
        XCTAssertEqual(records.map(\.path), ["/b", "sha", "/a"])
        try log.clear()
        XCTAssertTrue(log.load().isEmpty)
    }
}

/// Fake `docker` CLI: maps the joined arguments to canned results and records every call.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    var responses: [String: CommandResult] = [:]
    private(set) var calls: [[String]] = []

    func run(_ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> CommandResult {
        calls.append(arguments)
        return responses[arguments.joined(separator: " ")] ?? CommandResult(exitCode: 1, stdout: "", stderr: "unknown")
    }
}

final class DockerServiceTests: XCTestCase {
    func testNotInstalledRunsNothing() {
        let runner = FakeRunner()
        let service = DockerService(runner: runner, homePath: "/Users/t", fileExists: { _ in false })
        XCTAssertEqual(service.status(), .notInstalled)
        let (status, report) = service.report()
        XCTAssertEqual(status, .notInstalled)
        XCTAssertNil(report)
        XCTAssertTrue(runner.calls.isEmpty, "No command may run when Docker is not installed")
    }

    func testInstalledButNotRunning() {
        let runner = FakeRunner()
        runner.responses["info --format {{.ServerVersion}}"] = CommandResult(exitCode: 1, stdout: "", stderr: "Cannot connect to the Docker daemon")
        let service = DockerService(runner: runner, homePath: "/Users/t", fileExists: { $0 == "/opt/homebrew/bin/docker" })
        XCTAssertEqual(service.status(), .notRunning(binary: "/opt/homebrew/bin/docker"))
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testRunningReportParsesImagesAndUsage() {
        let runner = FakeRunner()
        runner.responses["info --format {{.ServerVersion}}"] = CommandResult(exitCode: 0, stdout: "27.3.1\n", stderr: "")
        runner.responses["images --filter dangling=true --no-trunc --format {{json .}}"] = CommandResult(exitCode: 0, stdout: """
        {"Containers":"N/A","CreatedSince":"3 weeks ago","ID":"sha256:a3f9c21e7b04aaaa","Repository":"\\u003cnone\\u003e","Size":"1.2GB","Tag":"\\u003cnone\\u003e"}
        {"CreatedSince":"1 month ago","ID":"sha256:7c0d88a1f5e2bbbb","Repository":"<none>","Size":"980MB","Tag":"<none>"}
        not json
        """, stderr: "")
        runner.responses["system df --format {{json .}}"] = CommandResult(exitCode: 0, stdout: """
        {"Active":"2","Reclaimable":"6.4GB (52%)","Size":"12.3GB","TotalCount":"14","Type":"Images"}
        {"Active":"0","Reclaimable":"4.8GB","Size":"4.8GB","TotalCount":"31","Type":"Build Cache"}
        """, stderr: "")
        let service = DockerService(runner: runner, homePath: "/nonexistent", fileExists: { $0 == "/usr/local/bin/docker" })

        let (status, report) = service.report()
        XCTAssertEqual(status, .running(binary: "/usr/local/bin/docker", serverVersion: "27.3.1"))
        let r = try! XCTUnwrap(report)
        XCTAssertEqual(r.danglingImages.map(\.id), ["a3f9c21e7b04aaaa", "7c0d88a1f5e2bbbb"])
        XCTAssertTrue(r.danglingImages.allSatisfy(\.isDangling))
        XCTAssertEqual(r.danglingBytes, 2_180_000_000)
        XCTAssertEqual(r.usage(.images)?.reclaimableBytes, 6_400_000_000)
        XCTAssertEqual(r.usage(.buildCache)?.totalCount, 31)
        XCTAssertNil(r.virtualDiskBytes)
    }

    func testRemoveNeverForces() {
        let runner = FakeRunner()
        runner.responses["image rm abc"] = CommandResult(exitCode: 0, stdout: "Deleted: sha256:abc", stderr: "")
        runner.responses["image rm used"] = CommandResult(exitCode: 1, stdout: "", stderr: "conflict: image is being used")
        let service = DockerService(runner: runner, homePath: "/u", fileExists: { _ in true })
        let results = service.removeImages(ids: ["abc", "used"], binary: "/usr/local/bin/docker")
        XCTAssertEqual(results.map(\.succeeded), [true, false])
        XCTAssertFalse(runner.calls.flatMap { $0 }.contains("-f"))
        XCTAssertFalse(runner.calls.flatMap { $0 }.contains("--force"))
    }

    func testPruneParsesReclaimedSpace() throws {
        let runner = FakeRunner()
        runner.responses["image prune -f"] = CommandResult(exitCode: 0, stdout: "Deleted Images:\ndeleted: sha256:x\n\nTotal reclaimed space: 1.25GB\n", stderr: "")
        let service = DockerService(runner: runner, homePath: "/u", fileExists: { _ in true })
        XCTAssertEqual(try service.pruneDanglingImages(binary: "/d"), 1_250_000_000)
    }

    func testSizeParser() {
        XCTAssertEqual(DockerSizeParser.bytes(from: "1.2GB"), 1_200_000_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "980MB"), 980_000_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "12.3kB"), 12_300)
        XCTAssertEqual(DockerSizeParser.bytes(from: "512B"), 512)
        XCTAssertEqual(DockerSizeParser.bytes(from: "1GiB"), 1_073_741_824)
        XCTAssertEqual(DockerSizeParser.bytes(from: ""), 0)
        XCTAssertEqual(DockerSizeParser.bytes(from: "N/A"), 0)
    }

    func testFullDiskAccessProbeLogic() {
        #if os(macOS)
        XCTAssertTrue(FullDiskAccess.isGranted(home: "/u", probe: { _ in .missing }))
        XCTAssertFalse(FullDiskAccess.isGranted(home: "/u", probe: { _ in .denied }))
        XCTAssertTrue(FullDiskAccess.isGranted(home: "/u", probe: { $0.hasSuffix("CloudTabs.db") ? .readable : .denied }))
        #else
        XCTAssertTrue(FullDiskAccess.isGranted(home: "/u"))
        #endif
    }
}
