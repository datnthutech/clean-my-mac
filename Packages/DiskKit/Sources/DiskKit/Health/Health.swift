import Foundation

public enum Severity: Int, Comparable, Codable, Sendable, CaseIterable {
    case ok = 0
    case info = 1
    case warning = 2
    case critical = 3

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Free-space thresholds. These are rules of thumb, editable in Settings.
///
/// The absolute GB limits only apply to the startup disk: macOS needs free space there for
/// swap, caches, APFS snapshots and system updates (~20–30 GB). Other drives use percentages only.
public struct HealthPolicy: Codable, Equatable, Sendable {
    public var criticalFreeBytes: Int64
    public var criticalFreeRatio: Double
    public var warningFreeBytes: Int64
    public var warningFreeRatio: Double

    public init(criticalFreeBytes: Int64 = 10 * ByteFormatter.gigabyte, criticalFreeRatio: Double = 0.05,
                warningFreeBytes: Int64 = 20 * ByteFormatter.gigabyte, warningFreeRatio: Double = 0.10) {
        self.criticalFreeBytes = criticalFreeBytes
        self.criticalFreeRatio = criticalFreeRatio
        self.warningFreeBytes = warningFreeBytes
        self.warningFreeRatio = warningFreeRatio
    }

    public static let `default` = HealthPolicy()

    public func severity(for volume: VolumeInfo) -> Severity {
        severity(freeBytes: volume.availableBytes, totalBytes: volume.totalBytes, isStartupDisk: volume.kind == .system)
    }

    public func severity(freeBytes: Int64, totalBytes: Int64, isStartupDisk: Bool) -> Severity {
        guard totalBytes > 0 else { return .ok }
        let ratio = Double(freeBytes) / Double(totalBytes)
        if ratio < criticalFreeRatio || (isStartupDisk && freeBytes < criticalFreeBytes) { return .critical }
        if ratio < warningFreeRatio || (isStartupDisk && freeBytes < warningFreeBytes) { return .warning }
        return .ok
    }
}

/// Where a finding's "Show" button navigates to.
public enum FindingTarget: Hashable, Sendable {
    case volume(String)
    case folder(volume: String, path: String)
    case duplicates
    case docker
    case fullDiskAccess
}

public enum FindingKind: Hashable, Sendable {
    case lowDiskSpace(volumeName: String, freeBytes: Int64, freeRatio: Double, isStartupDisk: Bool)
    case dockerDanglingImages(count: Int, bytes: Int64)
    case dockerBuildCache(bytes: Int64)
    case hotspot(HotspotKind, bytes: Int64)
    case duplicates(groups: Int, reclaimableBytes: Int64)
    case fullDiskAccessMissing
    case unreadableFolders(volumeName: String, count: Int)
}

public struct Finding: Hashable, Sendable, Identifiable {
    public let id: String
    public let severity: Severity
    public let kind: FindingKind
    public let target: FindingTarget
    /// Used to order findings of the same severity (largest first).
    public let bytes: Int64

    public init(id: String, severity: Severity, kind: FindingKind, target: FindingTarget, bytes: Int64 = 0) {
        self.id = id
        self.severity = severity
        self.kind = kind
        self.target = target
        self.bytes = bytes
    }
}

public struct SummaryInput: Sendable {
    public var volumes: [VolumeInfo]
    public var hotspotsByVolume: [String: [Hotspot]]
    public var unreadableByVolume: [String: Int]
    public var duplicateGroups: Int
    public var duplicateReclaimable: Int64
    public var docker: DockerReport?
    public var fullDiskAccessGranted: Bool
    public var policy: HealthPolicy

