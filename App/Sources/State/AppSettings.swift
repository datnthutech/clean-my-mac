import DiskKit
import Foundation

/// What to do with external drives when the user presses "Scan all".
enum ExternalDriveBehavior: String, CaseIterable, Codable, Identifiable {
    case ask
    case always
    case never

    var id: String { rawValue }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: Keys.language) } }
    @Published var policy: HealthPolicy { didSet { store(policy, Keys.policy) } }
    @Published var duplicateOptions: DuplicateOptions { didSet { store(duplicateOptions, Keys.duplicates) } }
    @Published var externalDriveBehavior: ExternalDriveBehavior {
        didSet { defaults.set(externalDriveBehavior.rawValue, forKey: Keys.external) }
    }
    @Published var largeFileMinimumMB: Int { didSet { defaults.set(largeFileMinimumMB, forKey: Keys.largeFiles) } }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }

    private enum Keys {
        static let language = "language"
        static let policy = "healthPolicy"
        static let duplicates = "duplicateOptions"
        static let external = "externalDriveBehavior"
        static let largeFiles = "largeFileMinimumMB"
        static let onboarding = "hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        policy = Self.load(HealthPolicy.self, Keys.policy, from: defaults) ?? .default
        duplicateOptions = Self.load(DuplicateOptions.self, Keys.duplicates, from: defaults) ?? DuplicateOptions()
        externalDriveBehavior = ExternalDriveBehavior(rawValue: defaults.string(forKey: Keys.external) ?? "") ?? .ask
        let largeFiles = defaults.integer(forKey: Keys.largeFiles)
        largeFileMinimumMB = largeFiles > 0 ? largeFiles : 100
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    }

    var largeFileMinimumBytes: Int64 { Int64(largeFileMinimumMB) * ByteFormatter.megabyte }

    func resetToDefaults() {
        policy = .default
        duplicateOptions = DuplicateOptions()
        externalDriveBehavior = .ask
        largeFileMinimumMB = 100
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
