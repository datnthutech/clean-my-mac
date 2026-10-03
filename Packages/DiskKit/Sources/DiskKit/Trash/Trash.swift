import Foundation

/// Decides which paths may never be moved to the Trash from inside the app.
public struct TrashGuard: Sendable {
    public enum Decision: Equatable, Sendable {
        case allowed
        case protected(reason: Reason)
    }

    public enum Reason: String, Equatable, Sendable {
        case systemLocation
        case essentialFolder
        case volumeRoot
        case applicationItself
        case notAbsolute
    }

    public let homePath: String
    public let appBundlePath: String?
    public let volumeRoots: Set<String>

    public init(homePath: String = NSHomeDirectory(), appBundlePath: String? = Bundle.main.bundlePath, volumeRoots: Set<String> = []) {
        self.homePath = homePath
        self.appBundlePath = appBundlePath
        self.volumeRoots = volumeRoots
    }

    static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/etc", "/var",
                                 "/cores", "/dev", "/opt", "/tmp"]

    public func decision(for rawPath: String) -> Decision {
        guard rawPath.hasPrefix("/") else { return .protected(reason: .notAbsolute) }
        let path = (rawPath as NSString).standardizingPath

        if let app = appBundlePath, path == app || path.hasPrefix(app + "/") {
            return .protected(reason: .applicationItself)
        }
        if path == "/" || volumeRoots.contains(path) || (path.hasPrefix("/Volumes/") && path.split(separator: "/").count == 2) {
            return .protected(reason: .volumeRoot)
        }
        if Self.systemPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .protected(reason: .systemLocation)
        }
        let essential: Set<String> = [
            "/Applications", "/Users", "/Volumes", "/Network", homePath,
            "\(homePath)/Library", "\(homePath)/Desktop", "\(homePath)/Documents", "\(homePath)/Downloads",
            "\(homePath)/Pictures", "\(homePath)/Movies", "\(homePath)/Music", "\(homePath)/Public",
            "\(homePath)/Applications", "\(homePath)/Library/Application Support", "\(homePath)/Library/Preferences",
            "\(homePath)/Library/Containers", "\(homePath)/Library/Group Containers", "\(homePath)/Library/Keychains",
            "\(homePath)/.Trash",
        ]
        if essential.contains(path) { return .protected(reason: .essentialFolder) }
        if path.hasPrefix("\(homePath)/Library/Keychains/") { return .protected(reason: .essentialFolder) }
        return .allowed
    }

    public func isAllowed(_ path: String) -> Bool { decision(for: path) == .allowed }
}

public struct TrashOutcome: Equatable, Sendable {
    public let path: String
    public let succeeded: Bool
    public let trashedPath: String?
    public let errorMessage: String?
}

/// Moves items to the Trash (never deletes permanently) after checking `TrashGuard`.
public struct TrashService: Sendable {
    public let guardrail: TrashGuard

    public init(guardrail: TrashGuard = TrashGuard()) {
        self.guardrail = guardrail
    }

    public func moveToTrash(_ paths: [String]) -> [TrashOutcome] {
        paths.map { path in
            guard guardrail.isAllowed(path) else {
                return TrashOutcome(path: path, succeeded: false, trashedPath: nil, errorMessage: "protected")
            }
            #if os(macOS)
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
                return TrashOutcome(path: path, succeeded: true, trashedPath: resulting?.path, errorMessage: nil)
            } catch {
                return TrashOutcome(path: path, succeeded: false, trashedPath: nil, errorMessage: error.localizedDescription)
            }
            #else
            return TrashOutcome(path: path, succeeded: false, trashedPath: nil, errorMessage: "unsupported platform")
            #endif
        }
    }
}

/// A history of what the app removed, shown in "Deletion log".
public struct DeletionRecord: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case file, folder, dockerImage }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let path: String
    public let bytes: Int64
    public let trashedPath: String?

    public init(id: UUID = UUID(), date: Date = Date(), kind: Kind, path: String, bytes: Int64, trashedPath: String? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.path = path
        self.bytes = bytes
        self.trashedPath = trashedPath
    }
}

public final class DeletionLog: @unchecked Sendable {
    public static let maximumRecords = 2000
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultLocation(appFolder: String = "CleanMyMac") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appFolder).appendingPathComponent("deletion-log.json")
    }

    public func load() -> [DeletionRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DeletionRecord].self, from: data)) ?? []
    }

    @discardableResult
    public func append(_ records: [DeletionRecord]) throws -> [DeletionRecord] {
        var all = load()
        lock.lock(); defer { lock.unlock() }
        all.insert(contentsOf: records.reversed(), at: 0)
        if all.count > Self.maximumRecords { all.removeLast(all.count - Self.maximumRecords) }
        try save(all)
        return all
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        try save([])
    }

    private func save(_ records: [DeletionRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: .atomic)
    }
}
