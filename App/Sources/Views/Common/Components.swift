import DiskKit
import SwiftUI

struct SeverityBadge: View {
    @EnvironmentObject private var l: Localizer
    let severity: Severity
    var text: String?

    var body: some View {
        Text(text ?? l.t("severity.\(Self.key(severity))"))
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Theme.color(for: severity))
            .background(Theme.color(for: severity).opacity(0.14), in: Capsule())
    }

    static func key(_ severity: Severity) -> String {
        switch severity {
        case .critical: return "critical"
        case .warning: return "warning"
        case .info: return "info"
        case .ok: return "ok"
        }
    }
}

struct SeverityDot: View {
    let severity: Severity
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(Theme.color(for: severity)).frame(width: size, height: size)
    }
}

/// A rounded panel used for every section.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct CapacitySegment: Identifiable {
    let id: String
    let fraction: Double
    let color: Color
}

/// Horizontal usage bar, either a single fill or one segment per category.
struct CapacityBar: View {
    let segments: [CapacitySegment]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, geo.size.width * min(1, segment.fraction)))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: height / 2))
        }
        .frame(height: height)
    }
}

/// Shown on screens that need a scan first.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Yellow banner for important caveats (e.g. "same name ≠ same content").
struct NoticeBanner: View {
    let text: String
    var symbol = "exclamationmark.triangle.fill"
    var tint = Theme.color(for: .warning)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 26, weight: .bold))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Bottom action bar shared by lists that can reveal / preview / trash a selection.
struct SelectionActionBar: View {
    @EnvironmentObject private var l: Localizer
    let summary: String
    var onReveal: (() -> Void)?
    var onPreview: (() -> Void)?
    var trashTitle: String?
    var onTrash: (() -> Void)?

    var body: some View {
        AdaptiveActionBar(summary: summary) {
            if let onReveal { Button(l.t("action.revealInFinder"), action: onReveal) }
            if let onPreview { Button(l.t("action.quickLook"), action: onPreview) }
            if let onTrash {
                Button(role: .destructive, action: onTrash) {
                    Label(trashTitle ?? l.t("action.moveToTrash"), systemImage: "trash")
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
    }
}

/// Summary text + buttons that never get clipped: one row if it fits, otherwise the summary
/// moves above the buttons, and on very narrow panes the buttons stack vertically.
struct AdaptiveActionBar<Buttons: View>: View {
    let summary: String
    @ViewBuilder var buttons: Buttons

    var body: some View {
        let label = Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { label; Spacer(minLength: 8); HStack(spacing: 8) { buttons }.fixedSize() }
            VStack(alignment: .leading, spacing: 6) {
                label
                HStack(spacing: 8) { Spacer(minLength: 0); HStack(spacing: 8) { buttons }.fixedSize() }
            }
            VStack(alignment: .trailing, spacing: 6) {
                label.frame(maxWidth: .infinity, alignment: .leading)
                buttons
            }
        }
    }
}

/// The app's equivalent of CSS `overflow: auto` for a whole page.
///
/// The page is laid out at the window's size, but never smaller than `minWidth` × `minHeight`.
/// When the window is smaller than that, scroll bars appear instead of content spilling
/// past the window edge; anything still wider than the page is clipped, never drawn outside.
struct PageContainer<Content: View>: View {
    var minWidth: CGFloat
    var minHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, minWidth)
            let height = max(geo.size.height, minHeight)
            let page = content
                .frame(width: width, height: height, alignment: .topLeading)
                .clipped()
            if width > geo.size.width || height > geo.size.height {
                ScrollView([.horizontal, .vertical]) { page }
            } else {
                page
            }
        }
    }
}
