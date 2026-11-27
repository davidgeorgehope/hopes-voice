import Foundation
import Observation
import SwiftUI

/// Board grid density. Only 2, 3, or 4 columns. Missing UserDefaults key is 3.
@Observable
final class GridLayout {
    /// Legacy un-namespaced key. Child 1 inherits it when its namespaced key is missing.
    static let defaultsKey = "bestwishes.gridColumns"
    static let allowedCounts = [2, 3, 4]
    static let defaultCount = 3
    static let columnSpacing: CGFloat = 22

    private(set) var columnCount: Int
    private var profile: KidProfile
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, profile: KidProfile = .child1) {
        self.defaults = defaults
        self.profile = profile
        self.columnCount = Self.loadColumnCount(defaults: defaults, profile: profile)
    }

    static func columnsKey(for profile: KidProfile) -> String {
        "bestwishes.gridColumns.\(profile.rawValue)"
    }

    /// Same path the caregiver 2 / 3 / 4 control uses.
    func setColumnCount(_ count: Int) {
        let next = Self.clamped(count)
        columnCount = next
        defaults.set(next, forKey: Self.columnsKey(for: profile))
    }

    /// Same path the caregiver profile switcher uses.
    func applyProfile(_ profile: KidProfile) {
        self.profile = profile
        columnCount = Self.loadColumnCount(defaults: defaults, profile: profile)
    }

    private static func loadColumnCount(defaults: UserDefaults, profile: KidProfile) -> Int {
        let namespaced = columnsKey(for: profile)
        if defaults.object(forKey: namespaced) != nil {
            return clamped(defaults.integer(forKey: namespaced))
        }
        if profile == .child1, defaults.object(forKey: defaultsKey) != nil {
            return clamped(defaults.integer(forKey: defaultsKey))
        }
        return defaultCount
    }

    /// Fixed flexible columns for `LazyVGrid`. Always 2, 3, or 4 items — never adaptive.
    var gridItems: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Self.columnSpacing),
            count: columnCount
        )
    }

    /// Launch-arg hook `-GridColumns 2|3|4` calls the same setter as the UI.
    func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let idx = arguments.firstIndex(of: "-GridColumns"),
              arguments.indices.contains(idx + 1),
              let value = Int(arguments[idx + 1]) else {
            return
        }
        setColumnCount(value)
    }

    /// Values outside 2/3/4 collapse to the default density (3). Never a fifth count.
    static func clamped(_ raw: Int) -> Int {
        allowedCounts.contains(raw) ? raw : defaultCount
    }
}
