import Foundation

public enum DockerStatus: Equatable, Sendable {
    /// No `docker` command found on this Mac — nothing to clean, no command is run.
    case notInstalled
    /// The CLI exists but the engine (Docker Desktop, OrbStack, Colima…) is not running.
    case notRunning(binary: String)
    case running(binary: String, serverVersion: String)
}

public struct DockerImage: Hashable, Sendable, Identifiable {
    public let id: String
    public let repository: String
    public let tag: String
    public let sizeBytes: Int64
    public let sizeText: String
    public let createdSince: String

    public var isDangling: Bool { repository == "<none>" && tag == "<none>" }
}

public struct DockerDiskUsage: Hashable, Sendable {
    public enum Kind: String, Sendable { case images, containers, volumes, buildCache, other }
    public let kind: Kind
    public let totalCount: Int
    public let active: Int
    public let sizeBytes: Int64
    public let reclaimableBytes: Int64
}

public struct DockerReport: Equatable, Sendable {
    public let binary: String
    public let serverVersion: String
    public let danglingImages: [DockerImage]
    public let diskUsage: [DockerDiskUsage]
    /// Size on disk of Docker Desktop's virtual disk file, when present.
    public let virtualDiskBytes: Int64?

    public var danglingBytes: Int64 { danglingImages.reduce(0) { $0 + $1.sizeBytes } }
    public func usage(_ kind: DockerDiskUsage.Kind) -> DockerDiskUsage? { diskUsage.first { $0.kind == kind } }
}

public struct DockerRemovalResult: Equatable, Sendable {
    public let imageID: String
    public let succeeded: Bool
    public let message: String
}

/// Finds Docker, checks the engine, lists `<none>` (dangling) images and removes them.
///
/// The check is strictly ordered: installed → running → scan. Nothing is executed when Docker is missing.
public struct DockerService: Sendable {
    private let runner: CommandRunner
    private let homePath: String
    private let fileExists: @Sendable (String) -> Bool