    public init(volumes: [VolumeInfo] = [], hotspotsByVolume: [String: [Hotspot]] = [:], unreadableByVolume: [String: Int] = [:],
                duplicateGroups: Int = 0, duplicateReclaimable: Int64 = 0, docker: DockerReport? = nil,
                fullDiskAccessGranted: Bool = true, policy: HealthPolicy = .default) {
        self.volumes = volumes
        self.hotspotsByVolume = hotspotsByVolume
        self.unreadableByVolume = unreadableByVolume
        self.duplicateGroups = duplicateGroups
        self.duplicateReclaimable = duplicateReclaimable
        self.docker = docker
        self.fullDiskAccessGranted = fullDiskAccessGranted
        self.policy = policy
    }
}

/// Turns raw analysis into a short list of findings sorted by severity — the "Summary" screen.
public enum SummaryBuilder {
    public static func findings(from input: SummaryInput) -> [Finding] {
        var result: [Finding] = []

        for volume in input.volumes {
            let severity = input.policy.severity(for: volume)
            if severity >= .warning {
                result.append(Finding(
                    id: "space-\(volume.id)", severity: severity,
                    kind: .lowDiskSpace(volumeName: volume.name, freeBytes: volume.availableBytes,
                                        freeRatio: volume.freeRatio, isStartupDisk: volume.kind == .system),
                    target: .volume(volume.id), bytes: volume.usedBytes))
            }
        }

        if !input.fullDiskAccessGranted {
            result.append(Finding(id: "fda", severity: .warning, kind: .fullDiskAccessMissing, target: .fullDiskAccess))
        }

        if let docker = input.docker {
            let dangling = docker.danglingBytes
            if !docker.danglingImages.isEmpty {
                result.append(Finding(
                    id: "docker-dangling", severity: dangling >= 5 * ByteFormatter.gigabyte ? .warning : .info,
                    kind: .dockerDanglingImages(count: docker.danglingImages.count, bytes: dangling),
                    target: .docker, bytes: dangling))
            }
            if let cache = docker.usage(.buildCache), cache.reclaimableBytes >= ByteFormatter.gigabyte {
                result.append(Finding(
                    id: "docker-build-cache", severity: cache.reclaimableBytes >= 10 * ByteFormatter.gigabyte ? .warning : .info,
                    kind: .dockerBuildCache(bytes: cache.reclaimableBytes), target: .docker, bytes: cache.reclaimableBytes))
            }
        }

        for (volumeID, hotspots) in input.hotspotsByVolume {
            for hotspot in hotspots {
                guard let severity = severity(forHotspot: hotspot) else { continue }
                result.append(Finding(
                    id: "hotspot-\(volumeID)-\(hotspot.kind.rawValue)", severity: severity,
                    kind: .hotspot(hotspot.kind, bytes: hotspot.bytes),
                    target: .folder(volume: volumeID, path: hotspot.path), bytes: hotspot.bytes))
            }
        }

        if input.duplicateGroups > 0 {
            result.append(Finding(
                id: "duplicates", severity: .info,
                kind: .duplicates(groups: input.duplicateGroups, reclaimableBytes: input.duplicateReclaimable),
                target: .duplicates, bytes: input.duplicateReclaimable))
        }

        for (volumeID, count) in input.unreadableByVolume where count > 0 && input.fullDiskAccessGranted {
            let name = input.volumes.first { $0.id == volumeID }?.name ?? volumeID
            result.append(Finding(id: "unreadable-\(volumeID)", severity: .info,
                                  kind: .unreadableFolders(volumeName: name, count: count), target: .volume(volumeID)))
        }

        return result.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.id < $1.id
        }
    }

    static func severity(forHotspot hotspot: Hotspot) -> Severity? {
        let gb = ByteFormatter.gigabyte
        switch hotspot.kind {
        case .downloads:
            // Downloads is personal data: only mention it when it's really big.
            return hotspot.bytes >= 20 * gb ? .info : nil
        default:
            if hotspot.bytes >= 10 * gb { return .warning }
            if hotspot.bytes >= gb { return .info }
            return nil
        }
    }

    /// Counts per severity, for the badges at the top of the summary.
    public static func counts(_ findings: [Finding]) -> [Severity: Int] {
        findings.reduce(into: [:]) { $0[$1.severity, default: 0] += 1 }
    }
}
