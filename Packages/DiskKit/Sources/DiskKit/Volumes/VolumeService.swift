import Foundation

/// Lists mounted volumes and builds scan targets for them.
public struct VolumeService: Sendable {
    public init() {}

    public func mountedVolumes() -> [VolumeInfo] {
        var keys: [URLResourceKey] = [
            .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey,
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey, .volumeLocalizedFormatDescriptionKey,
        ]
        #if os(macOS)
        keys.append(.volumeAvailableCapacityForImportantUsageKey)
        let options: FileManager.VolumeEnumerationOptions = [.skipHiddenVolumes]
        #else
        let options: FileManager.VolumeEnumerationOptions = []
        #endif

        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: options) ?? []
        var volumes: [VolumeInfo] = []
        var seen = Set<String>()
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let path = url.path.isEmpty ? "/" : url.path
            let attrs = VolumeAttributes(
                path: path,
                name: values.volumeLocalizedName ?? values.volumeName,
                isLocal: values.volumeIsLocal,
                isInternal: values.volumeIsInternal,
                isRootFileSystem: values.volumeIsRootFileSystem,
                isBrowsable: values.volumeIsBrowsable,
                isRemovable: values.volumeIsRemovable,
                isEjectable: values.volumeIsEjectable,
                isReadOnly: values.volumeIsReadOnly
            )
            guard let kind = VolumeClassifier.kind(for: attrs), seen.insert(path).inserted else { continue }
            guard let total = values.volumeTotalCapacity, total > 0 else { continue }

            var available = Int64(values.volumeAvailableCapacity ?? 0)
            #if os(macOS)
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
                available = important
            }
            #endif
            volumes.append(VolumeInfo(
                name: attrs.name ?? (path as NSString).lastPathComponent,
                path: path,
                kind: kind,
                format: values.volumeLocalizedFormatDescription ?? "",
                totalBytes: Int64(total),
                availableBytes: available,
                isRemovable: values.volumeIsRemovable ?? false,
                isEjectable: values.volumeIsEjectable ?? false,
                isReadOnly: values.volumeIsReadOnly ?? false
            ))
        }
        return volumes.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .system || (lhs.kind == .internalDrive && rhs.kind == .external) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Builds the scan target for a volume.
    ///
    /// On the startup disk, `/` is the read-only system volume and user data lives on the
    /// "Data" volume, reached through firmlinks (`/Users`, `/Applications`, …). We allow both
    /// devices but skip `/System/Volumes` so the Data volume is not counted twice.
    public func scanTarget(for volume: VolumeInfo) -> ScanTarget {
        var devices = Set<Int64>()
        if let dev = deviceID(ofPath: volume.path) { devices.insert(dev) }
        var excluded = Set<String>()

        if volume.kind == .system && volume.path == "/" {
            if let dataDev = deviceID(ofPath: "/System/Volumes/Data") { devices.insert(dataDev) }
            excluded = ["/System/Volumes", "/Volumes", "/dev", "/private/var/vm", "/proc", "/sys"]
        }
        return ScanTarget(rootPath: volume.path, allowedDevices: devices.isEmpty ? nil : devices, excludedPaths: excluded)
    }
}
