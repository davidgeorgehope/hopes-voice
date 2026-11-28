import Foundation
import Observation

/// The two on-device kid profiles. `rawValue` is the stable identity
/// ("Child 1" / "Child 2") for launch arguments, accessibility identifiers,
/// and saved keys. A caregiver can show a different label.
enum KidProfile: String, CaseIterable, Identifiable, Sendable {
    case child1 = "Child 1"
    case child2 = "Child 2"

    var id: String { rawValue }
    /// Identity string. The caregiver-facing label lives on `ProfileStore`.
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
    /// Longest caregiver label, in characters, after trimming.
    static let maxDisplayNameLength = 24

    private(set) var active: KidProfile
    /// Custom labels keyed by `KidProfile.fileKey`. A missing entry uses `rawValue`.
    private(set) var displayNames: [String: String]
    private let defaults: UserDefaults

    var activeName: String { displayName(for: active) }

    static func nameKey(for profile: KidProfile) -> String {
        "bestwishes.profileName.\(profile.fileKey)"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.defaultsKey),
           let profile = KidProfile(rawValue: stored) {
            self.active = profile
        } else {
            self.active = .child1
        }
        self.displayNames = Self.loadDisplayNames(defaults: defaults)
    }

    func displayName(for profile: KidProfile) -> String {
        displayNames[profile.fileKey] ?? profile.rawValue
    }

    /// Trim, drop a blank, and cap the length. A blank removes the saved label.
    func setDisplayName(_ name: String, for profile: KidProfile) {
        let key = Self.nameKey(for: profile)
        if let normalized = Self.normalizedDisplayName(name) {
            displayNames[profile.fileKey] = normalized
            defaults.set(normalized, forKey: key)
        } else {
            displayNames.removeValue(forKey: profile.fileKey)
            defaults.removeObject(forKey: key)
        }
    }

    static func normalizedDisplayName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxDisplayNameLength))
    }

    private static func loadDisplayNames(defaults: UserDefaults) -> [String: String] {
        var names: [String: String] = [:]
        for profile in KidProfile.allCases {
            guard let stored = defaults.string(forKey: nameKey(for: profile)),
                  let normalized = normalizedDisplayName(stored) else { continue }
            names[profile.fileKey] = normalized
        }
        return names
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
