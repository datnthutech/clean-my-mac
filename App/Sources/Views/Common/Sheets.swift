import DiskKit
import SwiftUI

/// "2 external drives detected — scan them too?"
struct ExternalDriveSheet: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let prompt: ExternalPrompt
    @State private var selected: Set<String> = []
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.t("external.title", "\(prompt.externalVolumes.count)")).font(.headline)
                    Text(l.t("external.message")).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                ForEach(prompt.externalVolumes) { volume in
                    Toggle(isOn: Binding(
                        get: { selected.contains(volume.id) },
                        set: { isOn in if isOn { selected.insert(volume.id) } else { selected.remove(volume.id) } }
                    )) {
                        HStack {
                            Image(systemName: Theme.symbol(for: volume))
                            VStack(alignment: .leading) {
                                Text(volume.name).font(.body.weight(.semibold))
                                Text(l.t("external.volumeDetail", l.bytes(volume.totalBytes), volume.format, l.bytes(volume.usedBytes)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                }
            }
            Toggle(l.t("external.remember"), isOn: $remember).toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button(l.t("external.internalOnly")) {
                    state.resolveExternalPrompt(prompt, selected: [], remember: remember)
                }
                .keyboardShortcut(.cancelAction)
                Button(l.t("external.scanSelected", "\(selected.count)")) {
                    state.resolveExternalPrompt(prompt, selected: selected, remember: remember)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { selected = Set(prompt.externalVolumes.map(\.id)) }
    }
}

/// Live scan progress, floating at the bottom of the window.
struct ScanProgressCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer

    var body: some View {
        if let status = state.scanStatus {
            let progress = state.progress
            let fraction = status.volumeUsedBytes > 0
                ? min(0.99, Double(progress.bytesScanned) / Double(status.volumeUsedBytes)) : 0
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(l.t("scan.scanning", status.volumeName)).font(.headline)
                    Spacer()
                    Text(l.t("scan.volumeIndex", "\(status.index + 1)", "\(status.total)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: fraction)
                HStack(spacing: 16) {
                    Text(l.t("scan.files", l.number(progress.filesScanned)))
                    Text(l.bytes(progress.bytesScanned))
                    TimelineView(.periodic(from: status.startedAt, by: 1)) { context in
                        Text(l.duration(context.date.timeIntervalSince(status.startedAt)))
                    }
                    Spacer()
                    Button(l.t("action.cancelScan")) { state.cancelScan() }
                }
                .font(.callout.monospacedDigit())
                Text(progress.currentPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(16)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
    }
}

/// Confirmation before anything is moved to the Trash.
struct TrashConfirmSheet: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let request: TrashRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.color(for: .critical))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.t("trash.confirmTitle", "\(request.items.count)", l.bytes(request.totalBytes))).font(.headline)
                    Text(l.t("trash.confirmMessage")).foregroundStyle(.secondary)
                }
            }
            if !request.items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(request.items.prefix(8)) { item in
                        HStack {
                            Image(systemName: item.isDirectory ? "folder" : "doc")
                            Text(item.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(l.bytes(item.bytes)).monospacedDigit()
                        }
                        .font(.callout)
                    }
                    if request.items.count > 8 {
                        Text(l.t("trash.andMore", "\(request.items.count - 8)")).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            if !request.blocked.isEmpty {
                NoticeBanner(text: l.t("trash.blocked", "\(request.blocked.count)"), symbol: "lock.fill")
            }
            HStack {
                Spacer()
                Button(l.t("action.cancel"), role: .cancel) { state.pendingTrash = nil }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) { state.performTrash(request) } label: {
                    Text(l.t("action.moveToTrash"))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(request.items.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct DockerRemovalSheet: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let request: DockerRemovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l.t("docker.confirmTitle", "\(request.images.count)", l.bytes(request.totalBytes))).font(.headline)
            Text(l.t("docker.confirmMessage")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(l.t("action.cancel"), role: .cancel) { state.pendingDockerRemoval = nil }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) { state.performDockerRemoval(request) } label: {
                    Text(l.t("docker.removeButton", "\(request.images.count)"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
