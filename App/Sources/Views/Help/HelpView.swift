import DiskKit
import SwiftUI

/// The in-app user guide. Content lives in Localizable.strings (`help.<topic>.*`) so it is translated with the UI.
enum HelpTopic: String, CaseIterable, Identifiable {
    case quickStart
    case fullDiskAccess
    case scanning
    case severity
    case folders
    case duplicates
    case docker
    case deleting
    case faq

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .quickStart: return "sparkles"
        case .fullDiskAccess: return "lock.shield"
        case .scanning: return "magnifyingglass"
        case .severity: return "exclamationmark.triangle"
        case .folders: return "square.grid.3x3.square"
        case .duplicates: return "doc.on.doc"
        case .docker: return "shippingbox"
        case .deleting: return "trash"
        case .faq: return "questionmark.bubble"
        }
    }
}

struct HelpView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var l: Localizer
    @State private var topic: HelpTopic? = .quickStart

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $topic) {
                Section(l.t("help.toc")) {
                    ForEach(HelpTopic.allCases) { item in
                        Label(l.t("help.\(item.rawValue).title"), systemImage: item.symbol).tag(item)
                    }
                }
            }
            // Not `.sidebar`: only the app menu may act as the window's sidebar.
            .listStyle(.inset)
            .frame(width: 240)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(l.t("help.\((topic ?? .quickStart).rawValue).title")).font(.system(size: 24, weight: .bold))
                        Spacer()
                        Picker(l.t("settings.language"), selection: $settings.language) {
                            ForEach(AppLanguage.allCases) { Text(l.t("language.\($0.rawValue)")).tag($0) }
                        }
                        .frame(width: 220)
                    }
                    content(for: topic ?? .quickStart)
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
                .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func content(for topic: HelpTopic) -> some View {
        switch topic {
        case .quickStart:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(1...4, id: \.self) { step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(step)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Theme.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.t("help.quickStart.step\(step).title")).font(.headline)
                            Text(l.t("help.quickStart.step\(step).body")).fixedSize(horizontal: false, vertical: true)
                            if step == 1 {
                                Button(l.t("onboarding.openSettings")) { state.openFullDiskAccessSettings() }
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
            }
            severityTable
        case .severity:
            paragraphs(for: topic)
            severityTable
        case .fullDiskAccess:
            paragraphs(for: topic)
            HStack {
                Button(l.t("onboarding.openSettings")) { state.openFullDiskAccessSettings() }.buttonStyle(.borderedProminent)
                Button(l.t("onboarding.recheck")) { state.recheckFullDiskAccess() }
                Label(state.fullDiskAccessGranted ? l.t("fda.granted") : l.t("fda.missing"),
                      systemImage: state.fullDiskAccessGranted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(Theme.color(for: state.fullDiskAccessGranted ? .ok : .critical))
            }
        default:
            paragraphs(for: topic)
        }
    }

    private func paragraphs(for topic: HelpTopic) -> some View {
        let text = l.t("help.\(topic.rawValue).body")
        let blocks = text.components(separatedBy: "\n\n")
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { index in
                Text(blocks[index]).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
        }
    }

    private var severityTable: some View {
        let policy = settings.policy
        let rows: [(Severity, String)] = [
            (.critical, l.t("help.severity.critical", l.bytes(policy.criticalFreeBytes), l.percent(policy.criticalFreeRatio))),
            (.warning, l.t("help.severity.warning", l.bytes(policy.warningFreeBytes), l.percent(policy.warningFreeRatio))),
            (.ok, l.t("help.severity.ok")),
        ]
        return Card {
            Text(l.t("help.severity.tableTitle")).font(.headline)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top, spacing: 10) {
                    SeverityDot(severity: row.0, size: 10).padding(.top, 4)
                    Text(l.t("severity.\(SeverityBadge.key(row.0))")).font(.body.weight(.semibold)).frame(width: 120, alignment: .leading)
                    Text(row.1).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
