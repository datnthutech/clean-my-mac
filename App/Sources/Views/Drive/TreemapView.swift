import DiskKit
import SwiftUI

/// Squarified treemap of the current folder. Click to select, double-click a folder to open it.
struct TreemapView: View {
    @EnvironmentObject private var l: Localizer
    let items: [FolderItem]
    @Binding var selection: Set<String>
    let onOpen: (FolderItem) -> Void

    /// Keep the map readable: the largest tiles individually, the rest merged into "Other".
    private static let maximumTiles = 40

    var body: some View {
        GeometryReader { geo in
            let computed = layout(in: geo.size)
            let shown = computed.shown
            let restBytes = computed.restBytes
            let tiles = computed.tiles
            let lookup = computed.lookup

            ZStack(alignment: .topLeading) {
                ForEach(tiles, id: \.id) { tile in
                    let item = lookup[tile.id]
                    TreemapTile(
                        title: item?.name ?? l.t("treemap.other"),
                        bytes: item?.bytes ?? restBytes,
                        color: color(for: item, index: shown.firstIndex { $0.id == tile.id } ?? 0),
                        isSelected: selection.contains(tile.id)
                    )
                    .frame(width: max(0, tile.rect.width), height: max(0, tile.rect.height))
                    .offset(x: tile.rect.x, y: tile.rect.y)
                    .onTapGesture(count: 2) { if let item { onOpen(item) } }
                    .onTapGesture { if item != nil { selection = [tile.id] } }
                    .help("\(item?.name ?? l.t("treemap.other")) — \(l.bytes(item?.bytes ?? restBytes))")
                }
            }
        }
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(minHeight: 320)
    }

    private func layout(in size: CGSize) -> (shown: [FolderItem], restBytes: Int64, tiles: [TreemapLayout.Tile<String>], lookup: [String: FolderItem]) {
        let shown = Array(items.prefix(Self.maximumTiles))
        let restBytes = items.dropFirst(Self.maximumTiles).reduce(0) { $0 + $1.bytes }
        var entries: [(id: String, value: Double)] = shown.map { (id: $0.id, value: Double($0.bytes)) }
        if restBytes > 0 { entries.append((id: "__other__", value: Double(restBytes))) }
        let tiles = TreemapLayout.squarify(entries, in: LayoutRect(x: 0, y: 0, width: size.width, height: size.height))
        let lookup = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (shown, restBytes, tiles, lookup)
    }

    private func color(for item: FolderItem?, index: Int) -> Color {
        guard let item else { return Theme.color(for: .other) }
        if item.kind == .file { return Theme.color(for: item.category ?? .other) }
        // Folders: cycle through the category palette so neighbours differ.
        let palette: [StorageCategory] = [.developer, .applications, .media, .documents, .music, .docker, .archives, .caches]
        return Theme.color(for: palette[index % palette.count])
    }
}

private struct TreemapTile: View {
    @EnvironmentObject private var l: Localizer
    let title: String
    let bytes: Int64
    let color: Color
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(color)
                if geo.size.width > 56 && geo.size.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(l.bytes(bytes)).font(.system(size: 11)).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                }
            }
            .overlay(Rectangle().strokeBorder(isSelected ? Color.white : Color.white.opacity(0.6), lineWidth: isSelected ? 3 : 1))
        }
        .contentShape(Rectangle())
    }
}
