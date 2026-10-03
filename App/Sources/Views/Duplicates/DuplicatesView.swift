import DiskKit
import QuickLook
import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var l: Localizer

    @State private var selectedGroup: String?
    /// Files ticked for removal, per group. Defaults to "everything except the newest copy".
    @State private var marked: [String: Set<String>] = [:]
    @State private var previewURL: URL?

    private static let sizeOptions: [Int64] = [0, 1, 10, 100, 1000].map { $0 * ByteFormatter.megabyte }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: l.t("duplicates.title"), subtitle: subtitle)
            // Filters get their own row and stack vertically when the window is too narrow,
            // so long (Vietnamese) labels can never push the page wider than the window.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { filterControls }
                VStack(alignment: .leading, spacing: 8) { filterControls }
            }
            .toggleStyle(.checkbox)
            .disabled(state.isBusy)
            NoticeBanner(text: l.t("duplicates.notice"))

            if state.scans.isEmpty {
                EmptyStateView(symbol: "doc.on.doc", title: l.t("duplicates.empty.title"), message: l.t("duplicates.empty.message"),
                               actionTitle: l.t("action.scanAll"), action: { state.scanAll() })
            } else if state.isFindingDuplicates {
                ProgressView(l.t("duplicates.searching")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.duplicates.isEmpty {
                EmptyStateView(symbol: "checkmark.circle", title: l.t("duplicates.none.title"), message: l.t("duplicates.none.message"))
            } else {
                HStack(alignment: .top, spacing: 16) {
                    groupList.frame(minWidth: 240, idealWidth: 320, maxWidth: 360)
                    groupDetail.frame(minWidth: 380, maxWidth: .infinity)
                }
            }
        }
        .padding(24)
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private var filterControls: some View {
        Toggle(l.t("duplicates.skipDev"), isOn: optionBinding(\.skipDeveloperFolders))
        Toggle(l.t("duplicates.skipLibrary"), isOn: optionBinding(\.skipLibraryAndSystem))
        Picker(l.t("duplicates.minSize"), selection: optionBinding(\.minimumSize)) {
            ForEach(Self.sizeOptions, id: \.self) { size in
                Text(size == 0 ? l.t("duplicates.anySize") : l.bytes(size)).tag(size)
            }
        }
        .fixedSize()
    }

    /// Parent folder of a copy, with the home folder shortened to "~".
    static func displayFolder(of path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    private var subtitle: String {
        l.t("duplicates.subtitle", "\(state.duplicates.count)", l.number(state.duplicates.reduce(0) { $0 + $1.files.count }),
            l.bytes(state.duplicateReclaimableBytes))
    }

    private func optionBinding<T>(_ keyPath: WritableKeyPath<DuplicateOptions, T>) -> Binding<T> {
        Binding(
            get: { settings.duplicateOptions[keyPath: keyPath] },
            set: { value in
                settings.duplicateOptions[keyPath: keyPath] = value
                marked = [:]
                Task { await state.findDuplicates() }
            }
        )
    }

    private var groupList: some View {
        List(selection: $selectedGroup) {
            ForEach(state.duplicates) { group in
                HStack {
                    Text(group.displayName).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("\(group.files.count)").foregroundStyle(.secondary).monospacedDigit()
                    Text(l.bytes(group.reclaimableSize)).font(.body.weight(.semibold).monospacedDigit())
                        .frame(width: 78, alignment: .trailing)
                }
                .tag(group.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        .onAppear { if selectedGroup == nil { selectedGroup = state.duplicates.first?.id } }
    }

    @ViewBuilder
    private var groupDetail: some View {
        if let group = state.duplicates.first(where: { $0.id == selectedGroup }) ?? state.duplicates.first {
            let ticked = marked[group.id] ?? Set(group.files.dropFirst().map(\.path))
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName).font(.headline)
                    Text(l.t("duplicates.groupSummary", "\(group.files.count)", l.bytes(group.totalSize), l.bytes(group.reclaimableSize)))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(12)
                Divider()
                List {
                    ForEach(group.files) { file in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { ticked.contains(file.path) },
                                set: { isOn in
                                    var updated = ticked
                                    if isOn { updated.insert(file.path) } else { updated.remove(file.path) }
                                    marked[group.id] = updated
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    // All copies share the name, so show where each one lives.
                                    Text(Self.displayFolder(of: file.path))
                                        .lineLimit(1).truncationMode(.middle)
                                        .help(file.path)
                                    if file == group.newest {
                                        SeverityBadge(severity: .ok, text: l.t("duplicates.newest")).fixedSize()
                                    }
                                }
                                Text("\(file.volumeName) · \(l.date(file.modificationDate))")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.tail)
                            }
                            .layoutPriority(1)
                            Spacer(minLength: 4)
                            Text(l.bytes(file.allocatedSize)).monospacedDigit().fixedSize()
                            Button { previewURL = URL(fileURLWithPath: file.path) } label: { Image(systemName: "eye") }
                                .buttonStyle(.borderless).help(l.t("action.quickLook"))
                            Button { state.reveal(file.path) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless).help(l.t("action.revealInFinder"))
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
                let chosen = group.files.filter { ticked.contains($0.path) }
                let summary = Text(l.t("selection.summary", "\(chosen.count)", l.bytes(chosen.reduce(0) { $0 + $1.allocatedSize })))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                let actions = HStack(spacing: 8) {
                    Button(l.t("duplicates.keepNewest")) { marked[group.id] = Set(group.files.dropFirst().map(\.path)) }
                    Button(role: .destructive) {
                        state.requestTrash(chosen.map { TrashItem(path: $0.path, bytes: $0.allocatedSize, isDirectory: false) })
                    } label: {
                        Label(l.t("duplicates.trashSelected", "\(chosen.count)"), systemImage: "trash")
                    }
                    .disabled(chosen.isEmpty || chosen.count == group.files.count)
                    .help(chosen.count == group.files.count ? l.t("duplicates.keepOne") : "")
                }
                .fixedSize()
                // One row when there is room, otherwise the summary goes above the buttons.
                ViewThatFits(in: .horizontal) {
                    HStack { summary; Spacer(minLength: 8); actions }
                    VStack(alignment: .leading, spacing: 6) { summary; HStack { Spacer(minLength: 0); actions } }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}
