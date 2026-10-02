import SwiftUI

@main
struct CleanMyMacApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var localizer: Localizer
    @StateObject private var state: AppState

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _localizer = StateObject(wrappedValue: Localizer(language: settings.language))
        _state = StateObject(wrappedValue: AppState(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(settings)
                .environmentObject(localizer)
                .frame(minWidth: 1040, minHeight: 680)
                .onReceive(settings.$language) { localizer.apply($0) }
        }
        .commands {
            AppCommands(state: state, localizer: localizer)
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(settings)
                .environmentObject(localizer)
                .frame(width: 620, height: 640)
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var state: AppState
    @ObservedObject var localizer: Localizer

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(localizer.t("action.scanAll")) { state.scanAll() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.isScanning)
            Button(localizer.t("action.cancelScan")) { state.cancelScan() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!state.isScanning)
        }
        CommandGroup(replacing: .help) {
            Button(localizer.t("sidebar.help")) { state.selection = .help }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