    public init(
        runner: CommandRunner = ProcessCommandRunner(),
        homePath: String = NSHomeDirectory(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.runner = runner
        self.homePath = homePath
        self.fileExists = fileExists
    }

    /// GUI apps don't inherit the Terminal's PATH, so look in the places Docker-compatible tools install to.
    public var candidatePaths: [String] {
        [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "\(homePath)/.docker/bin/docker",
            "\(homePath)/.orbstack/bin/docker",
            "\(homePath)/.rd/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
            "/usr/bin/docker",
        ]
    }

    public func locateBinary() -> String? {
        candidatePaths.first(where: fileExists)
    }

    func environment(for binary: String) -> [String: String] {
        let binDir = (binary as NSString).deletingLastPathComponent
        let path = [binDir, "/usr/local/bin", "/opt/homebrew/bin", "\(homePath)/.docker/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return ["PATH": path.joined(separator: ":"), "HOME": homePath, "LANG": "en_US.UTF-8"]
    }

    private func docker(_ binary: String, _ args: [String], timeout: TimeInterval = 20) throws -> CommandResult {
        try runner.run(binary, arguments: args, environment: environment(for: binary), timeout: timeout)
    }

    // MARK: Step 1 + 2

    public func status() -> DockerStatus {
        guard let binary = locateBinary() else { return .notInstalled }
        guard let result = try? docker(binary, ["info", "--format", "{{.ServerVersion}}"], timeout: 8),
              result.succeeded else {
            return .notRunning(binary: binary)
        }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // `docker info` can exit 0 while printing an error placeholder when the daemon is down.
        if version.isEmpty || version.contains("<no value>") { return .notRunning(binary: binary) }
        return .running(binary: binary, serverVersion: version)
    }

    // MARK: Step 3

    public func danglingImages(binary: String) throws -> [DockerImage] {
        let result = try docker(binary, ["images", "--filter", "dangling=true", "--no-trunc", "--format", "{{json .}}"])
        guard result.succeeded else { throw DockerError.commandFailed(result.stderr) }
        return Self.parseImages(result.stdout)
    }

    public func diskUsage(binary: String) throws -> [DockerDiskUsage] {
        let result = try docker(binary, ["system", "df", "--format", "{{json .}}"])
        guard result.succeeded else { throw DockerError.commandFailed(result.stderr) }
        return Self.parseDiskUsage(result.stdout)
    }

    public func virtualDiskBytes() -> Int64? {
        let candidates = [
            "\(homePath)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
            "\(homePath)/Library/Containers/com.docker.docker/Data/vms/0/Docker.raw",
            "\(homePath)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.qcow2",
        ]
        for path in candidates {
            if let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
               let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                return Int64(size)
            }
        }
        return nil
    }

    /// Runs every step and returns a full report. Returns nil status details through `DockerStatus` when not ready.
    public func report() -> (DockerStatus, DockerReport?) {
        let current = status()
        guard case let .running(binary, version) = current else { return (current, nil) }
        let images = (try? danglingImages(binary: binary)) ?? []
        let usage = (try? diskUsage(binary: binary)) ?? []
        return (current, DockerReport(binary: binary, serverVersion: version, danglingImages: images,
                                      diskUsage: usage, virtualDiskBytes: virtualDiskBytes()))
    }

    // MARK: Step 4

    /// Removes images one by one without `--force`, so an image used by any container is refused by Docker itself.
    public func removeImages(ids: [String], binary: String) -> [DockerRemovalResult] {
        ids.map { id in
            do {
                let result = try docker(binary, ["image", "rm", id], timeout: 60)
                let message = (result.succeeded ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
                return DockerRemovalResult(imageID: id, succeeded: result.succeeded, message: message)
            } catch {
                return DockerRemovalResult(imageID: id, succeeded: false, message: "\(error)")
            }
        }
    }

    /// `docker image prune -f`: removes all dangling images. Returns bytes reclaimed as reported by Docker.
    public func pruneDanglingImages(binary: String) throws -> Int64 {
        let result = try docker(binary, ["image", "prune", "-f"], timeout: 300)
        guard result.succeeded else { throw DockerError.commandFailed(result.stderr) }
        return Self.parseReclaimed(result.stdout)
    }

    // MARK: Parsing

    static func parseImages(_ output: String) -> [DockerImage] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let rawID = (object["ID"] as? String) ?? ""
            let id = rawID.hasPrefix("sha256:") ? String(rawID.dropFirst(7)) : rawID
            guard !id.isEmpty else { return nil }
            let sizeText = (object["Size"] as? String) ?? (object["VirtualSize"] as? String) ?? "0B"
            return DockerImage(
                id: id,
                repository: (object["Repository"] as? String) ?? "<none>",
                tag: (object["Tag"] as? String) ?? "<none>",
                sizeBytes: DockerSizeParser.bytes(from: sizeText),
                sizeText: sizeText,
                createdSince: (object["CreatedSince"] as? String) ?? ""
            )
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func parseDiskUsage(_ output: String) -> [DockerDiskUsage] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let type = (object["Type"] as? String) ?? ""
            let kind: DockerDiskUsage.Kind
            switch type.lowercased() {
            case "images": kind = .images
            case "containers": kind = .containers
            case "local volumes", "volumes": kind = .volumes
            case "build cache": kind = .buildCache
            default: kind = .other
            }
            func intValue(_ key: String) -> Int {
                if let number = object[key] as? Int { return number }
                return Int((object[key] as? String) ?? "") ?? 0
            }
            // Reclaimable looks like "6.4GB (52%)".
            let reclaimableText = ((object["Reclaimable"] as? String) ?? "0B").split(separator: " ").first.map(String.init) ?? "0B"
            return DockerDiskUsage(
                kind: kind,
                totalCount: intValue("TotalCount"),
                active: intValue("Active"),
                sizeBytes: DockerSizeParser.bytes(from: (object["Size"] as? String) ?? "0B"),
                reclaimableBytes: DockerSizeParser.bytes(from: reclaimableText)
            )
        }
    }

    static func parseReclaimed(_ output: String) -> Int64 {
        // "Total reclaimed space: 1.2GB"
        for line in output.split(whereSeparator: \.isNewline) where line.lowercased().contains("reclaimed space") {
            if let value = line.split(separator: ":").last {
                return DockerSizeParser.bytes(from: value.trimmingCharacters(in: .whitespaces))
            }
        }
        return 0
    }
}

public enum DockerError: Error, Equatable {
    case commandFailed(String)
}

/// Parses Docker's human sizes ("1.2GB", "980MB", "12.3kB", "512B"). Docker uses decimal units; *iB are binary.
public enum DockerSizeParser {
    public static func bytes(from text: String) -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        var numberPart = ""
        var unitPart = ""
        for character in trimmed {
            if character.isNumber || character == "." {
                if unitPart.isEmpty { numberPart.append(character) }
            } else if !character.isWhitespace {
                unitPart.append(character)
            }
        }
        guard let value = Double(numberPart) else { return 0 }
        let multipliers: [String: Double] = [
            "b": 1, "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12, "pb": 1e15,
            "kib": 1024, "mib": 1_048_576, "gib": 1_073_741_824, "tib": 1_099_511_627_776,
            "k": 1e3, "m": 1e6, "g": 1e9, "t": 1e12,
        ]
        let multiplier = multipliers[unitPart.lowercased()] ?? 1
        return Int64((value * multiplier).rounded())
    }
}
