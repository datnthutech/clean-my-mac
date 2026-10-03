import DiskKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var l: Localizer

    var body: some View {
        Form {
            Section(l.t("settings.general")) {
                Picker(l.t("settings.language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text(l.t("language.\($0.rawValue)")).tag($0) }
                }
                Picker(l.t("settings.externalDrives"), selection: $settings.externalDriveBehavior) {
                    ForEach(ExternalDriveBehavior.allCases) { Text(l.t("settings.external.\($0.rawValue)")).tag($0) }
                }
                Stepper(value: $settings.largeFileMinimumMB, in: 10...10_000, step: 50) {
                    LabeledContent(l.t("settings.largeFileMin"), value: l.bytes(settings.largeFileMinimumBytes))
                }
            }

            Section {
                Stepper(value: gbBinding(\.criticalFreeBytes), in: 1...200) {
                    LabeledContent(l.t("settings.criticalBytes"), value: l.bytes(settings.policy.criticalFreeBytes))
                }
                Stepper(value: percentBinding(\.criticalFreeRatio), in: 1...50) {
                    LabeledContent(l.t("settings.criticalRatio"), value: l.percent(settings.policy.criticalFreeRatio))
                }
                Stepper(value: gbBinding(\.warningFreeBytes), in: 1...500) {
                    LabeledContent(l.t("settings.warningBytes"), value: l.bytes(settings.policy.warningFreeBytes))
                }
                Stepper(value: percentBinding(\.warningFreeRatio), in: 1...60) {
                    LabeledContent(l.t("settings.warningRatio"), value: l.percent(settings.policy.warningFreeRatio))
                }
            } header: {
                Text(l.t("settings.thresholds"))
            } footer: {
                Text(l.t("settings.thresholds.footer")).font(.caption).foregroundStyle(.secondary)
            }

            Section(l.t("settings.permissions")) {
                LabeledContent(l.t("settings.fda")) {
                    Label(state.fullDiskAccessGranted ? l.t("fda.granted") : l.t("fda.missing"),
                          systemImage: state.fullDiskAccessGranted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(Theme.color(for: state.fullDiskAccessGranted ? .ok : .critical))
                }
                HStack {
                    Button(l.t("onboarding.openSettings")) { state.openFullDiskAccessSettings() }
                    Button(l.t("onboarding.recheck")) { state.recheckFullDiskAccess() }
                }
            }

            Section(l.t("settings.about")) {
                LabeledContent(l.t("settings.version"), value: Self.version)
                HStack {
                    Button(l.t("settings.showOnboarding")) { state.showOnboarding = true }
                    Button(l.t("settings.reset")) { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func gbBinding(_ keyPath: WritableKeyPath<HealthPolicy, Int64>) -> Binding<Int> {
        Binding(
            get: { Int(settings.policy[keyPath: keyPath] / ByteFormatter.gigabyte) },
            set: { settings.policy[keyPath: keyPath] = Int64($0) * ByteFormatter.gigabyte }
        )
    }

    private func percentBinding(_ keyPath: WritableKeyPath<HealthPolicy, Double>) -> Binding<Int> {
        Binding(
            get: { Int((settings.policy[keyPath: keyPath] * 100).rounded()) },
            set: { settings.policy[keyPath: keyPath] = Double($0) / 100 }
        )
    }
}
