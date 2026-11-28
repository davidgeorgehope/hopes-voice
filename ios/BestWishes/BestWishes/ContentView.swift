import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: CardStore
    @State var mode: CaregiverMode
    @State var profiles: ProfileStore
    @State var grid: GridLayout
    var sync: SyncCoordinator?
    @State private var draft = ""
    @State private var pendingHide: Card?
    @State private var pendingDelete: Card?
    @State private var pendingDeleteFolder: BoardFolder?
    @State private var pendingRenameSlug: String?
    @State private var pendingRenameFallback = ""
    @State private var renameDraft = ""
    @State private var draggingItemID: String?
    @State private var showingHidden = false
    @State private var editorDraft: ButtonEditorDraft?
    @State private var editorBusy = false
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var boardPage = 0
    @FocusState private var fieldFocused: Bool
    @FocusState private var searchFieldFocused: Bool
    @State private var voice = VoiceRecognizer()
    @State private var pendingVoiceWord: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewWidth: CGFloat = Self.initialViewWidth

    private static var initialViewWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var chrome: BoardChrome {
        BoardChrome.make(
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: viewWidth,
            columnCount: grid.columnCount
        )
    }

    init(
        store: CardStore,
        mode: CaregiverMode = CaregiverMode(),
        profiles: ProfileStore = ProfileStore(),
        grid: GridLayout? = nil,
        sync: SyncCoordinator? = nil
    ) {
        self.store = store
        self.sync = sync
        _mode = State(initialValue: mode)
        _profiles = State(initialValue: profiles)
        _grid = State(initialValue: grid ?? GridLayout(profile: profiles.active))
    }

    /// Measure the space the window offers, never the content's own size. Measuring the
    /// content let one too-wide row (for example the caregiver profile switcher on a phone)
    /// widen every fixed-width row, which then measured even wider and stuck off-screen.
    var body: some View {
        GeometryReader { geo in
            rootStack
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .onAppear { updateViewWidth(geo.size.width) }
                .onChange(of: geo.size.width) { _, width in updateViewWidth(width) }
        }
    }

    private func updateViewWidth(_ width: CGFloat) {
        guard width > 0, abs(width - viewWidth) > 0.5 else { return }
        viewWidth = width
    }

    private var rootStack: some View {
        VStack(spacing: 0) {
            topBar
            if let banner = store.banner {
                Text(banner)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Theme.slate.opacity(0.92))
            }
            if let error = store.errorMessage ?? voice.errorMessage {
                Text(error)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Theme.coral)
            }
            if voice.isListening {
                Text(voice.partialTranscript.isEmpty ? "Listening…" : voice.partialTranscript)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Theme.coral.opacity(0.92))
                    .accessibilityIdentifier("voiceListeningBanner")
            }
            sentenceStrip
            if !store.coreCards.isEmpty {
                coreRow
            }
            if !store.recentCards.isEmpty {
                recentsRow
            }
            if mode.showsHiddenList && showingHidden {
                hiddenList
            } else {
                board
            }
        }
        .background((Color(hex: store.settings.backgroundHex) ?? Theme.board).ignoresSafeArea())
        .sheet(isPresented: $showingSettings) {
            BoardSettingsSheet(
                store: store,
                grid: grid,
                sync: sync,
                onDismiss: { showingSettings = false },
                onImport: {
                    showingSettings = false
                    showingImporter = true
                }
            )
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .folder],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert("Could not import that board", isPresented: importErrorPresented) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .environment(\.boardChrome, chrome)
        .task { await store.bootstrap() }
        .onAppear { consumeLaunchArguments() }
        .background(SyncHooks(sync: sync, busy: mode.isEditing || showingSettings || editorDraft != nil))
        .onChange(of: voice.finishedTranscript) { _, transcript in
            consumeVoiceTranscript(transcript)
        }
        .sheet(isPresented: voiceConfirmPresented) {
            VoiceConfirmSheet(
                word: voiceConfirmWord,
                onAdd: {
                    let word = pendingVoiceWord
                    pendingVoiceWord = nil
                    if let word {
                        Task { await VoiceAdd.confirm(word, into: store) }
                    }
                },
                onCancel: { pendingVoiceWord = nil }
            )
            .presentationDetents([.fraction(0.52), .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Hide this card?", isPresented: hideAlertPresented, presenting: pendingHide) { card in
            Button("Hide", role: .destructive) {
                store.hideAfterConfirm(card.slug)
                pendingHide = nil
            }
            Button("Cancel", role: .cancel) {
                pendingHide = nil
            }
        } message: { card in
            Text("“\(store.displayLabel(for: card))” will leave this board until you Unhide it. It is not deleted on the server.")
        }
        .alert("Delete this card forever?", isPresented: deleteAlertPresented, presenting: pendingDelete) { card in
            Button("Delete", role: .destructive) {
                let slug = card.slug
                pendingDelete = nil
                Task { await store.deleteCardAfterConfirm(slug) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { card in
            Text("“\(store.displayLabel(for: card))” will be removed from the server. This cannot be undone. Hide keeps it for Unhide instead.")
        }
        .alert("Delete this folder?", isPresented: deleteFolderAlertPresented, presenting: pendingDeleteFolder) { folder in
            Button("Delete", role: .destructive) {
                let slug = folder.id
                pendingDeleteFolder = nil
                Task { await store.deleteFolderAfterConfirm(slug) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteFolder = nil
            }
        } message: { folder in
            Text("“\(store.displayLabel(for: folder))” will be removed. Words inside move to the home board.")
        }
        .alert("Rename this card?", isPresented: renameAlertPresented) {
            TextField("Display name", text: $renameDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") {
                if let slug = pendingRenameSlug {
                    store.setDisplayLabel(renameDraft, for: slug)
                }
                pendingRenameSlug = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRenameSlug = nil
            }
        } message: {
            Text("Only this iPad sees “\(renameDraft.isEmpty ? pendingRenameFallback : renameDraft)”. Speak still uses the original voice.")
        }
        .sheet(isPresented: editorPresented) {
            if editorDraft != nil {
                ButtonEditorSheet(
                    draft: editorDraftBinding,
                    availableFolders: store.grouping.folders.map { (id: $0.id, name: store.displayLabel(for: $0)) },
                    isBusy: editorBusy || store.isAdding,
                    errorMessage: store.errorMessage,
                    onSave: { Task { await saveEditor() } },
                    onCancel: { editorDraft = nil },
                    onHide: hideEditorItem,
                    onDelete: deleteEditorItem
                )
            }
        }
        .onChange(of: mode.isEditing) { _, editing in
            if editing { showingHidden = false }
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            grid.applySizeClassDefaultsIfNeeded(isCompact: horizontalSizeClass == .compact)
        }
    }

    private var editorPresented: Binding<Bool> {
        Binding(
            get: { editorDraft != nil },
            set: { if !$0 { editorDraft = nil } }
        )
    }

    private var editorDraftBinding: Binding<ButtonEditorDraft> {
        Binding(
            get: { editorDraft ?? .blank(at: GridCoord(row: 0, col: 0)) },
            set: { editorDraft = $0 }
        )
    }

    private var hideAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingHide != nil },
            set: { if !$0 { pendingHide = nil } }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var deleteFolderAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteFolder != nil },
            set: { if !$0 { pendingDeleteFolder = nil } }
        )
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingRenameSlug != nil },
            set: { if !$0 { pendingRenameSlug = nil } }
        )
    }

    private var voiceConfirmPresented: Binding<Bool> {
        Binding(
            get: { pendingVoiceWord != nil },
            set: { if !$0 { pendingVoiceWord = nil } }
        )
    }

    /// Editable confirm word. Parse only seeds this; Add reads the current string.
    private var voiceConfirmWord: Binding<String> {
        Binding(
            get: { pendingVoiceWord ?? "" },
            set: { newValue in
                if pendingVoiceWord != nil {
                    pendingVoiceWord = newValue
                }
            }
        )
    }

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: chrome.isCompact ? 8 : 16) {
                folderNav
                title
                Spacer(minLength: 4)
                if mode.showsAddChrome {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: chrome.isCompact ? 16 : 18, weight: .bold))
                            .foregroundStyle(Theme.cream)
                            .frame(minWidth: chrome.isCompact ? 44 : 52, minHeight: chrome.isCompact ? 44 : 52)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("boardSettings")
                }
                EditLockButton(mode: mode, isCompact: chrome.isCompact, onLock: lockEditing)
            }
            if mode.showsProfileSwitcher {
                if chrome.isCompact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            profileSwitcher
                            caregiverTools
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 12) {
                        profileSwitcher
                        Spacer(minLength: 8)
                        caregiverTools
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if mode.showsAddChrome {
                addChrome
            }
            if mode.showsSearchChrome {
                searchChrome
            }
        }
        .padding(.horizontal, chrome.isCompact ? 12 : 24)
        .padding(.vertical, mode.showsAddChrome ? (chrome.isCompact ? 8 : 16) : 14)
        .background(Theme.slate)
    }

    private var caregiverTools: some View {
        HStack(spacing: 12) {
            if mode.showsHiddenList {
                Button {
                    showingHidden.toggle()
                } label: {
                    VStack(spacing: 2) {
                        Text("Hidden")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                        Text("\(store.hiddenCards.count)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .frame(minWidth: 88, minHeight: 56)
                    .foregroundStyle(Theme.cream)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(showingHidden ? Theme.coral.opacity(0.85) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Theme.cream.opacity(0.65), lineWidth: 3)
                            )
                    )
                }
                .accessibilityLabel("Hidden cards")
                .accessibilityIdentifier("hiddenList")
            }

            Button(action: lockEditing) {
                Text("Lock")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .frame(minWidth: 88, minHeight: 56)
                    .foregroundStyle(Theme.cream)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.cream.opacity(0.65), lineWidth: 3)
                    )
            }
            .accessibilityLabel("Lock")
            .accessibilityIdentifier("lockCaregiver")
        }
    }

    /// Caregiver-only Child 1 / Child 2 switch. Kid mode never shows this.
    private var profileSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(KidProfile.allCases) { profile in
                Button {
                    profiles.switchTo(profile, overlay: store, grid: grid)
                    sync?.profileDidChange()
                } label: {
                    Text(profile.rawValue)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .frame(minWidth: 108, minHeight: 56)
                        .foregroundStyle(Theme.cream)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(profiles.active == profile ? Theme.coral : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Theme.cream.opacity(0.65), lineWidth: 3)
                                )
                        )
                }
                .accessibilityLabel("Switch to \(profile.rawValue)")
                .accessibilityIdentifier("switchProfile-\(profile.rawValue)")
                .accessibilityAddTraits(profiles.active == profile ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kid profile")
        .accessibilityIdentifier("profileSwitcher")
    }

    /// Caregiver-only row × column size. Kid mode still uses the saved counts.
    private var gridPicker: some View {
        HStack(spacing: 10) {
            gridStepper(
                title: "Columns",
                value: grid.columnCount,
                range: GridLayout.allowedColumnRange,
                identifier: "gridColumns",
                accessibility: "columns"
            ) { grid.setColumnCount($0) }
            gridStepper(
                title: "Rows",
                value: grid.rowCount,
                range: GridLayout.allowedRowRange,
                identifier: "gridRows",
                accessibility: "rows"
            ) { grid.setRowCount($0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Grid size")
        .accessibilityIdentifier("gridSize")
    }

    private func gridStepper(
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        identifier: String,
        accessibility: String,
        set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                set(value - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .heavy))
                    .frame(width: 36, height: 44)
            }
            .disabled(value <= range.lowerBound)
            .accessibilityLabel("Fewer \(accessibility)")
            .accessibilityIdentifier("\(identifier)Minus")

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text("\(value)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Theme.cream)
            .frame(minWidth: 64)
            .accessibilityLabel("\(value) \(accessibility)")
            .accessibilityIdentifier("\(identifier)")
            .accessibilityValue("\(value)")

            Button {
                set(value + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .heavy))
                    .frame(width: 36, height: 44)
            }
            .disabled(value >= range.upperBound)
            .accessibilityLabel("More \(accessibility)")
            .accessibilityIdentifier("\(identifier)Plus")
        }
        .foregroundStyle(Theme.cream)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.cream.opacity(0.65), lineWidth: 3)
        )
    }

    /// Folder Home / Back — not the sentence-strip backspace (that control is already labeled Back).
    private var folderNav: some View {
        HStack(spacing: 10) {
            Button {
                store.goHome()
                Task { await store.refresh() }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 20, weight: .bold))
                    Text("Home")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                .frame(minWidth: 76, minHeight: 56)
                .foregroundStyle(Theme.cream)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.cream.opacity(store.isAtRoot ? 0.28 : 0.75), lineWidth: 3)
                )
            }
            .disabled(store.isAtRoot)
            .opacity(store.isAtRoot ? 0.45 : 1)
            .accessibilityIdentifier("folderHome")
            .accessibilityLabel("Home")
            .accessibilityHint("Returns to the first board")

            Button {
                store.goBack()
                Task { await store.refresh() }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 20, weight: .bold))
                    Text("Back")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                .frame(minWidth: 76, minHeight: 56)
                .foregroundStyle(Theme.cream)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.cream.opacity(store.isAtRoot ? 0.28 : 0.75), lineWidth: 3)
                )
            }
            .disabled(store.isAtRoot)
            .opacity(store.isAtRoot ? 0.45 : 1)
            .accessibilityIdentifier("folderBack")
            .accessibilityLabel("Folder back")
            .accessibilityHint("Returns to the parent board")
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hope's Voice")
                .font(.system(chrome.isCompact ? .headline : .title2, design: .rounded).weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Theme.cream)
            Text(profiles.activeName)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Theme.coral)
                .clipShape(Capsule())
                .accessibilityIdentifier("activeProfile")
                .accessibilityLabel("Active profile \(profiles.activeName)")
            if let folderName = store.currentFolderName {
                Text(folderName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.cream.opacity(0.9))
                    .accessibilityIdentifier("currentFolderName")
            }
            if mode.showsAddChrome {
                Text(mode.showsEditChrome ? "Caregiver · Edit" : "Caregiver")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.cream.opacity(0.75))
                    .accessibilityIdentifier("caregiverIndicator")
            }
        }
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: CaregiverMode.unlockHoldDuration) {
            mode.unlockAndEdit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("boardTitle")
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Hold to unlock caregiver tools")
    }

    private var addChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 16) {
            Button {
                openNewButtonEditor()
            } label: {
                Text("+ Add button")
                    .font(.system(size: chrome.isCompact ? 16 : 22, weight: .heavy, design: .rounded))
                    .frame(minWidth: chrome.isCompact ? 108 : 148, minHeight: chrome.isCompact ? 52 : 64)
                    .foregroundStyle(Theme.cream)
                    .background(Theme.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityLabel("Add button")
            .accessibilityIdentifier("addButton")

            gridPicker

            TextField("type a word", text: $draft)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .focused($fieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { Task { await submit() } }
                .accessibilityLabel("Word to add")
                .accessibilityIdentifier("addWordField")
                .disabled(store.isAdding)

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if store.isAdding {
                        ProgressView()
                            .tint(Theme.cream)
                            .scaleEffect(1.3)
                    } else {
                        Text("Add")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                    }
                }
                .frame(minWidth: 112, minHeight: 64)
                .foregroundStyle(Theme.cream)
                .background(canAdd ? Theme.coral : Theme.coral.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(!canAdd)
            .accessibilityLabel("Add word")
            .accessibilityIdentifier("addWord")

            Button {
                Task { await submitFolder() }
            } label: {
                Text("Folder")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .frame(minWidth: 100, minHeight: 64)
                    .foregroundStyle(Theme.cream)
                    .background(canAdd ? Theme.slate : Theme.slate.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(!canAdd)
            .accessibilityLabel("Add folder")
            .accessibilityIdentifier("addFolder")

            if mode.showsVoiceChrome {
                voiceMicButton
            }
        }
        }
        ScrollView(.horizontal, showsIndicators: false) {
            messageBarSettings
        }
        }
    }

    private var messageBarSettings: some View {
        HStack(spacing: 16) {
            messageBarToggle("Speak on tap", isOn: speakOnTapBinding, identifier: "speakOnTap")
            messageBarToggle("Tap bar to speak", isOn: speakOnBarTapBinding, identifier: "speakOnBarTap")
            messageBarToggle("Clear after speak", isOn: clearAfterSpeakBinding, identifier: "clearAfterSpeak")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messageBarSettings")
    }

    private func messageBarToggle(_ title: String, isOn: Binding<Bool>, identifier: String) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
        }
        .tint(Theme.coral)
        .accessibilityIdentifier(identifier)
    }

    private var speakOnTapBinding: Binding<Bool> {
        Binding(
            get: { store.messageBar.speakOnTap },
            set: {
                var next = store.messageBar
                next.speakOnTap = $0
                store.setMessageBar(next)
            }
        )
    }

    private var speakOnBarTapBinding: Binding<Bool> {
        Binding(
            get: { store.messageBar.speakOnBarTap },
            set: {
                var next = store.messageBar
                next.speakOnBarTap = $0
                store.setMessageBar(next)
            }
        )
    }

    private var clearAfterSpeakBinding: Binding<Bool> {
        Binding(
            get: { store.messageBar.clearAfterSpeak },
            set: {
                var next = store.messageBar
                next.clearAfterSpeak = $0
                store.setMessageBar(next)
            }
        )
    }

    /// Caregiver-only on-device mic. Kid mode never mounts this control.
    private var voiceMicButton: some View {
        Button {
            guard mode.showsVoiceChrome else { return }
            fieldFocused = false
            searchFieldFocused = false
            voice.clearError()
            Task { await voice.toggle() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: voice.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 22, weight: .bold))
                Text(voice.isListening ? "Stop" : "Mic")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .frame(minWidth: 88, minHeight: 64)
            .foregroundStyle(Theme.cream)
            .background(voice.isListening ? Theme.coral : Theme.slate)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityLabel(voice.isListening ? "Stop listening" : "Add word by voice")
        .accessibilityIdentifier("voiceAddMic")
        .disabled(store.isAdding)
    }

    /// Caregiver-only current-board filter. Separate from Add so a query cannot POST a card.
    private var searchChrome: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink.opacity(0.5))
                .accessibilityHidden(true)

            TextField("search this board", text: searchQueryBinding)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .focused($searchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFieldFocused = false }
                .accessibilityLabel("Search this board")
                .accessibilityIdentifier("boardSearchField")

            if !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    store.setSearchQuery("")
                    searchFieldFocused = false
                } label: {
                    Text("Clear")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .frame(minWidth: 88, minHeight: 56)
                        .foregroundStyle(Theme.cream)
                        .background(Theme.slate)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("clearBoardSearch")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { store.searchQuery },
            set: { store.setSearchQuery($0) }
        )
    }

    /// Sticky core vocabulary. Always on-screen at root and inside folders;
    /// kid mode can tap it; caregiver Edit does not hide it.
    private var coreRow: some View {
        HStack(spacing: chrome.coreSpacing) {
            ForEach(store.coreCards) { card in
                Button {
                    store.tapCore(card)
                } label: {
                    CoreWordCell(
                        card: card,
                        image: store.image(for: card),
                        backgroundColor: Color(hex: store.style(forCard: card.slug).backgroundHex),
                        remoteURL: store.remoteImageURL(for: card),
                        revision: store.imageRevision[card.slug, default: 0],
                        highlighted: store.lastSpokenSlug == card.slug
                    )
                    .frame(width: chrome.coreCellWidth)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(card.word)
                .accessibilityHint("Adds this word to the sentence")
                .accessibilityIdentifier("coreWord-\(card.slug)")
            }
        }
        .padding(.horizontal, chrome.corePadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.slate)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Core words")
        .accessibilityIdentifier("coreRow")
    }

    /// Sticky Recents. Hidden when empty. Same cream/ink/slate cells as cores.
    /// Stays outside the grid ScrollView so it remains visible inside folders.
    private var recentsRow: some View {
        // Same fixed-width cells as the core row and at most `recentsLimit` of them, so the row
        // always fits the screen and never scrolls.
        HStack(spacing: chrome.coreSpacing) {
            ForEach(store.recentCards) { card in
                Button {
                    store.tapRecent(card)
                } label: {
                    CoreWordCell(
                        card: card,
                        label: store.displayLabel(for: card),
                        image: store.image(for: card),
                        backgroundColor: Color(hex: store.style(forCard: card.slug).backgroundHex),
                        remoteURL: store.remoteImageURL(for: card),
                        revision: store.imageRevision[card.slug, default: 0],
                        highlighted: store.lastSpokenSlug == card.slug
                    )
                    .frame(width: chrome.coreCellWidth)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(store.displayLabel(for: card))
                .accessibilityHint("Adds this word to the sentence")
                .accessibilityIdentifier("recentWord-\(card.slug)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, chrome.corePadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: chrome.coreRowHeight + 16)
        .background(Theme.slate)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recents")
        .accessibilityIdentifier("recentsRow")
    }

    private var board: some View {
        Group {
            if store.showsEmptyBoard && !mode.isEditing {
                ScrollView {
                    emptyBoard
                        .padding(.top, 48)
                }
            } else if mode.showsSearchChrome && !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    LazyVGrid(columns: chrome.gridItems, spacing: chrome.gridSpacing) {
                        ForEach(store.filteredCurrentItems) { item in
                            boardCell(item)
                        }
                    }
                    .padding(.horizontal, chrome.gridPadding)
                    .padding(.vertical, chrome.gridPadding + chrome.highlightStroke)
                }
            } else if store.hasImportedBoard {
                // Imported boards fill the remaining space with equal cells so a
                // 4×6 page fits (including empty rows, which keeps short folders
                // bottom-aligned when their cells are already on the last rows).
                importedBoardGrid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.boardCellExpands, true)
            } else {
                defaultBoardGrid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.boardCellExpands, true)
            }
        }
        .refreshable { await store.refresh() }
    }

    /// The default board: exactly `columnCount` columns across the width and `rowCount`
    /// rows filling the height. Extra rows (more buttons than seats) scroll vertically;
    /// cells never get shorter than `chrome.minimumCellHeight` and never scroll sideways.
    private var defaultBoardGrid: some View {
        GeometryReader { geo in
            let slots = boardSlots
            let cols = max(store.importedBoardCols ?? grid.columnCount, 1)
            let totalRows = max((slots.count + cols - 1) / cols, 1)
            let verticalPadding = chrome.gridPadding + chrome.highlightStroke
            let cellHeight = BoardChrome.fittedCellHeight(
                available: geo.size.height,
                rows: max(grid.rowCount, 1),
                verticalPadding: verticalPadding,
                spacing: chrome.gridSpacing,
                minimum: chrome.minimumCellHeight
            )
            let cellWidth = chrome.cellWidth(columns: cols)
            ScrollView(.vertical) {
                // Lazy, so a board with hundreds of buttons only builds the rows on screen.
                // Fixed columns keep every cell exactly `cellWidth` wide.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: chrome.gridSpacing), count: cols),
                    spacing: chrome.gridSpacing
                ) {
                    ForEach(0..<(totalRows * cols), id: \.self) { index in
                        Group {
                            if index < slots.count {
                                boardSlotCell(slots[index])
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: cellWidth, height: cellHeight)
                    }
                }
                .padding(.horizontal, chrome.gridPadding)
                .padding(.vertical, verticalPadding)
                .frame(width: geo.size.width)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var importedBoardGrid: some View {
        // A Grid of flexible cells has no intrinsic height. Take the size the
        // VStack offers and pass it down so empty rows still fill the page.
        GeometryReader { geo in
            Group {
                if store.importedPageCount > 1 {
                    pagedBoard
                } else {
                    filledImportGrid(
                        slots: boardSlots,
                        rowStart: 0,
                        rows: max(store.importedBoardRows ?? viewportRows, 1),
                        cols: max(store.importedBoardCols ?? viewportCols, 1)
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var pagedBoard: some View {
        let pages = store.importedPageCount
        let rowsPerPage = viewportRows
        return TabView(selection: $boardPage) {
            ForEach(0..<pages, id: \.self) { page in
                filledImportGrid(
                    slots: boardSlots,
                    rowStart: page * rowsPerPage,
                    rows: rowsPerPage,
                    cols: max(store.importedBoardCols ?? viewportCols, 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onChange(of: store.folderPath) { old, new in if old != new { boardPage = 0 } }
    }

    /// Equal-sized cells that fill the board area, including empty rows.
    private func filledImportGrid(slots: [BoardSlot], rowStart: Int, rows: Int, cols: Int) -> some View {
        let rows = max(rows, 1)
        let cols = max(cols, 1)
        let lookup = Dictionary(uniqueKeysWithValues: slots.map { ($0.coord, $0) })
        return Grid(horizontalSpacing: chrome.gridSpacing, verticalSpacing: chrome.gridSpacing) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { col in
                        let coord = GridCoord(row: rowStart + row, col: col)
                        boardSlotCell(lookup[coord] ?? .empty(coord))
                            .frame(width: chrome.cellWidth(columns: cols))
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, chrome.gridPadding)
        .padding(.vertical, chrome.gridPadding + chrome.highlightStroke)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Fixed row × column slots. Empty cells stay put so buttons never slide.
    private var boardSlots: [BoardSlot] {
        store.slots(
            rows: store.importedBoardRows ?? grid.rowCount,
            columns: store.importedBoardCols ?? grid.columnCount,
            editing: mode.isEditing
        )
    }

    private var viewportRows: Int {
        max(store.hasImportedBoard ? store.settings.viewportRows : grid.rowCount, 1)
    }

    private var viewportCols: Int {
        max(store.hasImportedBoard ? store.settings.viewportCols : grid.columnCount, 1)
    }

    /// Kid mode always shows the full current board. Caregiver search is a view over it.
    private var visibleBoardItems: [BoardItem] {
        mode.showsSearchChrome ? store.filteredCurrentItems : store.currentItems
    }

    private var emptyBoard: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.ink.opacity(0.22), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                .frame(width: 280, height: 320)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(Theme.ink.opacity(0.35))
                        Text("empty card")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.muted)
                    }
                }
            Text("This board is empty.")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(emptyBoardHint)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            if store.isLoading {
                ProgressView("Looking for cards on the server…")
                    .font(.system(.title3, design: .rounded))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 80)
    }

    @ViewBuilder
    private var sentenceStrip: some View {
        if store.messageBar.style == "compactBlue" {
            compactMessageBar
        } else {
        HStack(alignment: .center, spacing: chrome.stripSpacing) {
            Button {
                store.speakStrip()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: chrome.stripIconSize, weight: .bold))
                    Text("Speak")
                        .font(.system(size: chrome.stripLabelSize, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: chrome.speakWidth, height: chrome.stripHeight)
                .foregroundStyle(Theme.cream)
                .background(store.strip.isEmpty ? Theme.coral.opacity(0.4) : Theme.coral)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(store.strip.isEmpty)
            .accessibilityIdentifier("speakSentence")
            .accessibilityLabel("Speak sentence")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: chrome.stripChipSpacing) {
                        if store.strip.isEmpty {
                            Text(chrome.isCompact ? "Tap cards to talk" : "Tap cards to build a sentence")
                                .font(.system(size: chrome.stripPlaceholderSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.horizontal, 8)
                        } else {
                            ForEach(store.strip.chips) { chip in
                                StripChipView(
                                    card: chip.card,
                                    label: store.displayLabel(for: chip.card),
                                    image: store.image(for: chip.card),
                                    remoteURL: store.remoteImageURL(for: chip.card)
                                )
                                .id(chip.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: chrome.stripHeight)
                }
                .onChange(of: store.strip.chips.count) {
                    if let last = store.strip.chips.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .trailing)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minWidth: chrome.minimumChipWellWidth)
            .frame(height: chrome.stripHeight)
            .background(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.ink.opacity(0.22), lineWidth: 3)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if store.messageBar.speakOnBarTap, !store.strip.isEmpty {
                    store.speakStrip()
                }
            }
            .accessibilityIdentifier("sentenceStrip")
            .accessibilityHint("Tap to speak the sentence")

            Button {
                store.backspaceStrip()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "delete.backward.fill")
                        .font(.system(size: chrome.stripIconSize, weight: .bold))
                    Text("Back")
                        .font(.system(size: chrome.stripLabelSize, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: chrome.sideButtonWidth, height: chrome.stripHeight)
                .foregroundStyle(Theme.ink)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.ink.opacity(0.35), lineWidth: 3)
                )
            }
            .disabled(store.strip.isEmpty)
            .accessibilityIdentifier("backspaceSentence")
            .accessibilityLabel("Backspace")

            Button {
                store.clearStrip()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "xmark")
                        .font(.system(size: chrome.stripIconSize, weight: .bold))
                    Text("Clear")
                        .font(.system(size: chrome.stripLabelSize, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: chrome.sideButtonWidth, height: chrome.stripHeight)
                .foregroundStyle(Theme.cream)
                .background(store.strip.isEmpty ? Theme.slate.opacity(0.45) : Theme.slate)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(store.strip.isEmpty)
            .accessibilityIdentifier("clearSentence")
            .accessibilityLabel("Clear sentence")
        }
        .padding(.horizontal, chrome.stripPadding)
        .padding(.vertical, chrome.stripVerticalPadding)
        .background(Theme.board)
        }
    }

    private var compactMessageBar: some View {
        let barColor = Color(hex: store.messageBar.backgroundHex ?? "0000CB") ?? Color(red: 0, green: 0, blue: 0.8)
        return HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    if store.strip.isEmpty {
                        Text(" ")
                            .frame(minHeight: 52)
                    } else {
                        ForEach(store.strip.chips) { chip in
                            VStack(spacing: 2) {
                                Text(store.displayLabel(for: chip.card))
                                    .font(.system(size: 13, weight: .bold, design: .serif).italic())
                                    .foregroundStyle(Color(white: 0.82))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                if let image = store.image(for: chip.card) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 36, height: 28)
                                        .clipped()
                                } else {
                                    Color.white.opacity(0.15)
                                        .frame(width: 36, height: 28)
                                }
                            }
                            .id(chip.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if store.messageBar.speakOnBarTap, !store.strip.isEmpty {
                    store.speakStrip()
                }
            }
            .accessibilityIdentifier("sentenceStrip")
            .accessibilityHint("Tap to speak the sentence")

            if store.messageBar.showDeleteLast {
                Button {
                    store.backspaceStrip()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black))
                }
                .disabled(store.strip.isEmpty)
                .accessibilityIdentifier("backspaceSentence")
                .accessibilityLabel("Delete last")
                .padding(.trailing, 8)
            }
        }
        .frame(height: 57)
        .background(barColor)
    }

    private var hiddenList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Hidden cards")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("These stay off the kid board until you Unhide them. They are not deleted on the server.")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                if store.hiddenCards.isEmpty {
                    Text("No hidden cards.")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(store.hiddenCards) { card in
                            VStack(spacing: 10) {
                                CardCell(
                                    card: card,
                                    label: store.displayLabel(for: card),
                                    image: store.image(for: card),
                                    remoteURL: store.remoteImageURL(for: card),
                                    revision: store.imageRevision[card.slug, default: 0],
                                    highlighted: false
                                )
                                Button {
                                    store.unhide(card.slug)
                                } label: {
                                    Text("Unhide")
                                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .foregroundStyle(Theme.cream)
                                        .background(Theme.slate)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .accessibilityLabel("Unhide \(card.word)")
                                .accessibilityIdentifier("unhideCard-\(card.slug)")
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("hiddenBoard")
    }

    @ViewBuilder
    private func boardSlotCell(_ slot: BoardSlot) -> some View {
        switch slot {
        case .empty(let coord):
            emptyCell(at: coord)
        case .hidden(let item, let coord):
            boardCell(item, at: coord, dimmed: true)
        case .item(let item, let coord):
            boardCell(item, at: coord, dimmed: false)
        }
    }

    private func emptyCell(at coord: GridCoord) -> some View {
        let canAdd = mode.isEditing
        return Button {
            if canAdd {
                editorDraft = store.draftForNewButton(at: coord)
            }
        } label: {
            RoundedRectangle(cornerRadius: chrome.isCompact ? 16 : 22, style: .continuous)
                .stroke(canAdd ? Theme.ink.opacity(0.35) : Color.clear, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                .background(
                    RoundedRectangle(cornerRadius: chrome.isCompact ? 16 : 22, style: .continuous)
                        .fill(canAdd ? Theme.cream.opacity(0.35) : Color.clear)
                )
                .overlay {
                    if canAdd {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: chrome.isCompact ? 22 : 28, weight: .bold))
                            Text("Add")
                                .font(.system(size: chrome.isCompact ? 14 : 18, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(Theme.ink.opacity(0.45))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .accessibilityLabel("Add button")
        .accessibilityHint("Adds a button in this cell")
        .accessibilityIdentifier("emptyCell-\(coord.row)-\(coord.col)")
        .allowsHitTesting(canAdd)
    }

    @ViewBuilder
    private func boardCell(_ item: BoardItem, at coord: GridCoord? = nil, dimmed: Bool = false) -> some View {
        let label = store.displayLabel(for: item)
        let style = store.style(for: item)
        let background = Color(hex: style.backgroundHex) ?? Theme.cream
        let border = Color(hex: style.borderHex) ?? Theme.cardStroke
        switch item {
        case .word(let card):
            ZStack(alignment: .topTrailing) {
                CardCell(
                    card: card,
                    label: label,
                    image: store.image(for: card),
                    remoteURL: store.remoteImageURL(for: card),
                    revision: store.imageRevision[card.slug, default: 0],
                    highlighted: store.lastSpokenSlug == card.slug,
                    backgroundColor: background,
                    borderColor: border
                )
            }
            .opacity(dimmed ? 0.45 : 1)
            .onTapGesture { handleBoardTap(item, at: coord) }
            .modifier(BoardReorderSupport(
                itemID: item.id,
                enabled: mode.showsEditChrome,
                draggingItemID: $draggingItemID,
                store: store
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { handleBoardTap(item, at: coord) }
            .accessibilityLabel(label)
            .accessibilityHint("Adds this word to the sentence")
            .accessibilityIdentifier("card-\(card.slug)")
        case .folder(let folder):
            ZStack(alignment: .topTrailing) {
                FolderCell(
                    folder: folder,
                    label: label,
                    image: store.image(for: folder),
                    remoteURL: store.remoteImageURL(for: folder),
                    revision: store.imageRevision[folder.id, default: 0],
                    backgroundColor: background,
                    borderColor: border
                )
            }
            .opacity(dimmed ? 0.45 : 1)
            .onTapGesture { handleBoardTap(item, at: coord) }
            .modifier(BoardReorderSupport(
                itemID: item.id,
                enabled: mode.showsEditChrome,
                draggingItemID: $draggingItemID,
                store: store
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { handleBoardTap(item, at: coord) }
            .accessibilityLabel("\(label) folder")
            .accessibilityHint("Opens this folder")
            .accessibilityIdentifier("folder-\(folder.id)")
        }
    }

    /// Hide / Delete / Rename plus a drag handle. Kid mode never mounts this.
    @ViewBuilder
    private func editChrome(for item: BoardItem, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            switch item {
            case .word(let card):
                Button {
                    pendingHide = card
                } label: {
                    editCapsule("Hide", fill: Theme.slate)
                }
                .accessibilityLabel("Hide \(label)")
                .accessibilityIdentifier("hideCard-\(card.slug)")

                Button {
                    pendingDelete = card
                } label: {
                    editCapsule("Delete", fill: Theme.coral)
                }
                .accessibilityLabel("Delete \(label) forever")
                .accessibilityIdentifier("deleteCard-\(card.slug)")

                Button {
                    pendingRenameSlug = card.slug
                    pendingRenameFallback = card.word
                    renameDraft = store.displayLabel(for: card)
                } label: {
                    editCapsule("Rename", fill: Theme.slate)
                }
                .accessibilityLabel("Rename \(label)")
                .accessibilityIdentifier("renameCard-\(card.slug)")
            case .folder(let folder):
                Button {
                    pendingDeleteFolder = folder
                } label: {
                    editCapsule("Delete", fill: Theme.coral)
                }
                .accessibilityLabel("Delete \(label) folder")
                .accessibilityIdentifier("deleteFolder-\(folder.id)")

                Button {
                    pendingRenameSlug = folder.id
                    pendingRenameFallback = folder.name
                    renameDraft = store.displayLabel(for: folder)
                } label: {
                    editCapsule("Rename", fill: Theme.slate)
                }
                .accessibilityLabel("Rename \(label) folder")
                .accessibilityIdentifier("renameFolder-\(folder.id)")
            }
        }
        .padding(12)
    }

    private func dragHandle(itemID: String) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(Theme.cream)
            .frame(width: 40, height: 36)
            .background(Theme.slate)
            .clipShape(Capsule())
            .accessibilityLabel("Drag to reorder")
            .accessibilityIdentifier("dragHandle-\(itemID)")
    }

    private func editCapsule(_ title: String, fill: Color) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Theme.cream)
            .background(fill)
            .clipShape(Capsule())
    }

    private var columns: [GridItem] {
        chrome.gridItems
    }

    private var emptyBoardHint: String {
        if mode.showsAddChrome {
            return "Type a word up top and tap Add.\nHope's Voice will make the picture and the voice."
        }
        return "Ask a grown-up to add a word.\nHope's Voice will make the picture and the voice."
    }

    private func lockEditing() {
        fieldFocused = false
        searchFieldFocused = false
        draft = ""
        store.setSearchQuery("")
        showingHidden = false
        pendingHide = nil
        editorDraft = nil
        pendingVoiceWord = nil
        voice.cancel()
        mode.lock()
    }

    private func openNewButtonEditor() {
        let coord = store.firstEmptyCoord(rows: grid.rowCount, columns: grid.columnCount)
            ?? GridCoord(row: grid.rowCount, col: 0)
        editorDraft = store.draftForNewButton(at: coord)
        if !mode.isEditing {
            mode.enterEdit()
        }
    }

    private func handleBoardTap(_ item: BoardItem, at coord: GridCoord?) {
        if mode.isEditing {
            let at = coord ?? GridCoord(row: 0, col: 0)
            editorDraft = store.draftForExisting(item, at: at)
            return
        }
        store.select(item)
        if case .folder = item {
            Task { await store.refresh() }
        }
    }

    private func saveEditor() async {
        guard let draft = editorDraft, draft.canSave else { return }
        editorBusy = true
        defer { editorBusy = false }
        if await store.saveEditorDraft(draft) != nil {
            editorDraft = nil
        }
    }

    private func hideEditorItem() {
        guard let draft = editorDraft, let existingID = draft.existingID else { return }
        if existingID.hasPrefix("folder:") { return }
        if let card = store.cards.first(where: { $0.slug == existingID }) {
            editorDraft = nil
            pendingHide = card
        }
    }

    private func deleteEditorItem() {
        guard let draft = editorDraft, let existingID = draft.existingID else { return }
        editorDraft = nil
        if existingID.hasPrefix("folder:") {
            let id = String(existingID.dropFirst("folder:".count))
            pendingDeleteFolder = store.grouping.folder(id: id)
        } else if let card = store.cards.first(where: { $0.slug == existingID }) {
            pendingDelete = card
        }
    }

    private var canAdd: Bool {
        !store.isAdding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        let word = draft
        draft = ""
        fieldFocused = false
        await store.addWord(word)
    }

    private func submitFolder() async {
        let name = draft
        draft = ""
        fieldFocused = false
        await store.addFolder(name)
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var file = url
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                if let found = findBoardFile(in: url) {
                    file = found
                } else {
                    importError = "That folder does not contain a bestwishes.board/v1 JSON file."
                    return
                }
            }
            importBoard(from: file)
        }
    }

    private func findBoardFile(in directory: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let json = files.filter { $0.pathExtension.lowercased() == "json" }
        return json.first(where: { $0.lastPathComponent.contains("bestwishes") }) ?? json.first
    }

    private func importBoard(from url: URL, showBanner: Bool = true) {
        do {
            try store.importBoard(from: url)
            if let cols = store.importedBoardCols {
                grid.setColumnCount(cols)
            }
            boardPage = 0
            if showBanner {
                store.banner = "Imported \(store.importedDocument?.boards.count ?? 0) boards."
            }
        } catch {
            importError = error.localizedDescription
        }
    }


    @MainActor
    private func applyBoardPageLaunchHook(_ page: Int) async {
        for _ in 0..<40 {
            if store.hasImportedBoard, store.importedPageCount > page { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        boardPage = max(page, 0)
        // TabView may not exist yet on the first assignment; set it again once the pager is on screen.
        try? await Task.sleep(for: .milliseconds(800))
        boardPage = max(page, 0)
    }

    /// Test hooks that make a caregiver edit through the same store calls the editor uses:
    /// `-SyncDemoLabel slug=Label` renames, `-SyncDemoHide slug` hides.
    private func applySyncDemoEdits(_ args: [String]) {
        if let idx = args.firstIndex(of: "-SyncDemoLabel"), args.indices.contains(idx + 1) {
            let parts = args[idx + 1].split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { store.setDisplayLabel(parts[1], for: parts[0]) }
        }
        if let idx = args.firstIndex(of: "-SyncDemoHide"), args.indices.contains(idx + 1) {
            store.hideAfterConfirm(args[idx + 1])
        }
    }

    private func consumeLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        grid.applySizeClassDefaultsIfNeeded(isCompact: horizontalSizeClass == .compact)
        mode.applyLaunchArguments(args)
        profiles.applyLaunchArguments(args, overlay: store, grid: grid)
        // Test hook: start from the default board's Home (drops a saved import and folder).
        if args.contains("-ClearImportedBoard") {
            store.clearImportedBoard()
            grid.resetToSizeClassDefaults(isCompact: horizontalSizeClass == .compact)
            store.goHome()
        }
        grid.applyLaunchArguments(args)
        applySyncDemoEdits(args)
        if args.contains("-OpenSettings") { showingSettings = true }
        if let idx = args.firstIndex(of: "-ImportBoard"), args.indices.contains(idx + 1) {
            let path = args[idx + 1]
            Task { @MainActor in
                importBoard(from: URL(fileURLWithPath: path), showBanner: false)
                // Let folder-name onChange reset the page before we apply launch hooks.
                try? await Task.sleep(for: .milliseconds(400))
                if let folderIdx = args.firstIndex(of: "-OpenFolder"), args.indices.contains(folderIdx + 1) {
                    await runFolderLaunchHooks(folderId: args[folderIdx + 1])
                    try? await Task.sleep(for: .milliseconds(300))
                }
                if let pageIdx = args.firstIndex(of: "-BoardPage"), args.indices.contains(pageIdx + 1),
                   let page = Int(args[pageIdx + 1]) {
                    await applyBoardPageLaunchHook(page)
                }
            }
        } else if let idx = args.firstIndex(of: "-OpenFolder"), args.indices.contains(idx + 1) {
            Task { @MainActor in
                await runFolderLaunchHooks(folderId: args[idx + 1])
                try? await Task.sleep(for: .milliseconds(300))
                if let pageIdx = args.firstIndex(of: "-BoardPage"), args.indices.contains(pageIdx + 1),
                   let page = Int(args[pageIdx + 1]) {
                    await applyBoardPageLaunchHook(page)
                }
            }
        } else if let pageIdx = args.firstIndex(of: "-BoardPage"), args.indices.contains(pageIdx + 1),
                  let page = Int(args[pageIdx + 1]) {
            Task { @MainActor in
                await applyBoardPageLaunchHook(page)
            }
        }
        if let idx = args.firstIndex(of: "-AddWord"), args.indices.contains(idx + 1) {
            let word = args[idx + 1]
            Task { await store.addWord(word) }
        }
        if let idx = args.firstIndex(of: "-SpeakSlug"), args.indices.contains(idx + 1) {
            let slug = args[idx + 1]
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if let card = store.cards.first(where: { $0.slug == slug }) {
                    store.tap(card)
                }
            }
        }
        if let idx = args.firstIndex(of: "-StripAppend"), args.indices.contains(idx + 1) {
            let slugs = args[idx + 1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            Task { await runStripLaunchHooks(slugs: slugs) }
        }
        if args.contains("-ShowHidden") {
            showingHidden = true
        }
        if let idx = args.firstIndex(of: "-HideSlug"), args.indices.contains(idx + 1) {
            let slug = args[idx + 1]
            Task { await runHideLaunchHooks(slug: slug) }
        }
        if let idx = args.firstIndex(of: "-UnhideSlug"), args.indices.contains(idx + 1) {
            let slug = args[idx + 1]
            Task { await runUnhideLaunchHooks(slug: slug) }
        }
        if let idx = args.firstIndex(of: "-AddFolder"), args.indices.contains(idx + 1) {
            let name = args[idx + 1]
            Task { await runAddFolderLaunchHooks(name: name) }
        }
        if let idx = args.firstIndex(of: "-ReorderIds"), args.indices.contains(idx + 1) {
            let ids = args[idx + 1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            Task { await runReorderLaunchHooks(ids: ids) }
        }
        if let idx = args.firstIndex(of: "-RenameSlug"), args.indices.contains(idx + 1) {
            let slug = args[idx + 1]
            var label = ""
            if let labelIdx = args.firstIndex(of: "-RenameLabel"), args.indices.contains(labelIdx + 1) {
                label = args[labelIdx + 1]
            }
            Task { await runRenameLaunchHooks(slug: slug, label: label) }
        }
        if args.contains("-TapSlugs") || args.contains("-TapRecent") {
            Task { await runRecentsLaunchHooks() }
        }
        if let idx = args.firstIndex(of: "-SearchQuery"), args.indices.contains(idx + 1) {
            let query = args[idx + 1]
            Task { await runSearchLaunchHooks(query: query) }
        }
        if let idx = args.firstIndex(of: "-VoiceTranscript"), args.indices.contains(idx + 1) {
            let transcript = args[idx + 1]
            Task { await runVoiceTranscriptLaunchHooks(transcript: transcript) }
        }
        if let idx = args.firstIndex(of: "-VoiceConfirm"), args.indices.contains(idx + 1) {
            let word = args[idx + 1]
            Task { await runVoiceConfirmLaunchHooks(word: word) }
        }
        if args.contains("-VoiceListen") {
            Task { await runVoiceListenLaunchHooks() }
        }
    }

    private func consumeVoiceTranscript(_ transcript: String?) {
        guard mode.showsVoiceChrome else {
            voice.clearFinishedTranscript()
            return
        }
        guard let transcript, !transcript.isEmpty else { return }
        voice.clearFinishedTranscript()
        if let word = VoiceAdd.word(from: transcript) {
            pendingVoiceWord = word
        } else {
            store.errorMessage = "Didn't catch a word. Try “add juice”."
        }
    }

    /// Screenshot path: parse the same way a finished dictation does, then show confirm.
    private func runVoiceTranscriptLaunchHooks(transcript: String) async {
        for _ in 0..<40 {
            let ready = !store.isLoading && (!store.cards.isEmpty || !store.grouping.folders.isEmpty)
            if ready { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard mode.showsVoiceChrome else { return }
        if let word = VoiceAdd.word(from: transcript) {
            pendingVoiceWord = word
        }
    }

    /// Simulator probe: start the same on-device recognizer the Mic button uses.
    private func runVoiceListenLaunchHooks() async {
        for _ in 0..<40 {
            let ready = !store.isLoading && (!store.cards.isEmpty || !store.grouping.folders.isEmpty)
            if ready { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard mode.showsVoiceChrome else { return }
        await voice.startListening()
    }

    /// Screenshot path: present the shipped confirm sheet for an already-parsed word.
    private func runVoiceConfirmLaunchHooks(word: String) async {
        for _ in 0..<40 {
            let ready = !store.isLoading && (!store.cards.isEmpty || !store.grouping.folders.isEmpty)
            if ready { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard mode.showsVoiceChrome else { return }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingVoiceWord = trimmed
    }

    /// Screenshot path: write the same query the search field uses, without focusing it
    /// so the software keyboard does not cover the filtered grid.
    private func runSearchLaunchHooks(query: String) async {
        for _ in 0..<40 {
            let ready = !store.isLoading && (!store.cards.isEmpty || !store.grouping.folders.isEmpty)
            if ready { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        store.setSearchQuery(query)
        searchFieldFocused = false
        fieldFocused = false
    }

    /// Screenshot / demo path: tap board cards (counts toward Recents), optional
    /// strip clear, then tap a Recents cell through `tapRecent`.
    private func runRecentsLaunchHooks() async {
        let args = ProcessInfo.processInfo.arguments
        var tapSlugs: [String] = []
        if let idx = args.firstIndex(of: "-TapSlugs"), args.indices.contains(idx + 1) {
            tapSlugs = args[idx + 1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        var tapRecentSlug: String?
        if let idx = args.firstIndex(of: "-TapRecent"), args.indices.contains(idx + 1) {
            tapRecentSlug = args[idx + 1]
        }
        let needed = tapSlugs + (tapRecentSlug.map { [$0] } ?? [])
        for _ in 0..<40 {
            let ready = needed.allSatisfy { slug in store.cards.contains { $0.slug == slug } }
            if ready { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        for slug in tapSlugs {
            if let card = store.cards.first(where: { $0.slug == slug }) {
                store.tap(card)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        if args.contains("-StripClear") {
            try? await Task.sleep(for: .milliseconds(400))
            store.clearStrip()
        }
        if let slug = tapRecentSlug {
            for _ in 0..<20 {
                if store.recentSlugs.contains(slug) { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            if let card = store.recentCards.first(where: { $0.slug == slug }) {
                store.tapRecent(card)
            }
        }
    }

    private func runReorderLaunchHooks(ids: [String]) async {
        for _ in 0..<40 {
            if !store.currentItems.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        store.reorderCurrentItems(ids: ids)
    }

    private func runRenameLaunchHooks(slug: String, label: String) async {
        for _ in 0..<40 {
            let knownCard = store.cards.contains { $0.slug == slug }
            let knownFolder = store.grouping.folder(id: slug) != nil
            if knownCard || knownFolder { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        store.setDisplayLabel(label, for: slug)
    }

    private func runHideLaunchHooks(slug: String) async {
        let args = ProcessInfo.processInfo.arguments
        for _ in 0..<40 {
            if store.cards.contains(where: { $0.slug == slug }) { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        store.hideAfterConfirm(slug)
        if args.contains("-ShowHidden") {
            showingHidden = true
        }
    }

    private func runUnhideLaunchHooks(slug: String) async {
        for _ in 0..<40 {
            if store.hiddenSlugs.contains(slug) { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        store.unhide(slug)
    }

    private func runAddFolderLaunchHooks(name: String) async {
        for _ in 0..<40 {
            let ready = !store.isLoading && (!store.cards.isEmpty || !store.grouping.folders.isEmpty)
            if ready { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await store.addFolder(name)
    }

    private func runFolderLaunchHooks(folderId: String) async {
        let args = ProcessInfo.processInfo.arguments
        for _ in 0..<40 {
            if let folder = store.grouping.folder(id: folderId) {
                let membersReady = folder.memberSlugs.allSatisfy { slug in
                    store.cards.contains { $0.slug == slug }
                }
                if membersReady { break }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        store.openFolder(id: folderId)
        if args.contains("-GoBack") {
            try? await Task.sleep(for: .milliseconds(700))
            store.goBack()
        }
        if args.contains("-GoHome") {
            try? await Task.sleep(for: .milliseconds(700))
            store.goHome()
        }
    }

    private func runStripLaunchHooks(slugs: [String]) async {
        let args = ProcessInfo.processInfo.arguments
        for _ in 0..<40 {
            let ready = slugs.allSatisfy { slug in store.cards.contains { $0.slug == slug } }
            if ready { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        store.appendSlugsFromBoard(slugs)
        if args.contains("-StripSpeak") {
            try? await Task.sleep(for: .milliseconds(600))
            store.speakStrip()
        }
        if args.contains("-StripBackspace") {
            try? await Task.sleep(for: .milliseconds(900))
            store.backspaceStrip()
        }
        if args.contains("-StripClear") {
            try? await Task.sleep(for: .milliseconds(900))
            store.clearStrip()
        }
    }
}

/// Compact high-contrast core-strip cell. Uses the same server image cache as `CardCell`.
struct CoreWordCell: View {
    let card: Card
    var label: String? = nil
    let image: UIImage?
    var backgroundColor: Color? = nil
    let remoteURL: URL?
    let revision: Int
    let highlighted: Bool
    @Environment(\.boardChrome) private var chrome

    private var shown: String { label ?? card.word }

    var body: some View {
        VStack(spacing: 0) {
            PecsImageView(image: image, remoteURL: remoteURL, placeholderSize: 28)
                .frame(maxWidth: .infinity)
                .frame(height: chrome.coreImageHeight)
                .background(backgroundColor ?? Theme.cream)

            Text(shown)
                .font(.system(size: chrome.coreTitleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: chrome.coreLabelHeight)
                .padding(.horizontal, 2)
                .background(Theme.labelWell)
        }
        .frame(maxWidth: .infinity)
        .frame(height: chrome.coreRowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(highlighted ? Theme.coral : Theme.cardStroke, lineWidth: highlighted ? 4 : 3)
        )
        .shadow(color: .black.opacity(0.16), radius: highlighted ? 6 : 3, y: 2)
        .id("core-\(card.slug)-\(revision)")
    }
}

struct StripChipView: View {
    let card: Card
    var label: String? = nil
    let image: UIImage?
    var remoteURL: URL? = nil
    @Environment(\.boardChrome) private var chrome

    private var shown: String { label ?? card.word }

    var body: some View {
        VStack(spacing: 0) {
            PecsImageView(image: image, remoteURL: remoteURL, placeholderSize: 22)
                .frame(width: chrome.chipWidth, height: chrome.chipImageHeight)

            Text(shown)
                .font(.system(size: chrome.stripLabelSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(width: chrome.chipWidth, height: chrome.chipLabelHeight)
                .background(Theme.labelWell)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 2)
        )
        .accessibilityLabel(shown)
    }
}

private enum BoardCellExpandsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var boardCellExpands: Bool {
        get { self[BoardCellExpandsKey.self] }
        set { self[BoardCellExpandsKey.self] = newValue }
    }
}

/// Manila-folder silhouette so folder buttons are distinct from word cells.
struct FolderTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tabHeight = max(10, min(rect.height * 0.11, 20))
        let tabWidth = min(rect.width * 0.42, 96)
        let corner = min(14, rect.width * 0.08, rect.height * 0.08)
        var path = Path()
        path.move(to: CGPoint(x: corner, y: tabHeight))
        path.addLine(to: CGPoint(x: tabWidth * 0.12, y: tabHeight))
        path.addQuadCurve(
            to: CGPoint(x: tabWidth * 0.20, y: tabHeight * 0.25),
            control: CGPoint(x: tabWidth * 0.12, y: tabHeight * 0.15)
        )
        path.addLine(to: CGPoint(x: tabWidth * 0.78, y: tabHeight * 0.25))
        path.addQuadCurve(
            to: CGPoint(x: tabWidth, y: tabHeight),
            control: CGPoint(x: tabWidth * 0.92, y: tabHeight * 0.15)
        )
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: tabHeight))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: tabHeight + corner),
            control: CGPoint(x: rect.maxX, y: tabHeight)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - corner, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: corner, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - corner),
            control: CGPoint(x: 0, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: 0, y: tabHeight + corner))
        path.addQuadCurve(
            to: CGPoint(x: corner, y: tabHeight),
            control: CGPoint(x: 0, y: tabHeight)
        )
        path.closeSubpath()
        return path
    }
}

struct FolderCell: View {
    let folder: BoardFolder
    var label: String? = nil
    var image: UIImage? = nil
    var remoteURL: URL? = nil
    var revision: Int = 0
    var backgroundColor: Color? = nil
    var borderColor: Color? = nil
    @Environment(\.boardChrome) private var chrome
    @Environment(\.boardCellExpands) private var expands

    private var shown: String { label ?? folder.name }
    private var lineWidth: CGFloat { chrome.isCompact ? 3 : 5 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if image != nil || remoteURL != nil {
                    PecsImageView(image: image, remoteURL: remoteURL, placeholderSize: 44)
                } else {
                    folderFallbackIcon
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: expands ? .infinity : nil)
            .aspectRatio(expands ? nil as CGFloat? : 1, contentMode: .fit)
            .padding(.top, 12)

            Text(shown)
                .font(.system(size: chrome.cellTitleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
                // One word shrinks to fit instead of breaking mid-word ("chocolat-e").
                .lineLimit(shown.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: chrome.cellLabelMinHeight)
                .padding(.horizontal, 6)
                // The label takes only the height it needs; the picture gets the rest.
                .fixedSize(horizontal: false, vertical: true)
                .background(Theme.labelWell)
        }
        .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil)
        .background(backgroundColor ?? Theme.cream)
        .clipShape(FolderTabShape())
        .overlay(
            FolderTabShape()
                .stroke(borderColor ?? Theme.cardStroke, lineWidth: lineWidth)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, y: 5)
        .id("folder-\(folder.id)-\(revision)")
        .accessibilityLabel("\(shown) folder")
    }

    private var folderFallbackIcon: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: chrome.isCompact ? 44 : 76, weight: .bold))
            .foregroundStyle(Theme.slate.opacity(0.82))
            .accessibilityHidden(true)
    }
}

struct CardCell: View {
    let card: Card
    var label: String? = nil
    let image: UIImage?
    let remoteURL: URL?
    let revision: Int
    let highlighted: Bool
    var backgroundColor: Color? = nil
    var borderColor: Color? = nil
    @Environment(\.boardChrome) private var chrome
    @Environment(\.boardCellExpands) private var expands

    private var shown: String { label ?? card.word }
    private var lineWidth: CGFloat {
        highlighted ? chrome.highlightStroke : (chrome.isCompact ? 3 : 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            PecsImageView(image: image, remoteURL: remoteURL, placeholderSize: 36)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: expands ? .infinity : nil)
                .aspectRatio(expands ? nil as CGFloat? : 1, contentMode: .fit)
                .background((backgroundColor ?? Theme.cream))

            Text(shown)
                .font(.system(size: chrome.cellTitleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
                // One word shrinks to fit instead of breaking mid-word ("chocolat-e").
                .lineLimit(shown.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: chrome.cellLabelMinHeight)
                .padding(.horizontal, 6)
                // The label takes only the height it needs; the picture gets the rest.
                .fixedSize(horizontal: false, vertical: true)
                .background(Theme.labelWell)
        }
        .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil)
        .background(backgroundColor ?? Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: chrome.isCompact ? 16 : 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: chrome.isCompact ? 16 : 22, style: .continuous)
                .stroke(
                    highlighted ? Theme.coral : (borderColor ?? Theme.cardStroke),
                    lineWidth: lineWidth
                )
        )
        .shadow(color: .black.opacity(0.18), radius: highlighted ? 8 : 5, y: 4)
        .id("\(card.slug)-\(revision)")
    }
}

/// Edit-only drag-and-drop onto grid cells. Kid mode never enables this.
private struct BoardReorderSupport: ViewModifier {
    let itemID: String
    let enabled: Bool
    @Binding var draggingItemID: String?
    let store: CardStore

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    draggingItemID = itemID
                    return NSItemProvider(object: itemID as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: BoardReorderDropDelegate(
                        targetID: itemID,
                        store: store,
                        draggingItemID: $draggingItemID
                    )
                )
        } else {
            content
        }
    }
}

private struct BoardReorderDropDelegate: DropDelegate {
    let targetID: String
    let store: CardStore
    @Binding var draggingItemID: String?

    func performDrop(info: DropInfo) -> Bool {
        draggingItemID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingItemID, draggingItemID != targetID else { return }
        store.moveCurrentItem(id: draggingItemID, before: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

#Preview("Empty board") {
    ContentView(store: CardStore())
}

#Preview("iPad") {
    ContentView(store: CardStore())
}
