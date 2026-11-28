import Foundation
import Observation
import SwiftUI

/// Fixed AAC grid size. Buttons keep their row and column so motor memory stays stable.
@Observable
final class GridLayout {
    /// Legacy un-namespaced key. Child 1 inherits it when its namespaced key is missing.
    static let defaultsKey = "bestwishes.gridColumns"
    static let rowsDefaultsKey = "bestwishes.gridRows"
    /// Historical 2/3/4 presets. The stepper can go wider (see `allowedColumnRange`).
    static let allowedCounts = [2, 3, 4]
    static let defaultCount = 3
    static let columnSpacing: CGFloat = 22
    static let allowedColumnRange = 2...8
    static let allowedRowRange = 2...8
    static let defaultPhoneColumns = 3
    static let defaultPhoneRows = 4
    static let defaultPadColumns = 4
    static let defaultPadRows = 6
    static let defaultRows = defaultPhoneRows

    private(set) var columnCount: Int
    private(set) var rowCount: Int
    private var profile: KidProfile
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, profile: KidProfile = .child1) {
        self.defaults = defaults
        self.profile = profile
        self.columnCount = Self.loadColumnCount(defaults: defaults, profile: profile)
        self.rowCount = Self.loadRowCount(defaults: defaults, profile: profile)
    }

    static func columnsKey(for profile: KidProfile) -> String {
        "bestwishes.gridColumns.\(profile.rawValue)"
    }

    static func rowsKey(for profile: KidProfile) -> String {
        "bestwishes.gridRows.\(profile.rawValue)"
    }

    var cellCount: Int { rowCount * columnCount }

    /// Same path the caregiver 2 / 3 / 4 control uses.
    func setColumnCount(_ count: Int) {
        let next = Self.clampedColumns(count)
        columnCount = next
        defaults.set(next, forKey: Self.columnsKey(for: profile))
    }

    func setRowCount(_ count: Int) {
        let next = Self.clampedRows(count)
        rowCount = next
        defaults.set(next, forKey: Self.rowsKey(for: profile))
    }

    /// Apply the usual AAC default (4×6 on iPad, 3×4 on iPhone) only when this
    /// profile has no saved size yet. Existing 2/3/4 choices are left alone.
    func applySizeClassDefaultsIfNeeded(isCompact: Bool) {
        if !Self.hasSavedColumns(defaults: defaults, profile: profile) {
            setColumnCount(isCompact ? Self.defaultPhoneColumns : Self.defaultPadColumns)
        }
        if !Self.hasSavedRows(defaults: defaults, profile: profile) {
            setRowCount(isCompact ? Self.defaultPhoneRows : Self.defaultPadRows)
        }
    }

    /// Back to the device's default size (after removing an imported board, which sets its own).
    func resetToSizeClassDefaults(isCompact: Bool) {
        setColumnCount(isCompact ? Self.defaultPhoneColumns : Self.defaultPadColumns)
        setRowCount(isCompact ? Self.defaultPhoneRows : Self.defaultPadRows)
    }

    /// Same path the caregiver profile switcher uses.
    func applyProfile(_ profile: KidProfile) {
        self.profile = profile
        columnCount = Self.loadColumnCount(defaults: defaults, profile: profile)
        rowCount = Self.loadRowCount(defaults: defaults, profile: profile)
    }

    private static func hasSavedColumns(defaults: UserDefaults, profile: KidProfile) -> Bool {
        if defaults.object(forKey: columnsKey(for: profile)) != nil { return true }
        return profile == .child1 && defaults.object(forKey: defaultsKey) != nil
    }

    private static func hasSavedRows(defaults: UserDefaults, profile: KidProfile) -> Bool {
        defaults.object(forKey: rowsKey(for: profile)) != nil
            || (profile == .child1 && defaults.object(forKey: rowsDefaultsKey) != nil)
    }

    private static func loadColumnCount(defaults: UserDefaults, profile: KidProfile) -> Int {
        let namespaced = columnsKey(for: profile)
        if defaults.object(forKey: namespaced) != nil {
            return clampedColumns(defaults.integer(forKey: namespaced))
        }
        if profile == .child1, defaults.object(forKey: defaultsKey) != nil {
            return clampedColumns(defaults.integer(forKey: defaultsKey))
        }
        return defaultCount
    }

    private static func loadRowCount(defaults: UserDefaults, profile: KidProfile) -> Int {
        let namespaced = rowsKey(for: profile)
        if defaults.object(forKey: namespaced) != nil {
            return clampedRows(defaults.integer(forKey: namespaced))
        }
        if profile == .child1, defaults.object(forKey: rowsDefaultsKey) != nil {
            return clampedRows(defaults.integer(forKey: rowsDefaultsKey))
        }
        return defaultRows
    }

    /// Fixed flexible columns for `LazyVGrid`.
    var gridItems: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Self.columnSpacing),
            count: columnCount
        )
    }

    /// Launch-arg hooks `-GridColumns N` and `-GridRows N` call the same setters as the UI.
    func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        if let idx = arguments.firstIndex(of: "-GridColumns"),
           arguments.indices.contains(idx + 1),
           let value = Int(arguments[idx + 1]) {
            setColumnCount(value)
        }
        if let idx = arguments.firstIndex(of: "-GridRows"),
           arguments.indices.contains(idx + 1),
           let value = Int(arguments[idx + 1]) {
            setRowCount(value)
        }
    }

    /// Values outside 2...8 collapse to the default column density (3).
    static func clamped(_ raw: Int) -> Int {
        clampedColumns(raw)
    }

    static func clampedColumns(_ raw: Int) -> Int {
        allowedColumnRange.contains(raw) ? raw : defaultCount
    }

    static func clampedRows(_ raw: Int) -> Int {
        allowedRowRange.contains(raw) ? raw : defaultRows
    }
}
