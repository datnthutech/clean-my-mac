import DiskKit
import SwiftUI

/// Colors shared by every screen. Mid-tone values that read well in both light and dark mode.
enum Theme {
    static let accent = Color(red: 0.04, green: 0.36, blue: 0.83)

    static func color(for severity: Severity) -> Color {
        switch severity {
        case .critical: return Color(red: 0.77, green: 0.15, blue: 0.11)
        case .warning: return Color(red: 0.76, green: 0.33, blue: 0.0)
        case .info: return accent
        case .ok: return Color(red: 0.12, green: 0.48, blue: 0.23)
        }
    }

    static func color(for category: StorageCategory) -> Color {
        switch category {
        case .applications: return Color(red: 0.18, green: 0.37, blue: 0.77)
        case .developer: return Color(red: 0.42, green: 0.27, blue: 0.76)
        case .media: return Color(red: 0.72, green: 0.38, blue: 0.06)
        case .music: return Color(red: 0.80, green: 0.25, blue: 0.45)
        case .documents: return Color(red: 0.12, green: 0.50, blue: 0.44)
        case .archives: return Color(red: 0.55, green: 0.45, blue: 0.10)
        case .caches: return Color(red: 0.42, green: 0.44, blue: 0.48)
        case .iosBackups: return Color(red: 0.20, green: 0.55, blue: 0.75)
        case .mail: return Color(red: 0.30, green: 0.60, blue: 0.30)
        case .trash: return Color(red: 0.55, green: 0.35, blue: 0.30)
        case .docker: return Color(red: 0.05, green: 0.55, blue: 0.85)
        case .system: return Color(red: 0.36, green: 0.39, blue: 0.45)
        case .other: return Color(red: 0.62, green: 0.64, blue: 0.68)
        }
    }

    static let unscanned = Color.gray.opacity(0.35)

    static func symbol(for category: StorageCategory) -> String {
        switch category {
        case .applications: return "app.badge"
        case .documents: return "doc.text"
        case .media: return "photo.on.rectangle"
        case .music: return "music.note"
        case .archives: return "archivebox"
        case .developer: return "hammer"
        case .caches: return "clock.arrow.circlepath"
        case .iosBackups: return "iphone"
        case .mail: return "envelope"
        case .trash: return "trash"
        case .docker: return "shippingbox"
        case .system: return "gearshape.2"
        case .other: return "questionmark.folder"
        }
    }

    static func symbol(for volume: VolumeInfo) -> String {
        switch volume.kind {
        case .system: return "internaldrive"
        case .internalDrive: return "internaldrive"
        case .external: return volume.isRemovable ? "sdcard" : "externaldrive"
        }
    }
}
