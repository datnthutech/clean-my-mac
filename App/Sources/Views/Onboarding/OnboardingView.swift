import DiskKit
import SwiftUI

/// First-launch welcome: what the app does, language choice and Full Disk Access.
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var l: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.t("onboarding.title")).font(.system(size: 22, weight: .bold))
                    Text(l.t("onboarding.subtitle")).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                feature("chart.pie", "onboarding.feature1")
                feature("doc.on.doc", "onboarding.feature2")
                feature("shippingbox", "onboarding.feature3")
                feature("trash", "onboarding.feature4")
            }

            Card {
                HStack {
                    Image(systemName: "lock.shield").font(.title2).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.t("onboarding.fdaTitle")).font(.headline)
                        Text(l.t("onboarding.fdaBody")).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Button(l.t("onboarding.openSettings")) { state.openFullDiskAccessSettings() }
                    Button(l.t("onboarding.recheck")) { state.recheckFullDiskAccess() }
                    Spacer()
                    Label(state.fullDiskAccessGranted ? l.t("fda.granted") : l.t("fda.missing"),
                          systemImage: state.fullDiskAccessGranted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(Theme.color(for: state.fullDiskAccessGranted ? .ok : .critical))
                }
            }

            HStack {
                Picker(l.t("settings.language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text(l.t("language.\($0.rawValue)")).tag($0) }
                }
                .frame(width: 260)
                Spacer()
                Button(l.t("onboarding.continue")) { state.finishOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 600)
    }

    private func feature(_ symbol: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(Theme.accent)
            Text(l.t(key)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
