import DiskKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var l: Localizer

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            DetailRouter()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(l.t("app.name"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if state.isScanning {
                    Button(role: .cancel) { state.cancelScan() } label: {
                        Label(l.t("action.cancelScan"), systemImage: "stop.circle")
                    }
                } else {
                    Button { state.scanAll() } label: {
                        Label(l.t("action.scanAll"), systemImage: "magnifyingglass")
                    }
                    .help(l.t("action.scanAll.help"))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if state.isScanning {
                ScanProgressCard()
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.isScanning)
        .task {
            // `-scanOnLaunch YES` (used by the CI smoke test) starts a scan right away.
            if let page = UserDefaults.standard.string(forKey: "openPage") {
                switch page {
                case "duplicates": state.selection = .duplicates
                case "docker": state.selection = .docker
                case "help": state.selection = .help
                default: break
                }
            }
            if UserDefaults.standard.bool(forKey: "scanOnLaunch") { state.scanAll() }
        }
        .sheet(item: $state.externalPrompt) { prompt in
            ExternalDriveSheet(prompt: prompt)
        }
        .sheet(item: $state.pendingTrash) { request in
            TrashConfirmSheet(request: request)
        }
        .sheet(item: $state.pendingDockerRemoval) { request in
            DockerRemovalSheet(request: request)
        }
        .sheet(isPresented: $state.showOnboarding) {
            OnboardingView()
        }
        .alert(
            l.t("mount.title"),
            isPresented: Binding(get: { state.mountedVolumePrompt != nil }, set: { if !$0 { state.mountedVolumePrompt = nil } }),
            presenting: state.mountedVolumePrompt
        ) { volume in
            Button(l.t("mount.scanNow")) { state.scan(volume) }
            Button(l.t("action.later"), role: .cancel) {}
        } message: { volume in
            Text(l.t("mount.message", volume.name, l.bytes(volume.totalBytes)))
        }
        .alert(
            l.t("app.name"),
            isPresented: Binding(get: { state.message != nil }, set: { if !$0 { state.message = nil } }),
            presenting: state.message
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { key in
            Text(l.t(key))
        }
    }
}

struct DetailRouter: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let item = state.selection ?? .summary
        // Every page is wrapped so it can never overflow the window (see PageContainer).
        PageContainer(minWidth: Self.minimumWidth(for: item), minHeight: 460) {
            page(for: item)
        }
    }

    @ViewBuilder
    private func page(for item: SidebarItem) -> some View {
        switch item {
        case .summary: SummaryView()
        case let .volume(id): DriveDetailView(volumeID: id).id(id)
        case .duplicates: DuplicatesView()
        case .docker: DockerView()
        case .deletionLog: DeletionLogView()
        case .help: HelpView()
        case .settings: ScrollView { SettingsView().padding(24) }
        }
    }

    /// Smallest width at which a page still lays out cleanly; below it the page scrolls sideways.
    static func minimumWidth(for item: SidebarItem) -> CGFloat {
        switch item {
        case .volume, .duplicates: return 700
        case .help: return 640
        default: return 560
        }
    }
}
