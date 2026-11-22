import SwiftUI

@main
struct AgentsAnywhereApp: App {
    @State private var appState = AppState()
    /// The full session tree is expensive to build. Committing a light first
    /// frame before it keeps the scene-update watchdog satisfied, which matters
    /// on older systems where the same tree is laid out more slowly.
    @State private var showsWorkbench = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearanceValue = AppAppearance.system.rawValue

    init() {
        AppFontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showsWorkbench {
                    RootView()
                        .environment(appState)
                        .background {
                            #if targetEnvironment(macCatalyst)
                            MacCatalystWindowTitle(appState: appState)
                            #endif
                        }
                } else {
                    LaunchPlaceholder()
                        .task {
                            // Runs after the placeholder's first frame is
                            // committed, so the watchdog clock stops before the
                            // workbench tree is laid out.
                            await Task.yield()
                            try? await Task.sleep(for: .milliseconds(16))
                            showsWorkbench = true
                        }
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { appState.setAppInBackground(true) }
                else if phase == .active { appState.setAppInBackground(false) }
            }
        }
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceValue) ?? .system
    }
}

private struct LaunchPlaceholder: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            Text(String(localized: "正在载入…"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
