import DiskKit
import SwiftUI

struct DriveDetailView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let volumeID: String

    var body: some View {
        if let volume = state.volume(id: volumeID) {
            VStack(alignment: .leading, spacing: 16) {
                DriveHeader(volume: volume, scan: state.scans[volumeID])
                if let scan = state.scans[volumeID] {
                    Picker("", selection: tabBinding) {
                        ForEach(DriveTab.allCases) { tab in
                            Text(l.t("drive.tab.\(tab.rawValue)")).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)

                    switch tabBinding.wrappedValue {
                    case .categories: CategoriesTab(scan: scan)
                    case .folders: FoldersTab(scan: scan)
                    case .largeFiles: LargeFilesTab(scan: scan)
                    }
                } else {
                    EmptyStateView(
                        symbol: Theme.symbol(for: volume),
                        title: l.t("drive.notScanned.title"),
                        message: volume.isExternal ? l.t("drive.notScanned.external") : l.t("drive.notScanned.message"),
                        actionTitle: l.t("drive.scanThis"),
                        action: { state.scan(volume) }
                    )
                    .disabled(state.isScanning)
                }
            }
            .padding(24)
        } else {
            EmptyStateView(symbol: "externaldrive.badge.xmark", title: l.t("drive.missing"), message: "")
        }
    }

    private var tabBinding: Binding<DriveTab> {
        Binding(get: { state.driveTabs[volumeID] ?? .categories }, set: { state.driveTabs[volumeID] = $0 })
    }
}

private struct DriveHeader: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let volume: VolumeInfo
    let scan: VolumeScan?

    var body: some View {
        let severity = state.severity(of: volume)
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(volume.name).font(.system(size: 24, weight: .bold))
                    SeverityBadge(severity: severity, text: "\(l.t("severity.\(SeverityBadge.key(severity))")) · \(l.t("volume.freeShort", l.bytes(volume.availableBytes)))")
                }
                CapacityBar(segments: segments, height: 10)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Button { state.scan(volume) } label: {
                Label(scan == nil ? l.t("drive.scanThis") : l.t("drive.rescan"), systemImage: "arrow.clockwise")
            }
            .disabled(state.isScanning)
        }
    }

    private var segments: [CapacitySegment] {
        guard let scan, volume.totalBytes > 0 else {
            return [CapacitySegment(id: "used", fraction: volume.usedRatio, color: Theme.color(for: state.severity(of: volume)))]
        }
        var result = scan.categories.sortedTotals.map {
            CapacitySegment(id: $0.category.rawValue, fraction: Double($0.bytes) / Double(volume.totalBytes), color: Theme.color(for: $0.category))
        }
        let unscanned = volume.usedBytes - scan.categories.categorizedBytes
        if unscanned > 0 {
            result.append(CapacitySegment(id: "unscanned", fraction: Double(unscanned) / Double(volume.totalBytes), color: Theme.unscanned))
        }
        return result
    }

    private var detail: String {
        var parts = [l.t("volume.usedOf", l.bytes(volume.usedBytes), l.bytes(volume.totalBytes)), volume.format,
                     l.t("volume.kind.\(volume.kind.rawValue)")]
        if let scan {
            parts.append(l.t("drive.scannedAt", l.date(scan.scannedAt), l.number(scan.result.totalFiles), l.duration(scan.result.duration)))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Categories

private struct CategoriesTab: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let scan: VolumeScan

    var body: some View {
        let totals = scan.categories.sortedTotals
        let unscanned = max(0, scan.volume.usedBytes - scan.categories.categorizedBytes)
        let base = Double(max(1, scan.categories.categorizedBytes + unscanned))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    Text(l.t("drive.categories.title")).font(.headline)
                    ForEach(totals, id: \.category) { item in
                        CategoryRow(symbol: Theme.symbol(for: item.category), color: Theme.color(for: item.category),
                                    title: l.t("category.\(item.category.rawValue)"),
                                    subtitle: l.t("category.\(item.category.rawValue).detail"),
                                    bytes: item.bytes, fraction: Double(item.bytes) / base)
                    }
                    if unscanned > 0 {
                        CategoryRow(symbol: "lock", color: Theme.unscanned, title: l.t("category.unscanned"),
                                    subtitle: l.t("category.unscanned.detail"), bytes: unscanned, fraction: Double(unscanned) / base)
                    }
                }
                if !scan.categories.hotspots.isEmpty {
                    Card {
                        Text(l.t("drive.hotspots.title")).font(.headline)
                        Text(l.t("drive.hotspots.subtitle")).font(.callout).foregroundStyle(.secondary)
                        ForEach(scan.categories.hotspots) { hotspot in
                            Divider()
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.t("hotspot.\(hotspot.kind.rawValue)")).font(.body.weight(.semibold))
                                    Text(hotspot.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(l.bytes(hotspot.bytes)).font(.body.weight(.semibold).monospacedDigit())
                                Button(l.t("action.show")) {
                                    state.navigate(to: .folder(volume: scan.volume.id, path: hotspot.path))
                                }
                                Button { state.reveal(hotspot.path) } label: { Image(systemName: "magnifyingglass") }
                                    .help(l.t("action.revealInFinder"))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryRow: View {
    @EnvironmentObject private var l: Localizer
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let bytes: Int64
    let fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(l.bytes(bytes)).font(.body.weight(.semibold).monospacedDigit())
                    Text(l.percent(fraction)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                }
                CapacityBar(segments: [CapacitySegment(id: title, fraction: fraction, color: color)], height: 6)
            }
        }
        .padding(.vertical, 3)
    }
}
