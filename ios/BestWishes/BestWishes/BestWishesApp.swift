import SwiftUI

@main
struct BestWishesApp: App {
    @State private var profiles: ProfileStore
    @State private var store: CardStore

    init() {
        let profiles = ProfileStore()
        _profiles = State(initialValue: profiles)
        _store = State(initialValue: CardStore(
            api: APIClient.fromLaunchArguments(),
            profile: profiles.active
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, profiles: profiles)
                .statusBarHidden(true)
        }
    }
}
