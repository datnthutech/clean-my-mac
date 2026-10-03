import DiskKit
import QuickLook
import SwiftUI

/// One row in the folder browser: a sub-folder or a file of the current directory.
struct FolderItem: Identifiable, Hashable {
    enum Kind { case directory, file }
    let id: String
    let name: String
    let kind: Kind
    let bytes: Int64
    let fileCount: Int
    let modified: Date?
    let isPackage: Bool
    let isUnreadable: Bool
    let category: StorageCategory?
}

enum FolderSort: String, CaseIterable, Identifiable {
    case size, name, date
    var id: String { rawValue }
}

struct FoldersTab: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    let scan: VolumeScan

    @State private var selection: Set<String> = []
    @State private var sort: FolderSort = .size
    @State private var previewURL: URL?

    private var root: DirectoryNode { scan.result.root }

    private var current: DirectoryNode {
        if let path = state.folderPaths[scan.volume.id], let node = root.node(atPath: path) { return node }
        return root
    }

    var body: some View {
        let node = current
        let items = Self.items(of: node, sort: sort)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Breadcrumb(root: root, current: node) { open($0) }
                Spacer()
                Picker(l.t("folders.sort"), selection: $sort) {
                    ForEach(FolderSort.allCases) { Text(l.t("folders.sort.\($0.rawValue)")).tag($0) }
                }
                .frame(width: 210)
            }
            HStack(alignment: .top, spacing: 16) {
                TreemapView(items: items.filter { $0.bytes > 0 }, selection: $selection) { item in
                    if item.kind == .directory, let child = node.directories.first(where: { $0.path == item.id }) { open(child) }
                }
                .frame(minWidth: 320, idealWidth: 420, maxWidth: 520)

                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(items) { item in
                            FolderRow(item: item, parentBytes: node.allocatedSize)
                                .tag(item.id)
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .contextMenu(forSelectionType: String.self) { ids in
                        contextMenu(for: items.filter { ids.contains($0.id) }, in: node)
                    } primaryAction: { ids in
                        if ids.count == 1, let id = ids.first, let child = node.directories.first(where: { $0.path == id }) {
                            open(child)
                        }
                    }
                    SelectionActionBar(
                        summary: selectionSummary(items),
                        onReveal: selection.isEmpty ? nil : { selection.forEach(state.reveal) },
                        onPreview: selection.count == 1 ? { if let id = selection.first { previewURL = URL(fileURLWithPath: id) } } : nil,
                        onTrash: selection.isEmpty ? nil : { trash(items) }
                    )
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            }
            if node.isUnreadable || scan.result.unreadableDirectories > 0 {
                Text(l.t("folders.unreadableNote", l.number(scan.result.unreadableDirectories)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: state.folderPaths[scan.volume.id]) { _ in selection = [] }
    }

    private func open(_ node: DirectoryNode) {
        state.folderPaths[scan.volume.id] = node.path
    }

    @ViewBuilder
    private func contextMenu(for chosen: [FolderItem], in node: DirectoryNode) -> some View {
        if chosen.count == 1, let item = chosen.first {
            if item.kind == .directory, let child = node.directories.first(where: { $0.path == item.id }) {
                Button(l.t("folders.open")) { open(child) }
            }
            Button(l.t("action.revealInFinder")) { state.reveal(item.id) }
            Button(l.t("action.quickLook")) { previewURL = URL(fileURLWithPath: item.id) }
            Divider()
        }
        if !chosen.isEmpty {
            Button(l.t("action.moveToTrash"), role: .destructive) {
                state.requestTrash(chosen.map { TrashItem(path: $0.id, bytes: $0.bytes, isDirectory: $0.kind == .directory) })
            }
        }
    }

    private func selectionSummary(_ items: [FolderItem]) -> String {
        let chosen = items.filter { selection.contains($0.id) }
        if chosen.isEmpty { return l.t("folders.itemsSummary", l.number(items.count), l.bytes(current.allocatedSize)) }
        return l.t("selection.summary", l.number(chosen.count), l.bytes(chosen.reduce(0) { $0 + $1.bytes }))
    }

    private func trash(_ items: [FolderItem]) {
        let chosen = items.filter { selection.contains($0.id) }
        state.requestTrash(chosen.map { TrashItem(path: $0.id, bytes: $0.bytes, isDirectory: $0.kind == .directory) })
    }

    static func items(of node: DirectoryNode, sort: FolderSort) -> [FolderItem] {
        var items = node.directories.map {
            FolderItem(id: $0.path, name: $0.name, kind: .directory, bytes: $0.allocatedSize, fileCount: $0.fileCount,
                       modified: $0.modificationDate, isPackage: $0.isPackage, isUnreadable: $0.isUnreadable, category: nil)
        }
        items += node.files.map {
            FolderItem(id: node.childPath($0.name), name: $0.name, kind: .file, bytes: $0.allocatedSize, fileCount: 1,
                       modified: $0.modificationDate, isPackage: false, isUnreadable: false,
                       category: Categorizer.category(forFileName: $0.name))
        }
        switch sort {
        case .size: items.sort { $0.bytes > $1.bytes }
        case .name: items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date: items.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        }
        return items
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var l: Localizer
    let item: FolderItem
    let parentBytes: Int64

    var body: some View {
        let fraction = parentBytes > 0 ? Double(item.bytes) / Double(parentBytes) : 0
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(item.kind == .directory ? Theme.accent : Theme.color(for: item.category ?? .other))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if item.kind == .directory {
                    Text(item.isUnreadable ? l.t("folders.unreadable") : l.t("folders.fileCount", l.number(item.fileCount)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            CapacityBar(segments: [CapacitySegment(id: item.id, fraction: fraction, color: Theme.accent.opacity(0.7))], height: 6)
                .frame(width: 90)
            Text(l.bytes(item.bytes))
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        if item.isUnreadable { return "lock.fill" }
        if item.isPackage { return "shippingbox" }
        return item.kind == .directory ? "folder.fill" : "doc"
    }
}

private struct Breadcrumb: View {
    let root: DirectoryNode
    let current: DirectoryNode
    let onSelect: (DirectoryNode) -> Void

    var body: some View {
        var chain: [DirectoryNode] = []
        var cursor: DirectoryNode? = current
        while let node = cursor {
            chain.insert(node, at: 0)
            if node === root { break }
            cursor = node.parent
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.offset) { pair in
                    let index = pair.offset
                    let node = pair.element
                    if index > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    Button(node === root ? (root.path == "/" ? "/" : root.name) : node.name) { onSelect(node) }
                        .buttonStyle(.link)
                        .font(index == chain.count - 1 ? .callout.weight(.semibold) : .callout)
                }
            }
        }
    }
}
