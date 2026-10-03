import DiskKit
import SwiftUI

struct DockerView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    @State private var unselected: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: l.t("docker.title"), subtitle: subtitle) {
                    Button { state.refreshDocker() } label: { Label(l.t("docker.recheck"), systemImage: "arrow.clockwise") }
                        .disabled(state.isDockerWorking)
                }
                StepIndicator(state: state.docker)
                content
            }
            .padding(24)
        }
        .onAppear { if state.docker == .unknown { state.refreshDocker() } }
    }

    private var subtitle: String? {
        switch state.docker {
        case let .ready(report): return "\(l.t("docker.engine")) \(report.serverVersion) · \(report.binary)"
        case let .notRunning(binary): return binary
        default: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.docker {
        case .unknown, .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(l.t("docker.checking"))
            }
            .padding(.top, 20)
        case .notInstalled:
            Card {
                Label(l.t("docker.notInstalled.title"), systemImage: "checkmark.seal").font(.headline)
                Text(l.t("docker.notInstalled.message")).foregroundStyle(.secondary)
            }
        case .notRunning:
            Card {
                Label(l.t("docker.notRunning.title"), systemImage: "pause.circle").font(.headline)
                Text(l.t("docker.notRunning.message")).foregroundStyle(.secondary)
                HStack {
                    Button(l.t("docker.openApp")) { state.openDockerApp() }.buttonStyle(.borderedProminent)
                    Button(l.t("docker.recheck")) { state.refreshDocker() }
                }
            }
        case let .failed(message):
            NoticeBanner(text: l.t("docker.failed") + (message.isEmpty ? "" : "\n\(message)"))
        case let .ready(report):
            readyContent(report)
        }
    }

    @ViewBuilder
    private func readyContent(_ report: DockerReport) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            StatTile(title: l.t("docker.stat.dangling"), value: l.bytes(report.danglingBytes),
                     caption: l.t("docker.stat.images", "\(report.danglingImages.count)"),
                     tint: report.danglingImages.isEmpty ? nil : Theme.color(for: .warning))
            if let images = report.usage(.images) {
                StatTile(title: l.t("docker.stat.allImages"), value: l.bytes(images.sizeBytes),
                         caption: l.t("docker.stat.reclaimable", l.bytes(images.reclaimableBytes)))
            }
            if let cache = report.usage(.buildCache) {
                StatTile(title: l.t("docker.stat.buildCache"), value: l.bytes(cache.sizeBytes),
                         caption: l.t("docker.stat.reclaimable", l.bytes(cache.reclaimableBytes)))
            }
            if let disk = report.virtualDiskBytes {
                StatTile(title: l.t("docker.stat.virtualDisk"), value: l.bytes(disk), caption: l.t("docker.stat.virtualDiskCaption"))
            }
        }

        Card(padding: 0) {
            if report.danglingImages.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.color(for: .ok))
                    Text(l.t("docker.noDangling"))
                }
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text(l.t("docker.danglingList")).font(.headline)
                        Spacer()
                        Button(unselected.isEmpty ? l.t("docker.selectNone") : l.t("docker.selectAll")) {
                            unselected = unselected.isEmpty ? Set(report.danglingImages.map(\.id)) : []
                        }
                        .buttonStyle(.link)
                    }
                    .padding(12)
                    ForEach(report.danglingImages) { image in
                        Divider()
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { !unselected.contains(image.id) },
                                set: { if $0 { unselected.remove(image.id) } else { unselected.insert(image.id) } }
                            ))
                            .toggleStyle(.checkbox).labelsHidden()
                            Text(String(image.id.prefix(12))).font(.system(.body, design: .monospaced))
                            Text("\(image.repository):\(image.tag)").foregroundStyle(.secondary)
                            Spacer()
                            Text(image.createdSince).font(.caption).foregroundStyle(.secondary)
                            Text(l.bytes(image.sizeBytes)).font(.body.weight(.semibold).monospacedDigit())
                                .frame(width: 84, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    Divider()
                    let chosen = report.danglingImages.filter { !unselected.contains($0.id) }
                    HStack {
                        Text(l.t("docker.selected", "\(chosen.count)", l.bytes(chosen.reduce(0) { $0 + $1.sizeBytes })))
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        if state.isDockerWorking { ProgressView().controlSize(.small) }
                        Button(role: .destructive) { state.requestDockerRemoval(chosen) } label: {
                            Label(l.t("docker.removeButton", "\(chosen.count)"), systemImage: "trash")
                        }
                        .disabled(chosen.isEmpty || state.isDockerWorking)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                }
            }
        }

        NoticeBanner(text: l.t("docker.note"), symbol: "info.circle.fill", tint: Theme.accent)
    }
}

private struct StepIndicator: View {
    @EnvironmentObject private var l: Localizer
    let state: DockerState

    var body: some View {
        let reached: Int = {
            switch state {
            case .unknown, .checking: return 0
            case .notInstalled: return 0
            case .notRunning: return 1
            case .failed: return 2
            case .ready: return 3
            }
        }()
        let failedAt: Int? = {
            switch state {
            case .notInstalled: return 1
            case .notRunning: return 2
            default: return nil
            }
        }()
        HStack(spacing: 22) {
            ForEach(1...4, id: \.self) { step in
                HStack(spacing: 8) {
                    ZStack {
                        if step <= reached {
                            Circle().fill(Theme.color(for: .ok))
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        } else if step == failedAt {
                            Circle().fill(Theme.color(for: .warning))
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(Color.secondary, lineWidth: 1.5)
                            Text("\(step)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 20, height: 20)
                    Text(l.t("docker.step\(step)")).font(.callout)
                        .foregroundStyle(step <= reached || step == failedAt ? .primary : .secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    var tint: Color?

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(tint ?? .primary)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
