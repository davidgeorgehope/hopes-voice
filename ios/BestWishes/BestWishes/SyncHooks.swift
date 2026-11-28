import SwiftUI

/// Starts sync with the view, tells it when the caregiver has something open, and nudges it on foreground.
/// A separate view so the main board's modifier chain stays small.
struct SyncHooks: View {
    var sync: SyncCoordinator?
    var busy: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .onAppear {
                sync?.isBusy = busy
                sync?.start()
            }
            .onChange(of: busy) { _, value in sync?.isBusy = value }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { sync?.sceneBecameActive() }
            }
    }
}
