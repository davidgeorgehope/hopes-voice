import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: CardStore
    @State var mode: CaregiverMode
    @State var profiles: ProfileStore
    @State var grid: GridLayout
    @State private var draft = ""
    @State private var pendingHide: Card?
    @State private var pendingDelete: Card?
    @State private var pendingDeleteFolder: BoardFolder?
    @State private var pendingRenameSlug: String?
    @State private var pendingRenameFallback = ""
    @State private var renameDraft = ""
    @State private var draggingItemID: String?
    @State private var showingHidden = false
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
        grid: GridLayout? = nil
    ) {
        self.store = store
        _mode = State(initialValue: mode)
        _profiles = State(initialValue: profiles)
        _grid = State(initialValue: grid ?? GridLayout(profile: profiles.active))
    }

    var body: some View {
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
        .background(Theme.board.ignoresSafeArea())
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: BoardWidthPreference.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(BoardWidthPreference.self) { viewWidth = $0 }
        .environment(\.boardChrome, chrome)
        .task { await store.bootstrap() }
        .onAppear { consumeLaunchArguments() }
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
            HStack(spacing: 16) {
                folderNav
                title
                Spacer(minLength: 8)
                if mode.showsAddChrome {
                    caregiverTools
                }
            }
            if mode.showsProfileSwitcher {
                profileSwitcher
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if mode.showsAddChrome {
                addChrome
            }
            if mode.showsSearchChrome {
                searchChrome
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, mode.showsAddChrome ? 16 : 14)
        .background(Theme.slate)
    }

    private var caregiverTools: some View {
        HStack(spacing: 12) {
            if mode.showsEditButton {
                Button {
                    if mode.isEditing {
                        mode.exitEdit()
                    } else {
                        showingHidden = false
                        mode.enterEdit()
                    }
                } label: {
                    Text(mode.isEditing ? "Done" : "Edit")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .frame(minWidth: 88, minHeight: 56)
                        .foregroundStyle(Theme.cream)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(mode.isEditing ? Theme.coral : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Theme.cream.opacity(0.65), lineWidth: 3)
                                )
                        )
                }
                .accessibilityLabel(mode.isEditing ? "Done editing" : "Edit board")
                .accessibilityIdentifier(mode.isEditing ? "doneEditing" : "editBoard")
            }

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

            Button {
                fieldFocused = false
                searchFieldFocused = false
                draft = ""
                store.setSearchQuery("")
                showingHidden = false
                pendingHide = nil
                pendingVoiceWord = nil
                voice.cancel()
                mode.lock()
            } label: {
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

    /// Caregiver-only 2 / 3 / 4 column control. Kid mode still uses `grid.columnCount`.
    private var gridPicker: some View {
        HStack(spacing: 6) {
            ForEach(GridLayout.allowedCounts, id: \.self) { count in
                Button {
                    grid.setColumnCount(count)
                } label: {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .frame(minWidth: 48, minHeight: 56)
                        .foregroundStyle(Theme.cream)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(grid.columnCount == count ? Theme.coral : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Theme.cream.opacity(0.65), lineWidth: 3)
                                )
                        )
                }
                .accessibilityLabel("\(count) columns")
                .accessibilityIdentifier("gridColumns-\(count)")
                .accessibilityAddTraits(grid.columnCount == count ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Grid columns")
        .accessibilityIdentifier("gridColumns")
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
                .font(.system(.title2, design: .rounded).weight(.heavy))
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
            mode.unlock()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("boardTitle")
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Hold to unlock caregiver tools")
    }

    private var addChrome: some View {
        HStack(spacing: 16) {
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: chrome.coreSpacing) {
                ForEach(store.recentCards) { card in
                    Button {
                        store.tapRecent(card)
                    } label: {
                        CoreWordCell(
                            card: card,
                            label: store.displayLabel(for: card),
                            image: store.image(for: card),
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
            }
            .padding(.horizontal, chrome.corePadding)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: chrome.coreRowHeight + 16)
        .background(Theme.slate)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recents")
        .accessibilityIdentifier("recentsRow")
    }

    private var board: some View {
        ScrollView {
            if store.showsEmptyBoard {
                emptyBoard
                    .padding(.top, 48)
            } else {
                LazyVGrid(columns: chrome.gridItems, spacing: chrome.gridSpacing) {
                    ForEach(visibleBoardItems) { item in
                        boardCell(item)
                    }
                }
                .padding(.horizontal, chrome.gridPadding)
                .padding(.vertical, chrome.gridPadding + chrome.highlightStroke)
            }
        }
        .refreshable { await store.refresh() }
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

    private var sentenceStrip: some View {
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
            .accessibilityIdentifier("sentenceStrip")

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
    private func boardCell(_ item: BoardItem) -> some View {
        let label = store.displayLabel(for: item)
        switch item {
        case .word(let card):
            ZStack(alignment: .topTrailing) {
                CardCell(
                    card: card,
                    label: label,
                    image: store.image(for: card),
                    remoteURL: store.remoteImageURL(for: card),
                    revision: store.imageRevision[card.slug, default: 0],
                    highlighted: store.lastSpokenSlug == card.slug
                )
                if mode.showsEditChrome {
                    editChrome(for: item, label: label)
                }
            }
            .overlay(alignment: .topLeading) {
                if mode.showsEditChrome {
                    dragHandle(itemID: item.id)
                        .padding(12)
                }
            }
            .onTapGesture { store.select(item) }
            .modifier(BoardReorderSupport(
                itemID: item.id,
                enabled: mode.showsEditChrome,
                draggingItemID: $draggingItemID,
                store: store
            ))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityHint("Adds this word to the sentence")
        case .folder(let folder):
            ZStack(alignment: .topTrailing) {
                FolderCell(
                    folder: folder,
                    label: label,
                    image: store.image(for: folder),
                    remoteURL: store.remoteImageURL(for: folder),
                    revision: store.imageRevision[folder.id, default: 0]
                )
                if mode.showsEditChrome {
                    editChrome(for: item, label: label)
                }
            }
            .overlay(alignment: .topLeading) {
                if mode.showsEditChrome {
                    dragHandle(itemID: item.id)
                        .padding(.leading, 12)
                        .padding(.top, 52)
                }
            }
            .onTapGesture {
                store.select(item)
                Task { await store.refresh() }
            }
            .modifier(BoardReorderSupport(
                itemID: item.id,
                enabled: mode.showsEditChrome,
                draggingItemID: $draggingItemID,
                store: store
            ))
            .accessibilityAddTraits(.isButton)
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

    private func consumeLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        mode.applyLaunchArguments(args)
        profiles.applyLaunchArguments(args, overlay: store, grid: grid)
        grid.applyLaunchArguments(args)
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
        if let idx = args.firstIndex(of: "-OpenFolder"), args.indices.contains(idx + 1) {
            let folderId = args[idx + 1]
            Task { await runFolderLaunchHooks(folderId: folderId) }
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

struct FolderCell: View {
    let folder: BoardFolder
    var label: String? = nil
    var image: UIImage? = nil
    var remoteURL: URL? = nil
    var revision: Int = 0
    @Environment(\.boardChrome) private var chrome

    private var shown: String { label ?? folder.name }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if image != nil || remoteURL != nil {
                    PecsImageView(image: image, remoteURL: remoteURL, placeholderSize: 44)
                } else {
                    Theme.cream
                    folderFallbackIcon
                }
            }
            .overlay(alignment: .topLeading) {
                Text("folder")
                    .font(.system(size: chrome.isCompact ? 11 : 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, chrome.isCompact ? 8 : 12)
                    .padding(.vertical, chrome.isCompact ? 4 : 6)
                    .background(Theme.coral)
                    .clipShape(Capsule())
                    .padding(chrome.isCompact ? 6 : 12)
                    .accessibilityHidden(true)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Theme.cream)

            Text(shown)
                .font(.system(size: chrome.cellTitleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: chrome.cellLabelMinHeight)
                .padding(.horizontal, 6)
                .background(Theme.labelWell)
        }
        .clipShape(RoundedRectangle(cornerRadius: chrome.isCompact ? 16 : 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: chrome.isCompact ? 16 : 22, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: chrome.isCompact ? 3 : 5)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, y: 5)
        .id("folder-\(folder.id)-\(revision)")
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
    @Environment(\.boardChrome) private var chrome

    private var shown: String { label ?? card.word }

    var body: some View {
        VStack(spacing: 0) {
            PecsImageView(image: image, remoteURL: remoteURL, placeholderSize: 36)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Theme.cream)

            Text(shown)
                .font(.system(size: chrome.cellTitleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: chrome.cellLabelMinHeight)
                .padding(.horizontal, 6)
                .background(Theme.labelWell)
        }
        .clipShape(RoundedRectangle(cornerRadius: chrome.isCompact ? 16 : 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: chrome.isCompact ? 16 : 22, style: .continuous)
                .stroke(
                    highlighted ? Theme.coral : Theme.cardStroke,
                    lineWidth: highlighted ? chrome.highlightStroke : (chrome.isCompact ? 3 : 5)
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
