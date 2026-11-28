import SwiftUI

@main
struct BestWishesApp: App {
    @State private var profiles: ProfileStore
    @State private var store: CardStore
    @State private var sync: SyncCoordinator

    init() {
        let profiles = ProfileStore()
        let store = CardStore(
            api: APIClient.fromLaunchArguments(),
            profile: profiles.active
        )
        _profiles = State(initialValue: profiles)
        _store = State(initialValue: store)
        _sync = State(initialValue: SyncCoordinator(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, profiles: profiles, sync: sync)
                .statusBarHidden(true)
        }
    }
}
