import SwiftUI

@main
struct MusicPlayerMacApp: App {
    @State private var player = AudioPlayerManager()
    @State private var tracksViewModel = TracksViewModel()
    @State private var syncManager = MultipeerSyncManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .environment(tracksViewModel)
                .environment(syncManager)
                .onAppear {
                    syncManager.tracksViewModel = tracksViewModel
                }
        }
        .defaultSize(width: 860, height: 580)
        .windowResizability(.contentMinSize)
    }
}
