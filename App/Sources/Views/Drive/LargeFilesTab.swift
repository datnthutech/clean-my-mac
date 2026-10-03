import DiskKit
import QuickLook
import SwiftUI

struct LargeFilesTab: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var l: Localizer
    let scan: VolumeScan

    @State private var selection: Set<String> = []
    @State private var previewURL: URL?

    var body: some View {
        let files = scan.largeFiles
        VStack(alignment: .leading, spacing: 8) {
            Text(l.t("largeFiles.subtitle", l.bytes(settings.largeFileMinimumBytes), "\(files.count)"))
                .font(.callout).foregroundStyle(.secondary)
            if files.isEmpty {
                EmptyStateView(symbol: "checkmark.circle", title: l.t("largeFiles.none"), message: "")
            } else {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(files) { file in
                            HStack(spacing: 10) {
                                Image(systemName: Theme.symbol(for: file.category))
                                    .foregroundStyle(Theme.color(for: file.category))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name).lineLimit(1)
                                    Text(file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(l.date(file.modificationDate, time: false)).font(.caption).foregroundStyle(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                                Text(l.bytes(file.allocatedSize)).font(.body.weight(.semibold).monospacedDigit())
                                    .frame(width: 84, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                            .tag(file.path)
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .contextMenu(forSelectionType: String.self) { ids in
                        if ids.count == 1, let id = ids.first {
                            Button(l.t("action.revealInFinder")) { state.reveal(id) }
                            Button(l.t("action.quickLook")) { previewURL = URL(fileURLWithPath: id) }
                            Divider()
                        }
                        if !ids.isEmpty {
                            Button(l.t("action.moveToTrash"), role: .destructive) { trash(ids, files: files) }
                        }
                    } primaryAction: { ids in
                        if let id = ids.first { previewURL = URL(fileURLWithPath: id) }
                    }

                    let chosen = files.filter { selection.contains($0.path) }
                    SelectionActionBar(
                        summary: chosen.isEmpty
                            ? l.t("largeFiles.total", l.bytes(files.reduce(0) { $0 + $1.allocatedSize }))
                            : l.t("selection.summary", l.number(chosen.count), l.bytes(chosen.reduce(0) { $0 + $1.allocatedSize })),
                        onReveal: selection.isEmpty ? nil : { selection.forEach(state.reveal) },
                        onPreview: selection.count == 1 ? { if let id = selection.first { previewURL = URL(fileURLWithPath: id) } } : nil,
                        onTrash: selection.isEmpty ? nil : { trash(selection, files: files) }
                    )
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            }
        }
        .quickLookPreview($previewURL)
    }

    private func trash(_ ids: Set<String>, files: [LargeFile]) {
        state.requestTrash(files.filter { ids.contains($0.path) }.map {
            TrashItem(path: $0.path, bytes: $0.allocatedSize, isDirectory: false)
        })
    }
}
