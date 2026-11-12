import SwiftUI
import HostDeps

@main
struct AetherPlayerApp: App {
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()

                // The render surface stays mounted for the app's lifetime, so the engine is
                // always bound to a view before the first load.
                AetherPlayerSurface(engine: model.engine)
                    .ignoresSafeArea()

                if model.request != nil {
                    PlayerScreen(model: model)
                } else {
                    SettingsScreen(model: model)
                        .background(Color.black.ignoresSafeArea())
                }
            }
            // Lampa opens SenPlayer://x-callback-url/play?url=...  (see project.yml)
            .onOpenURL { model.handleIncoming($0) }
        }
    }
}
