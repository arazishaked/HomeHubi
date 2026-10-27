import SwiftUI

@main
struct HomeHubApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear { store.startPolling() }
                .onChange(of: phase) { p in
                    if p == .active { store.startPolling() } else { store.stopPolling() }
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        HomeView()
            .environment(\.layoutDirection, .rightToLeft)
    }
}
