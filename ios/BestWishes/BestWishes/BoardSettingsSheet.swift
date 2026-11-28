import SwiftUI
import UniformTypeIdentifiers

/// Caregiver settings for look, voice, message bar, and board import.
struct BoardSettingsSheet: View {
    @Bindable var store: CardStore
    var grid: GridLayout
    var sync: SyncCoordinator?
    var profiles: ProfileStore?
    var onDismiss: () -> Void
    var onImport: () -> Void

    @State private var draft: ProfileSettings
    @State private var profileName: String
    @State private var confirmClear = false

    init(
        store: CardStore,
        grid: GridLayout,
        sync: SyncCoordinator? = nil,
        profiles: ProfileStore? = nil,
        onDismiss: @escaping () -> Void,
        onImport: @escaping () -> Void
    ) {
        self.store = store
        self.grid = grid
        self.sync = sync
        self.profiles = profiles
        self.onDismiss = onDismiss
        self.onImport = onImport
        _draft = State(initialValue: Self.initialDraft(store: store, grid: grid))
        _profileName = State(initialValue: Self.initialProfileName(store: store, profiles: profiles))
    }

    /// Settings the sheet shows. A default board edits the live grid. An import edits the viewport.
    static func initialDraft(store: CardStore, grid: GridLayout) -> ProfileSettings {
        var draft = store.settings
        if !store.hasImportedBoard {
            draft.viewportRows = grid.rowCount
            draft.viewportCols = grid.columnCount
        }
        return draft
    }

    /// Blank when the active profile still uses its identity string, so the placeholder shows that string.
    static func initialProfileName(store: CardStore, profiles: ProfileStore?) -> String {
        guard let profiles else { return "" }
        let shown = profiles.displayName(for: store.activeProfile)
        return shown == store.activeProfile.rawValue ? "" : shown
    }

    static func visibleRowRange(hasImportedBoard: Bool) -> ClosedRange<Int> {
        hasImportedBoard ? 2...12 : GridLayout.allowedRowRange
    }

    static func apply(
        _ draft: ProfileSettings,
        store: CardStore,
        grid: GridLayout,
        profiles: ProfileStore?,
        displayName: String
    ) {
        store.updateSettings(draft)
        if !store.hasImportedBoard {
            grid.setColumnCount(draft.viewportCols)
            grid.setRowCount(draft.viewportRows)
        }
        profiles?.setDisplayName(displayName, for: store.activeProfile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField(store.activeProfile.rawValue, text: $profileName)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("settingsProfileName")
                    }
                    Text("Shown on the profile switcher. Stays on this device. Leave blank for \(store.activeProfile.rawValue).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Board") {
                    ColorHexField(title: "Background", hex: $draft.backgroundHex)
                    Picker("Color mode", selection: $draft.colorMode) {
                        Text("As written").tag("custom")
                        Text("Border only").tag("border")
                        Text("Fill").tag("fill")
                    }
                    Stepper(
                        "Visible rows: \(draft.viewportRows)",
                        value: $draft.viewportRows,
                        in: Self.visibleRowRange(hasImportedBoard: store.hasImportedBoard)
                    )
                    Stepper(
                        "Visible columns: \(draft.viewportCols)",
                        value: $draft.viewportCols,
                        in: GridLayout.allowedColumnRange
                    )
                    Toggle("Show core words", isOn: $draft.showCoreRow)
                    Toggle("Show recents", isOn: $draft.showRecents)
                }
                Section("Message bar") {
                    Picker("Style", selection: $draft.messageBar.style) {
                        Text("Standard").tag("standard")
                        Text("Solid blue").tag("compactBlue")
                    }
                    Toggle("Speak on tap", isOn: $draft.messageBar.speakOnTap)
                    Toggle("Tap bar to speak", isOn: $draft.messageBar.speakOnBarTap)
                    Toggle("Clear after speak", isOn: $draft.messageBar.clearAfterSpeak)
                    Toggle("Picture under the label", isOn: $draft.messageBar.textAboveImage)
                    Toggle("Delete-last button", isOn: $draft.messageBar.showDeleteLast)
                }
                Section("Folders") {
                    Toggle("Return home after a selection", isOn: $draft.returnHomeAfterSelection)
                    Toggle("Folder buttons add their word", isOn: addFolderBinding)
                }
                Section("Voice") {
                    Picker("Engine", selection: $draft.voice.engine) {
                        Text("This device").tag("system")
                        Text("Server (Eve)").tag("server")
                    }
                    Text("Closest stand-in for a young English voice: Samantha on this device, or Eve on the server, at 180 words per minute (rate 1.0).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Stepper(
                        "Rate \(draft.voice.rate, specifier: "%.2f")×",
                        value: $draft.voice.rate,
                        in: 0.5...1.5,
                        step: 0.05
                    )
                    Stepper(
                        "Pitch \(draft.voice.pitch, specifier: "%.2f")×",
                        value: $draft.voice.pitch,
                        in: 0.7...1.3,
                        step: 0.05
                    )
                }
                if let sync {
                    SyncSettingsSection(
                        sync: sync,
                        profileName: profiles?.displayName(for: store.activeProfile) ?? store.activeProfile.displayName
                    )
                }
                Section("Import") {
                    Button("Import a board file…", action: onImport)
                        .accessibilityIdentifier("importBoard")
                    if store.hasImportedBoard {
                        Button("Remove imported board", role: .destructive) {
                            confirmClear = true
                        }
                        .accessibilityIdentifier("clearImportedBoard")
                    }
                    Text("The file must be bestwishes.board/v1. Family photos stay on this device. Import is all-or-nothing: any error leaves the current board unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .accessibilityIdentifier("settingsCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Self.apply(
                            draft,
                            store: store,
                            grid: grid,
                            profiles: profiles,
                            displayName: profileName
                        )
                        onDismiss()
                    }
                    .accessibilityIdentifier("settingsSave")
                }
            }
            .alert("Remove the imported board?", isPresented: $confirmClear) {
                Button("Remove", role: .destructive) {
                    store.clearImportedBoard()
                    confirmClear = false
                    onDismiss()
                }
                Button("Cancel", role: .cancel) { confirmClear = false }
            } message: {
                Text("The default board comes back. Pictures copied onto this device stay in the cache until you delete the app.")
            }
        }
    }

    private var addFolderBinding: Binding<Bool> {
        Binding(
            get: { draft.addFolderWordToBar ?? false },
            set: { draft.addFolderWordToBar = $0 }
        )
    }
}

private struct ColorHexField: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("000000", text: $hex)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .accessibilityIdentifier("settingsBackground")
        }
    }
}
