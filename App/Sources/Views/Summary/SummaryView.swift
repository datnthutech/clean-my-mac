import DiskKit
import SwiftUI

struct SummaryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: l.t("summary.title"), subtitle: subtitle) {
                    Button { state.scanAll() } label: { Label(l.t("action.scanAll"), systemImage: "magnifyingglass") }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isScanning)
                }

                if state.scans.isEmpty && !state.isScanning {
                    NoticeBanner(text: l.t("summary.notScannedYet"), symbol: "info.circle.fill", tint: Theme.accent)
                }

                FindingsCard()

                Text(l.t("summary.drives")).font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(state.volumes) { volume in
                        VolumeCard(volume: volume)
                    }
                }

                if let startup = state.startupVolume, let scan = state.scans[startup.id] {
                    CategoryOverviewCard(scan: scan)
                }
            }
            .padding(28)
        }
    }

    private var subtitle: String {
        guard let date = state.lastScanDate else { return l.t("summary.subtitle.never", "\(state.volumes.count)") }
        let files = state.scans.values.reduce(0) { $0 + $1.result.totalFiles }
        return l.t("summary.subtitle", l.date(date), "\(state.scans.count)", l.number(files))
    }
}

private struct FindingsCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer

    var body: some View {
        Card {
            HStack(spacing: 8) {
                Text(l.t("summary.attention")).font(.headline)
                Spacer()
                let counts = SummaryBuilder.counts(state.findings)
                ForEach([Severity.critical, .warning, .info], id: \.self) { severity in
                    if let count = counts[severity], count > 0 {
                        SeverityBadge(severity: severity, text: "\(count) \(l.t("severity.\(SeverityBadge.key(severity))"))")
                    }
                }
            }
            if state.findings.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.color(for: .ok))
                    Text(state.scans.isEmpty ? l.t("summary.noFindings.unscanned") : l.t("summary.noFindings"))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(state.findings) { finding in
                        Divider()
                        FindingRow(finding: finding)
                    }
                }
            }
        }
    }
}

struct FindingRow: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let finding: Finding

    var body: some View {
        let text = FindingPresenter.text(for: finding, l: l)
        HStack(alignment: .center, spacing: 14) {
            SeverityDot(severity: finding.severity, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).font(.body.weight(.semibold))
                Text(text.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(l.t("action.show")) { state.navigate(to: finding.target) }
        }
        .padding(.vertical, 10)
    }
}

/// Turns a `Finding` into localized title + explanation.
enum FindingPresenter {
    @MainActor
    static func text(for finding: Finding, l: Localizer) -> (title: String, detail: String) {
        switch finding.kind {
        case let .lowDiskSpace(name, free, ratio, isStartup):
            let title = l.t("finding.lowSpace.title", name, l.bytes(free), l.percent(ratio))
            let detailKey: String
            switch (finding.severity, isStartup) {
            case (.critical, true): detailKey = "finding.lowSpace.critical.startup"
            case (_, true): detailKey = "finding.lowSpace.warning.startup"
            default: detailKey = "finding.lowSpace.external"
            }
            return (title, l.t(detailKey))
        case let .dockerDanglingImages(count, bytes):
            return (l.t("finding.docker.title", "\(count)", l.bytes(bytes)), l.t("finding.docker.detail"))
        case let .dockerBuildCache(bytes):
            return (l.t("finding.dockerCache.title", l.bytes(bytes)), l.t("finding.dockerCache.detail"))
        case let .hotspot(kind, bytes):
            return (l.t("finding.hotspot.title", l.t("hotspot.\(kind.rawValue)"), l.bytes(bytes)),
                    l.t("hotspot.\(kind.rawValue).detail"))
        case let .duplicates(groups, bytes):
            return (l.t("finding.duplicates.title", "\(groups)", l.bytes(bytes)), l.t("finding.duplicates.detail"))
        case .fullDiskAccessMissing:
            return (l.t("finding.fda.title"), l.t("finding.fda.detail"))
        case let .unreadableFolders(name, count):
            return (l.t("finding.unreadable.title", name, "\(count)"), l.t("finding.unreadable.detail"))
        }
    }
}

private struct VolumeCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let volume: VolumeInfo

    var body: some View {
        let severity = state.severity(of: volume)
        Button { state.selection = .volume(volume.id) } label: {
            Card {
                HStack {
                    Image(systemName: Theme.symbol(for: volume))
                    Text(volume.name).font(.headline).lineLimit(1)
                    Spacer()
                    if state.scans[volume.id] == nil {
                        SeverityBadge(severity: severity, text: severity == .ok ? l.t("volume.notScanned") : nil)
                    } else {
                        SeverityBadge(severity: severity)
                    }
                }
                CapacityBar(segments: [CapacitySegment(id: "used", fraction: volume.usedRatio, color: Theme.color(for: severity))], height: 8)
                Text(l.t("volume.detailLine", l.bytes(volume.usedBytes), l.bytes(volume.totalBytes),
                         l.bytes(volume.availableBytes), volume.format, l.t("volume.kind.\(volume.kind.rawValue)")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct CategoryOverviewCard: View {
    @EnvironmentObject private var l: Localizer
    let scan: VolumeScan

    var body: some View {
        let totals = scan.categories.sortedTotals
        let used = max(scan.volume.usedBytes, scan.categories.categorizedBytes)
        Card {
            Text(l.t("summary.usedFor", scan.volume.name)).font(.headline)
            CapacityBar(segments: totals.map {
                CapacitySegment(id: $0.category.rawValue, fraction: used > 0 ? Double($0.bytes) / Double(used) : 0,
                                color: Theme.color(for: $0.category))
            }, height: 20)
            FlowLegend(items: totals.prefix(8).map { (Theme.color(for: $0.category), "\(l.t("category.\($0.category.rawValue)")) \(l.bytes($0.bytes))") })
        }
    }
}

struct FlowLegend: View {
    let items: [(Color, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(items[index].0).frame(width: 10, height: 10)
                    Text(items[index].1).font(.caption)
                }
            }
        }
    }
}
