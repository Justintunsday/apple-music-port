import SwiftUI

@main
struct MusicLandscapePrototypeApp: App {
    var body: some Scene {
        WindowGroup {
            PlayerScreen()
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
        }
    }
}
