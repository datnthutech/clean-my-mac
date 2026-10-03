import DiskKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer

    var body: some View {
        List(selection: $state.selection) {
            Section(l.t("sidebar.section.overview")) {
                Label(l.t("sidebar.summary"), systemImage: "square.grid.2x2")
                    .badge(state.findings.filter { $0.severity >= .warning }.count)
                    .tag(SidebarItem.summary)
            }

            Section(l.t("sidebar.section.drives")) {
                ForEach(state.volumes) { volume in
                    VolumeRow(volume: volume)
                        .tag(SidebarItem.volume(volume.id))
                }
            }

            Section(l.t("sidebar.section.tools")) {
                Label(l.t("sidebar.duplicates"), systemImage: "doc.on.doc")
                    .badge(state.duplicates.count)
                    .tag(SidebarItem.duplicates)
                Label(l.t("sidebar.docker"), systemImage: "shippingbox")
                    .badge(state.docker.report?.danglingImages.count ?? 0)
                    .tag(SidebarItem.docker)
                Label(l.t("sidebar.deletionLog"), systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.deletionLog)
            }

            Section(l.t("sidebar.section.app")) {
                Label(l.t("sidebar.help"), systemImage: "questionmark.circle")
                    .tag(SidebarItem.help)
                Label(l.t("sidebar.settings"), systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct VolumeRow: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let volume: VolumeInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Theme.symbol(for: volume))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(volume.name).lineLimit(1)
                Text(l.t("volume.freeShort", l.bytes(volume.availableBytes)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            SeverityDot(severity: state.severity(of: volume))
                .help(l.t("severity.\(SeverityBadge.key(state.severity(of: volume)))"))
        }
        .padding(.vertical, 2)
    }
}
