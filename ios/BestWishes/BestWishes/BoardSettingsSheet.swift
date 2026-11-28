import SwiftUI
import UniformTypeIdentifiers

/// Caregiver settings for look, voice, message bar, and board import.
struct BoardSettingsSheet: View {
    @Bindable var store: CardStore
    var grid: GridLayout
    var sync: SyncCoordinator?
    var onDismiss: () -> Void
    var onImport: () -> Void

    @State private var draft: ProfileSettings
    @State private var confirmClear = false

    init(store: CardStore, grid: GridLayout, sync: SyncCoordinator? = nil, onDismiss: @escaping () -> Void, onImport: @escaping () -> Void) {
        self.store = store
        self.grid = grid
        self.sync = sync
        self.onDismiss = onDismiss
        self.onImport = onImport
        _draft = State(initialValue: store.settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Board") {
                    ColorHexField(title: "Background", hex: $draft.backgroundHex)
                    Picker("Color mode", selection: $draft.colorMode) {
                        Text("As written").tag("custom")
                        Text("Border only").tag("border")
                        Text("Fill").tag("fill")
                    }
                    Stepper("Visible rows: \(draft.viewportRows)", value: $draft.viewportRows, in: 2...12)
                    Stepper("Visible columns: \(draft.viewportCols)", value: $draft.viewportCols, in: 2...8)
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
                    SyncSettingsSection(sync: sync, profileName: store.activeProfile.displayName)
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
                        store.updateSettings(draft)
                        grid.setColumnCount(draft.viewportCols)
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
