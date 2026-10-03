import AppKit
import Combine
import DiskKit
import Foundation

enum SidebarItem: Hashable {
    case summary
    case volume(String)
    case duplicates
    case docker
    case deletionLog
    case help
    case settings
}

enum DriveTab: String, CaseIterable, Identifiable {
    case categories
    case folders
    case largeFiles

    var id: String { rawValue }
}

/// Everything known about one scanned volume.
struct VolumeScan: @unchecked Sendable {
    var volume: VolumeInfo
    var result: ScanResult
    var categories: CategoryReport
    var largeFiles: [LargeFile]
    var scannedAt: Date
}

struct ScanStatus: Equatable {
    var volumeName: String
    var volumeUsedBytes: Int64
    var index: Int
    var total: Int
    var startedAt: Date
}

struct ExternalPrompt: Identifiable {
    let id = UUID()
    let internalVolumes: [VolumeInfo]
    let externalVolumes: [VolumeInfo]
}

enum DockerState: Equatable {
    case unknown
    case checking
    case notInstalled
    case notRunning(binary: String)
    case ready(DockerReport)
    case failed(String)

    var report: DockerReport? {
        if case let .ready(report) = self { return report }
        return nil
    }
}

struct TrashItem: Hashable, Identifiable {
    var id: String { path }
    let path: String
    let bytes: Int64
    let isDirectory: Bool
}

struct TrashRequest: Identifiable {
    let id = UUID()
    let items: [TrashItem]
    let blocked: [TrashItem]

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

struct DockerRemovalRequest: Identifiable {
    let id = UUID()
    let images: [DockerImage]
    var totalBytes: Int64 { images.reduce(0) { $0 + $1.sizeBytes } }
}

/// The single source of truth for the UI. All mutations happen on the main actor;
/// heavy work (scanning, duplicate search, Docker, trashing) runs in detached tasks.
@MainActor
final class AppState: ObservableObject {
    let settings: AppSettings

    @Published var selection: SidebarItem? = .summary
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var scans: [String: VolumeScan] = [:]
    @Published private(set) var lastScanDate: Date?

    @Published private(set) var scanStatus: ScanStatus?
    @Published private(set) var progress = ScanProgress.Snapshot()
    @Published var externalPrompt: ExternalPrompt?
    @Published var mountedVolumePrompt: VolumeInfo?

    @Published private(set) var duplicates: [DuplicateGroup] = []
    @Published private(set) var isFindingDuplicates = false
    @Published private(set) var docker: DockerState = .unknown
    @Published private(set) var isDockerWorking = false
    @Published private(set) var findings: [Finding] = []
    @Published private(set) var fullDiskAccessGranted = true
    @Published private(set) var deletionLog: [DeletionRecord] = []

    @Published var pendingTrash: TrashRequest?
    @Published var pendingDockerRemoval: DockerRemovalRequest?
    @Published var showOnboarding = false
    @Published var message: String?

    /// Per-volume UI state so findings can deep-link into a folder.
    @Published var driveTabs: [String: DriveTab] = [:]
    @Published var folderPaths: [String: String] = [:]

    private let volumeService = VolumeService()
    private let log = DeletionLog(fileURL: DeletionLog.defaultLocation())
    private var currentProgress: ScanProgress?
    private var cancelRequested = false
    private var observers: [NSObjectProtocol] = []
    private var settingsObserver: AnyCancellable?

