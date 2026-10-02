import Foundation

/// "What is this space used for?" — the buckets shown in the Categories view.
public enum StorageCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case applications
    case documents
    case media
    case music
    case archives
    case developer
    case caches
    case iosBackups
    case mail
    case trash
    case docker
    case system
    case other

    public var id: String { rawValue }
}

/// Well-known folders that are often large and safe(ish) to clean.
public enum HotspotKind: String, CaseIterable, Codable, Sendable {
    case xcodeDerivedData
    case xcodeArchives
    case simulators
    case userCaches
    case trash
    case iosBackups
    case nodeModules
    case downloads
    case homebrewCache
}

public struct Hotspot: Hashable, Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public let kind: HotspotKind
    /// Representative path (for aggregates such as node_modules: the largest one).
    public let path: String
    public let bytes: Int64
    public let itemCount: Int
}

public struct CategoryReport: Sendable {
    public var totals: [StorageCategory: Int64]
    public var hotspots: [Hotspot]

    public var sortedTotals: [(category: StorageCategory, bytes: Int64)] {
        totals.filter { $0.value > 0 }
            .map { (category: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    public var categorizedBytes: Int64 { totals.values.reduce(0, +) }
}

/// Assigns every file in a scan to a `StorageCategory` using folder rules first, then the file extension.
public struct Categorizer: Sendable {
    public let homePath: String
    private let pathRules: [String: StorageCategory]
    private let hotspotPaths: [String: HotspotKind]

    public init(homePath: String = NSHomeDirectory()) {
        self.homePath = homePath
        let home = homePath
        var rules: [String: StorageCategory] = [
            "/Applications": .applications,
            "/System/Applications": .applications,
            "\(home)/Applications": .applications,

            "\(home)/Library/Developer": .developer,
            "\(home)/Library/Caches/Homebrew": .developer,
            "\(home)/Library/Caches/CocoaPods": .developer,
            "\(home)/Library/Caches/org.swift.swiftpm": .developer,
            "\(home)/Library/Android": .developer,
            "\(home)/.npm": .developer,
            "\(home)/.yarn": .developer,
            "\(home)/.pnpm-store": .developer,
            "\(home)/.gradle": .developer,
            "\(home)/.m2": .developer,
            "\(home)/.cocoapods": .developer,
            "\(home)/.cargo": .developer,
            "\(home)/.rustup": .developer,
            "\(home)/go": .developer,
            "/opt/homebrew": .developer,
            "/usr/local/Cellar": .developer,
            "/usr/local/Homebrew": .developer,
            "/Library/Developer": .developer,

            "\(home)/Library/Containers/com.docker.docker": .docker,
            "\(home)/Library/Group Containers/group.com.docker": .docker,
            "\(home)/.docker": .docker,
            "\(home)/.orbstack": .docker,
            "\(home)/.colima": .docker,
            "\(home)/Library/Containers/dev.orbstack.OrbStack": .docker,

            "\(home)/Library/Caches": .caches,
            "/Library/Caches": .caches,
            "/private/var/folders": .caches,

            "\(home)/Library/Application Support/MobileSync/Backup": .iosBackups,
            "\(home)/Library/Mail": .mail,
            "\(home)/Library/Messages": .mail,
            "\(home)/Library/Containers/com.apple.mail": .mail,
            "\(home)/.Trash": .trash,
        ]
        for systemPath in ["/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/cores", "/etc", "/var"] {
            rules[systemPath] = .system
        }
        self.pathRules = rules
        self.hotspotPaths = [
            "\(home)/Library/Developer/Xcode/DerivedData": .xcodeDerivedData,
            "\(home)/Library/Developer/Xcode/Archives": .xcodeArchives,
            "\(home)/Library/Developer/CoreSimulator": .simulators,
            "\(home)/Library/Caches": .userCaches,
            "\(home)/.Trash": .trash,
            "\(home)/Library/Application Support/MobileSync/Backup": .iosBackups,
            "\(home)/Downloads": .downloads,
            "\(home)/Library/Caches/Homebrew": .homebrewCache,
        ]
    }

    /// Category for a folder by its own name, used when no path rule matches.
    static func category(forDirectoryName name: String) -> StorageCategory? {
        switch name {
        case "node_modules", ".git", "DerivedData", "Pods", ".gradle", "__pycache__", ".venv", "venv", ".build":
            return .developer
        case ".Trashes", ".Trash":
            return .trash
        default:
            break
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "app": return .applications
        case "photoslibrary", "imovielibrary", "fcpbundle", "tvlibrary": return .media
        case "musiclibrary", "logicx", "band": return .music
        case "pages", "numbers", "key", "rtfd": return .documents
        case "xcarchive": return .developer
        default: return nil
        }
    }

    static let extensionMap: [String: StorageCategory] = {
        var map: [String: StorageCategory] = [:]
        let groups: [(StorageCategory, [String])] = [
            (.documents, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md", "csv", "odt",
                          "ods", "odp", "epub", "pages", "numbers", "key", "json", "xml", "html", "htm"]),
            (.media, ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "raw", "cr2", "cr3", "nef",
                      "arw", "dng", "psd", "svg", "webp", "mov", "mp4", "m4v", "avi", "mkv", "wmv", "flv", "webm",
                      "mts", "braw", "prores"]),
            (.music, ["mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "ogg", "alac", "wma", "mid", "midi"]),
            (.archives, ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "pkg", "iso", "img", "xip",
                         "ipa", "apk"]),
            (.developer, ["o", "a", "dylib", "swiftmodule", "pch", "class", "jar", "pyc"]),
        ]
        for (category, extensions) in groups {
            for ext in extensions { map[ext] = category }
        }
        return map
    }()

    public static func category(forFileName name: String) -> StorageCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        return extensionMap[ext] ?? .other
    }

    public func report(for root: DirectoryNode) -> CategoryReport {
        var totals: [StorageCategory: Int64] = [:]
        var hotspotTotals: [HotspotKind: (path: String, bytes: Int64, count: Int)] = [:]

        var stack: [(DirectoryNode, StorageCategory?)] = [(root, pathRules[root.path])]
        while let (node, inherited) = stack.popLast() {
            if let hotspot = hotspotPaths[node.path], node.allocatedSize > 0 {
                hotspotTotals[hotspot] = (node.path, node.allocatedSize, node.fileCount)
            }
            if node.name == "node_modules" {
                // Count each top-level node_modules once (nested ones are inside its size) and stop descending.
                var aggregate = hotspotTotals[.nodeModules] ?? (path: node.path, bytes: 0, count: 0)
                if node.allocatedSize > aggregate.bytes { aggregate.path = node.path }
                aggregate.bytes += node.allocatedSize
                aggregate.count += 1
                hotspotTotals[.nodeModules] = aggregate
                totals[inherited ?? .developer, default: 0] += node.allocatedSize
                continue
            }
            for file in node.files {
                let category = inherited ?? Self.category(forFileName: file.name)
                totals[category, default: 0] += file.allocatedSize
            }
            for child in node.directories {
                let forced = pathRules[child.path]
                    ?? (inherited == nil ? Self.category(forDirectoryName: child.name) : nil)
                stack.append((child, forced ?? inherited))
            }
        }

        let hotspots = hotspotTotals.map { Hotspot(kind: $0.key, path: $0.value.path, bytes: $0.value.bytes, itemCount: $0.value.count) }
            .sorted { $0.bytes > $1.bytes }
        return CategoryReport(totals: totals, hotspots: hotspots)
    }
}
