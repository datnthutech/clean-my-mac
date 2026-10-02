import DiskKit
import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case vietnamese = "vi"
    case english = "en"

    var id: String { rawValue }
}

/// Looks strings up in the chosen language's `.lproj`, so switching language in Settings
/// takes effect immediately without restarting the app.
@MainActor
final class Localizer: ObservableObject {
    @Published private(set) var languageCode: String = "en"
    private(set) var locale = Locale(identifier: "en_US")
    private var bundle: Bundle = .main
    private var fallback: Bundle = .main

    init(language: AppLanguage) {
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let en = Bundle(path: path) {
            fallback = en
        }
        apply(language)
    }

    static func resolve(_ language: AppLanguage) -> String {
        switch language {
        case .vietnamese: return "vi"
        case .english: return "en"
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("vi") ? "vi" : "en"
        }
    }

    func apply(_ language: AppLanguage) {
        let code = Self.resolve(language)
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let localized = Bundle(path: path) {
            bundle = localized
        } else {
            bundle = fallback
        }
        locale = Locale(identifier: code == "vi" ? "vi_VN" : "en_US")
        languageCode = code
    }

    func t(_ key: String) -> String {
        let missing = "\u{1}"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        if value != missing { return value }
        let english = fallback.localizedString(forKey: key, value: missing, table: nil)
        return english == missing ? key : english
    }

    /// Format with `%@` placeholders; pass every argument as a String.
    func t(_ key: String, _ args: String...) -> String {
        String(format: t(key), locale: locale, arguments: args.map { $0 as NSString })
    }

    func bytes(_ value: Int64) -> String {
        ByteFormatter.string(value, locale: locale)
    }

    func percent(_ ratio: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = ratio < 0.1 && ratio > 0 ? 1 : 0
        return formatter.string(from: NSNumber(value: ratio)) ?? "\(Int(ratio * 100))%"
    }

    func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func date(_ date: Date, time: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = time ? .short : .none
        return formatter.string(from: date)
    }

    func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