    init(settings: AppSettings) {
        self.settings = settings
        refreshVolumes()
        fullDiskAccessGranted = FullDiskAccess.isGranted()
        deletionLog = log.load()
        showOnboarding = !settings.hasCompletedOnboarding
        observeMounts()
        settingsObserver = settings.$policy.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildFindings() }
        }
        rebuildFindings()
    }

    var isScanning: Bool { scanStatus != nil }
    var isBusy: Bool { isScanning || isFindingDuplicates }
    var internalVolumes: [VolumeInfo] { volumes.filter { !$0.isExternal } }
    var externalVolumes: [VolumeInfo] { volumes.filter(\.isExternal) }
    var startupVolume: VolumeInfo? { volumes.first { $0.kind == .system } }

    func volume(id: String) -> VolumeInfo? { volumes.first { $0.id == id } }
    func severity(of volume: VolumeInfo) -> Severity { settings.policy.severity(for: volume) }

    // MARK: Volumes

    func refreshVolumes() {
        volumes = volumeService.mountedVolumes()
        let ids = Set(volumes.map(\.id))
        if scans.keys.contains(where: { !ids.contains($0) }) {
            scans = scans.filter { ids.contains($0.key) }
            let names = Set(scans.values.map(\.volume.name))
            duplicates = duplicates.compactMap { group in
                let files = group.files.filter { names.contains($0.volumeName) }
                return files.count >= 2 ? DuplicateGroup(key: group.key, displayName: group.displayName, files: files) : nil
            }
        }
        if case let .volume(id) = selection, !ids.contains(id) { selection = .summary }
        rebuildFindings()
    }

    private func observeMounts() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            let path = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
            Task { @MainActor in self?.volumeMounted(path: path) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshVolumes() }
        })
    }

    private func volumeMounted(path: String?) {
        let before = Set(volumes.map(\.id))
        refreshVolumes()
        let added = volumes.first { volume in
            !before.contains(volume.id) && volume.isExternal && (path == nil || volume.path == path)
        }
        if let added, !isScanning, settings.externalDriveBehavior != .never {
            mountedVolumePrompt = added
        }
    }

    // MARK: Scanning

    /// "Scan all": internal volumes always; external volumes only after asking (unless the user chose otherwise).
    func scanAll() {
        guard !isScanning else { return }
        refreshVolumes()
        let internalList = internalVolumes
        let externalList = externalVolumes
        if externalList.isEmpty {
            startScan(internalList)
            return
        }
        switch settings.externalDriveBehavior {
        case .always: startScan(internalList + externalList)
        case .never: startScan(internalList)
        case .ask: externalPrompt = ExternalPrompt(internalVolumes: internalList, externalVolumes: externalList)
        }
    }

    func resolveExternalPrompt(_ prompt: ExternalPrompt, selected: Set<String>, remember: Bool) {
        externalPrompt = nil
        if remember {
            settings.externalDriveBehavior = selected.isEmpty ? .never : .always
        }
        startScan(prompt.internalVolumes + prompt.externalVolumes.filter { selected.contains($0.id) })
    }

    func scan(_ volume: VolumeInfo) {
        guard !isScanning else { return }
        startScan([volume])
    }

    func cancelScan() {
        cancelRequested = true
        currentProgress?.cancel()
    }

    private func startScan(_ list: [VolumeInfo]) {
        guard !list.isEmpty, !isScanning else { return }
        cancelRequested = false
        fullDiskAccessGranted = FullDiskAccess.isGranted()
        Task { await runScans(list) }
    }

    private func runScans(_ list: [VolumeInfo]) async {
        let home = NSHomeDirectory()
        let minimumLarge = settings.largeFileMinimumBytes
        var scannedAny = false

        for (index, volume) in list.enumerated() {
            if cancelRequested { break }
            let progress = ScanProgress()
            currentProgress = progress
            self.progress = ScanProgress.Snapshot()
            scanStatus = ScanStatus(volumeName: volume.name, volumeUsedBytes: volume.usedBytes,
                                    index: index, total: list.count, startedAt: Date())
            let target = volumeService.scanTarget(for: volume)

            let poller = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.progress = progress.snapshot()
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            let scan = await Task.detached(priority: .userInitiated) { () -> VolumeScan in
                let result = DiskScanner().scan(target, progress: progress)
                let categories = Categorizer(homePath: home).report(for: result.root)
                let large = LargeFileFinder.largestFiles(in: result.root, minimumSize: minimumLarge)
                return VolumeScan(volume: volume, result: result, categories: categories, largeFiles: large, scannedAt: Date())
            }.value
            poller.cancel()

            if scan.result.wasCancelled { break }
            scans[volume.id] = scan
            folderPaths[volume.id] = nil
            scannedAny = true
        }

        currentProgress = nil
        scanStatus = nil
        refreshVolumes()
        guard scannedAny else { return }
        lastScanDate = Date()
        rebuildFindings()
        await findDuplicates()
        refreshDocker()
    }

    // MARK: Duplicates

    func findDuplicates() async {
        guard !scans.isEmpty else { return }
        let sources = scans.values
            .sorted { $0.volume.name < $1.volume.name }
            .map { DuplicateSource(volumeName: $0.volume.name, root: $0.result.root) }
        let options = settings.duplicateOptions
        isFindingDuplicates = true
        let groups = await Task.detached(priority: .utility) {
            DuplicateFinder.find(in: sources, options: options)
        }.value
        duplicates = groups
        isFindingDuplicates = false
        rebuildFindings()
    }

    var duplicateReclaimableBytes: Int64 { duplicates.reduce(0) { $0 + $1.reclaimableSize } }

    // MARK: Docker (installed → running → scan → clean)

    func refreshDocker() {
        guard !isDockerWorking else { return }
        docker = .checking
        isDockerWorking = true
        Task {
            let (status, report) = await Task.detached(priority: .utility) { DockerService().report() }.value
            switch status {
            case .notInstalled: docker = .notInstalled
            case let .notRunning(binary): docker = .notRunning(binary: binary)
            case .running:
                if let report { docker = .ready(report) } else { docker = .failed("") }
            }
            isDockerWorking = false
            rebuildFindings()
        }
    }

    func openDockerApp() {
        let candidates = ["/Applications/Docker.app", "/Applications/OrbStack.app", "/Applications/Rancher Desktop.app"]
        if let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: app))
        }
    }

    func requestDockerRemoval(_ images: [DockerImage]) {
        guard !images.isEmpty else { return }
        pendingDockerRemoval = DockerRemovalRequest(images: images)
    }

    func performDockerRemoval(_ request: DockerRemovalRequest) {
        pendingDockerRemoval = nil
        guard case let .ready(report) = docker, !isDockerWorking else { return }
        isDockerWorking = true
        let binary = report.binary
        let ids = request.images.map(\.id)
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                DockerService().removeImages(ids: ids, binary: binary)
            }.value
            let succeeded = Set(results.filter(\.succeeded).map(\.imageID))
            let records = request.images.filter { succeeded.contains($0.id) }.map {
                DeletionRecord(kind: .dockerImage, path: "docker:\($0.id.prefix(12))", bytes: $0.sizeBytes)
            }
            appendLog(records)
            let failed = results.count - succeeded.count
            isDockerWorking = false
            if failed > 0 { message = "docker.removeFailed" }
            refreshDocker()
        }
    }

    // MARK: Trash

    func requestTrash(_ items: [TrashItem]) {
        guard !items.isEmpty else { return }
        let guardrail = TrashGuard(volumeRoots: Set(volumes.map(\.path)))
        let allowed = items.filter { guardrail.isAllowed($0.path) }
        let blocked = items.filter { !guardrail.isAllowed($0.path) }
        pendingTrash = TrashRequest(items: allowed, blocked: blocked)
    }

    func performTrash(_ request: TrashRequest) {
        pendingTrash = nil
        guard !request.items.isEmpty else { return }
        let guardrail = TrashGuard(volumeRoots: Set(volumes.map(\.path)))
        let paths = request.items.map(\.path)
        Task {
            let outcomes = await Task.detached(priority: .userInitiated) {
                TrashService(guardrail: guardrail).moveToTrash(paths)
            }.value
            let byPath = Dictionary(request.items.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            var removed = Set<String>()
            var records: [DeletionRecord] = []
            for outcome in outcomes where outcome.succeeded {
                removed.insert(outcome.path)
                let item = byPath[outcome.path]
                records.append(DeletionRecord(kind: item?.isDirectory == true ? .folder : .file, path: outcome.path,
                                              bytes: item?.bytes ?? 0, trashedPath: outcome.trashedPath))
            }
            applyRemoval(of: removed)
            appendLog(records)
            if removed.count < paths.count { message = "trash.someFailed" }
        }
    }

    /// Updates trees, large-file lists and duplicate groups after items went to the Trash.
    private func applyRemoval(of paths: Set<String>) {
        guard !paths.isEmpty else { return }
        var touched = Set<String>()
        for path in paths {
            // The deepest matching root wins (an external volume is not part of "/" scans, but be safe).
            let owner = scans
                .filter { _, scan in
                    let root = scan.result.root.path
                    return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
                }
                .max { $0.value.result.root.path.count < $1.value.result.root.path.count }
            guard let owner else { continue }
            if owner.value.result.root.removeItem(atPath: path) != nil { touched.insert(owner.key) }
        }
        for id in touched {
            guard var scan = scans[id] else { continue }
            scan.largeFiles.removeAll { file in paths.contains { file.path == $0 || file.path.hasPrefix($0 + "/") } }
            scan.categories = Categorizer().report(for: scan.result.root)
            scans[id] = scan
        }
        duplicates = DuplicateFinder.removing(paths: paths, from: duplicates)
        refreshVolumes()
        objectWillChange.send()
    }

    private func appendLog(_ records: [DeletionRecord]) {
        guard !records.isEmpty else { return }
        if let all = try? log.append(records) {
            deletionLog = all
        } else {
            deletionLog = records + deletionLog
        }
    }

    func clearDeletionLog() {
        try? log.clear()
        deletionLog = []
    }

    // MARK: Permissions & navigation

    func recheckFullDiskAccess() {
        fullDiskAccessGranted = FullDiskAccess.isGranted()
        rebuildFindings()
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    func finishOnboarding() {
        settings.hasCompletedOnboarding = true
        showOnboarding = false
        recheckFullDiskAccess()
    }

    func navigate(to target: FindingTarget) {
        switch target {
        case let .volume(id):
            selection = .volume(id)
        case let .folder(volume, path):
            driveTabs[volume] = .folders
            folderPaths[volume] = path
            selection = .volume(volume)
        case .duplicates:
            selection = .duplicates
        case .docker:
            selection = .docker
        case .fullDiskAccess:
            showOnboarding = true
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
    }

    // MARK: Summary

    func rebuildFindings() {
        let input = SummaryInput(
            volumes: volumes,
            hotspotsByVolume: scans.mapValues { $0.categories.hotspots },
            duplicateGroups: duplicates.count,
            duplicateReclaimable: duplicateReclaimableBytes,
            docker: docker.report,
            fullDiskAccessGranted: fullDiskAccessGranted,
            policy: settings.policy
        )
        findings = SummaryBuilder.findings(from: input)
    }
}
