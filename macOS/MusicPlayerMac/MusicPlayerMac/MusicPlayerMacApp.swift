import SwiftUI

@main
struct MusicPlayerMacApp: App {
    @State private var player = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
        }
        .defaultSize(width: 860, height: 580)
        .windowResizability(.contentMinSize)
    }
}
