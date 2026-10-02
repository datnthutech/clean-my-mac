import Foundation

public enum VolumeKind: String, Codable, Sendable {
    /// The startup disk ("Macintosh HD").
    case system
    /// Another internal volume/partition.
    case internalDrive
    /// External SSD/HDD, USB stick, SD card…
    case external
}

public struct VolumeInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let kind: VolumeKind
    public let format: String
    public let totalBytes: Int64
    /// Free space as Finder reports it (includes purgeable space on APFS).
    public let availableBytes: Int64
    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isReadOnly: Bool

    public init(
        name: String, path: String, kind: VolumeKind, format: String,
        totalBytes: Int64, availableBytes: Int64,
        isRemovable: Bool = false, isEjectable: Bool = false, isReadOnly: Bool = false
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.format = format
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isReadOnly = isReadOnly
    }

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    public var freeRatio: Double { totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 0 }
    public var usedRatio: Double { 1 - freeRatio }
    public var isExternal: Bool { kind == .external }
}

/// Raw attributes of a mounted volume, separated from `URLResourceValues` so the rules are unit-testable.
public struct VolumeAttributes: Sendable {
    public var path: String
    public var name: String?
    public var isLocal: Bool?
    public var isInternal: Bool?
    public var isRootFileSystem: Bool?
    public var isBrowsable: Bool?
    public var isRemovable: Bool?
    public var isEjectable: Bool?
    public var isReadOnly: Bool?

    public init(
        path: String, name: String? = nil, isLocal: Bool? = nil, isInternal: Bool? = nil,
        isRootFileSystem: Bool? = nil, isBrowsable: Bool? = nil, isRemovable: Bool? = nil,
        isEjectable: Bool? = nil, isReadOnly: Bool? = nil
    ) {
        self.path = path
        self.name = name
        self.isLocal = isLocal
        self.isInternal = isInternal
        self.isRootFileSystem = isRootFileSystem
        self.isBrowsable = isBrowsable
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isReadOnly = isReadOnly
    }
}

public enum VolumeClassifier {
    /// Returns nil for volumes the app should not show: network shares, hidden system volumes, pseudo file systems.
    public static func kind(for attrs: VolumeAttributes) -> VolumeKind? {
        if attrs.isLocal == false { return nil }
        if attrs.isBrowsable == false { return nil }
        let hiddenPrefixes = ["/System/Volumes", "/private/var/vm", "/dev", "/proc", "/sys", "/run", "/snap"]
        if attrs.path != "/" && hiddenPrefixes.contains(where: { attrs.path == $0 || attrs.path.hasPrefix($0 + "/") }) {
            return nil
        }
        if attrs.path == "/" || attrs.isRootFileSystem == true { return .system }
        if attrs.isRemovable == true || attrs.isEjectable == true || attrs.isInternal == false {
            return .external
        }
        return .internalDrive
    }
}
