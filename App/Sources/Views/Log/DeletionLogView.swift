import DiskKit
import SwiftUI

struct DeletionLogView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: l.t("log.title"), subtitle: l.t("log.subtitle", l.bytes(state.deletionLog.reduce(0) { $0 + $1.bytes }))) {
                HStack {
                    Button { state.openTrash() } label: { Label(l.t("log.openTrash"), systemImage: "trash") }
                    Button(l.t("log.clear")) { confirmClear = true }.disabled(state.deletionLog.isEmpty)
                }
            }
            NoticeBanner(text: l.t("log.restoreHint"), symbol: "arrow.uturn.backward.circle.fill", tint: Theme.accent)
            if state.deletionLog.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath", title: l.t("log.empty"), message: "")
            } else {
                List(state.deletionLog) { record in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: record.kind)).frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.path).lineLimit(1).truncationMode(.middle)
                            Text(l.date(record.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(l.bytes(record.bytes)).monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(24)
        .confirmationDialog(l.t("log.clearConfirm"), isPresented: $confirmClear) {
            Button(l.t("log.clear"), role: .destructive) { state.clearDeletionLog() }
        }
    }

    private func icon(for kind: DeletionRecord.Kind) -> String {
        switch kind {
        case .file: return "doc"
        case .folder: return "folder"
        case .dockerImage: return "shippingbox"
        }
    }
}
