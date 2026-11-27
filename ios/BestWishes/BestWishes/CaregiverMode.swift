import Foundation
import Observation

/// Kid vs caregiver chrome. Missing UserDefaults key is kid mode.
@Observable
final class CaregiverMode {
    static let defaultsKey = "bestwishes.caregiverUnlocked"
    /// Long-press duration on the title that unlocks caregiver tools.
    static let unlockHoldDuration: TimeInterval = 1.5

    private(set) var isCaregiver: Bool
    /// Explicit Edit state. Only meaningful while caregiver is unlocked.
    private(set) var isEditing: Bool = false
    private let defaults: UserDefaults

    /// Add field, Add button, and other edit chrome. Hidden in kid mode.
    var showsAddChrome: Bool { isCaregiver }

    /// Edit / Done / Hidden list entry. Hidden in kid mode.
    var showsEditButton: Bool { isCaregiver }

    /// Per-card Hide controls. Requires caregiver plus explicit Edit.
    var showsEditChrome: Bool { isCaregiver && isEditing }

    /// Hidden-card list. Caregiver only; kid mode never shows it.
    var showsHiddenList: Bool { isCaregiver }

    /// Child 1 / Child 2 switcher. Caregiver only; kid mode never shows it.
    var showsProfileSwitcher: Bool { isCaregiver }

    /// Board search field. Caregiver only; kid mode never shows it.
    var showsSearchChrome: Bool { isCaregiver }

    /// Voice-add mic. Caregiver only; kid mode never shows it and never listens.
    var showsVoiceChrome: Bool { isCaregiver }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isCaregiver = defaults.bool(forKey: Self.defaultsKey)
    }

    /// Unlock caregiver tools without entering Edit. Used by the `-CaregiverMode` launch arg.
    func unlock() {
        isCaregiver = true
        defaults.set(true, forKey: Self.defaultsKey)
    }

    /// Main P2G-style path: unlock caregiver tools and go straight into Edit.
    /// Used by the toolbar hold-to-edit control and the title long-press.
    func unlockAndEdit() {
        unlock()
        enterEdit()
    }

    /// Same path the Lock control uses. Kid mode always leaves Edit.
    func lock() {
        isCaregiver = false
        isEditing = false
        defaults.set(false, forKey: Self.defaultsKey)
    }

    /// Same path the Edit control uses.
    func enterEdit() {
        guard isCaregiver else { return }
        isEditing = true
    }

    /// Same path the Done control uses.
    func exitEdit() {
        isEditing = false
    }

    /// Launch-arg hooks call the same unlock/lock/edit as the UI.
    func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("-CaregiverMode") {
            unlock()
        }
        if arguments.contains("-EditMode") {
            unlock()
            enterEdit()
        }
        if arguments.contains("-KidMode") {
            lock()
        }
    }
}
