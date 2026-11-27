import Foundation
import Observation

/// The two on-device kid profiles. Names are exact display strings.
enum KidProfile: String, CaseIterable, Identifiable, Sendable {
    case child1 = "Child 1"
    case child2 = "Child 2"

    var id: String { rawValue }
    var displayName: String { rawValue }
    /// Filesystem key for per-profile overlay files (`hidden-child1.json`).
    var fileKey: String {
        switch self {
        case .child1: return "child1"
        case .child2: return "child2"
        }
    }
}

/// Active kid profile. Missing UserDefaults key is Child 1.
@Observable
final class ProfileStore {
    static let defaultsKey = "bestwishes.activeProfile"

    private(set) var active: KidProfile
    private let defaults: UserDefaults

    var activeName: String { active.rawValue }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.defaultsKey),
           let profile = KidProfile(rawValue: stored) {
            self.active = profile
        } else {
            self.active = .child1
        }
    }

    /// Same path the caregiver switcher uses. Reloads per-profile overlays
    /// (hide, order, labels, recents, grid, folder path, strip) without refetching the server board.
    func switchTo(_ profile: KidProfile, overlay store: CardStore, grid: GridLayout) {
        guard profile != active else { return }
        active = profile
        defaults.set(profile.rawValue, forKey: Self.defaultsKey)
        store.switchToProfile(profile)
        grid.applyProfile(profile)
    }

    /// Launch-arg hook `-Profile 'Child 1'|'Child 2'` calls the same switcher as the UI.
    func applyLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments,
        overlay store: CardStore,
        grid: GridLayout
    ) {
        guard let idx = arguments.firstIndex(of: "-Profile"),
              arguments.indices.contains(idx + 1),
              let profile = KidProfile(rawValue: arguments[idx + 1]) else {
            return
        }
        if profile == active { return }
        switchTo(profile, overlay: store, grid: grid)
    }
}
