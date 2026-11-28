import Foundation
import Observation
import UIKit

@Observable
final class CardStore {
    /// Probe slugs stripped from the visible board via the same local hide path.
    static let probeSlugs = ["hello-test-probe", "bubble"]

    var cards: [Card] = []
    var grouping = BoardGrouping.empty
    /// Local overlay: slugs hidden from every board/folder view until Unhide.
    var hiddenSlugs: Set<String> = []
    /// Local overlay: ordered `BoardItem.id`s per folder (empty key = root).
    var orderOverlays: [String: [String]] = [:]
    /// Local overlay: display labels keyed by card slug or folder id.
    var labelOverlays: [String: String] = [:]
    var positionOverlays: [String: [String: GridCoord]] = [:]
    var speakOverlays: [String: String] = [:]
    var styleOverlays: [String: CellStyle] = [:]
    var messageBar: MessageBarSettings = .default
    var settings: ProfileSettings = .default
    var importedDocument: BoardImportDocument?
    var importActions: [String: String] = [:]
    var importTargets: [String: String] = [:]
    var importAddToMessage: [String: Bool] = [:]
    /// Spoken slugs, most-recent-first, unique, capped at `recentsLimit`.
    private(set) var recentSlugs: [String] = []
    /// Folder ids from root to the open board. Empty means the root board.
    var folderPath: [String] = []
    var isLoading = false
    var isAdding = false
    var addingWord: String?
    var errorMessage: String?
    var banner: String?
    var lastSpokenSlug: String?
    /// Set by sync so it can tell when the board is in use. Not observed by views.
    @ObservationIgnored var onInteraction: (() -> Void)?
    var imageRevision: [String: Int] = [:]
    var strip = SentenceStrip()
    /// Caregiver search text. Filter is a view over `currentItems`; not persisted.
    var searchQuery: String = ""
    /// Active kid overlay. Board cards and PECS/MP3 cache are shared.
    private(set) var activeProfile: KidProfile
    /// Last `GET /v1/board` succeeded. Core POST bootstrap only runs after a live fetch.
    private(set) var lastBoardFetchSucceeded = false

    /// True when the current board (root or folder) has nothing to show.
    var showsEmptyBoard: Bool { currentItems.isEmpty }

    var isAtRoot: Bool { folderPath.isEmpty }

    /// Folder name for chrome. `nil` on the root board. Uses the display overlay when set.
    var currentFolderName: String? {
        if let title = importedBoardTitle, !isAtRoot { return title }
        guard let folder = currentFolder else { return nil }
        return displayLabel(for: folder)
    }

    var currentFolder: BoardFolder? {
        guard let id = folderPath.last else { return nil }
        if let folder = grouping.folder(id: id) { return folder }
        if let document = importedDocument,
           let board = document.boards.first(where: { $0.id == id }) {
            return BoardFolder(id: board.id, name: board.title, parentId: nil, memberSlugs: [])
        }
        return nil
    }

    /// Items on the open board after hide, then the local order overlay.
    /// Search does not change this list — Edit reorder and hide read it.
    var currentItems: [BoardItem] {
        if let document = importedDocument, let board = currentImportedBoard(in: document) {
            return board.cells.compactMap { cell in
                if cell.hidden { return nil }
                return boardItem(from: cell)
            }
        }
        let parentId = currentFolder?.id
        return Self.applyingOrder(membershipItems(parentId: parentId), saved: orderOverlays[Self.orderKey(folderId: parentId)])
    }

    /// `BoardItem.id`s on the open board, in the order the grid shows.
    var currentItemIDs: [String] { currentItems.map(\.id) }

    /// Current board after the caregiver search filter. Empty query equals `currentItems`.
    var filteredCurrentItems: [BoardItem] {
        Self.filtering(currentItems, query: searchQuery, displayLabel: { displayLabel(for: $0) })
    }

    /// Hidden vocabulary for the caregiver restore list. Sorted by word.
    var hiddenCards: [Card] {
        cards
            .filter { hiddenSlugs.contains($0.slug) }
            .sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    var hiddenListSlugs: [String] {
        hiddenCards.map(\.slug)
    }

    var currentWordSlugs: [String] {
        currentItems.compactMap {
            if case .word(let card) = $0 { return card.slug }
            return nil
        }
    }

    var currentFolderIds: [String] {
        currentItems.compactMap {
            if case .folder(let folder) = $0 { return folder.id }
            return nil
        }
    }

    /// Core strip in display order. Drawn from the full vocabulary, not `currentItems`,
    /// so opening Food (or any folder) cannot hide the six cores.
    var coreCards: [Card] {
        guard settings.showCoreRow else { return [] }
        return CoreVocabulary.resolved(from: cards)
    }

    var coreSlugs: [String] {
        coreCards.map(\.slug)
    }

    /// Max distinct words on the Recents row: one row of cells, the same width as the core row,
    /// so it fits any screen without scrolling.
    static let recentsLimit = 6

    /// Most recent first, one entry per word, never a core-row word, at most `recentsLimit`.
    /// Applied when a word is spoken, when Recents are read from disk and when they are saved,
    /// so a file written by an older version (8 entries, core words) is trimmed on load.
    nonisolated static func sanitizedRecents(_ slugs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for slug in slugs where !slug.isEmpty && !CoreVocabulary.slugs.contains(slug) {
            guard seen.insert(slug).inserted else { continue }
            result.append(slug)
            if result.count == recentsLimit { break }
        }
        return result
    }

    /// Recents in display order (most recent first). Missing vocabulary is skipped.
    var recentCards: [Card] {
        guard settings.showRecents else { return [] }
        let found = recentSlugs.compactMap { slug in
            cards.first { $0.slug == slug }
        }.filter { !CoreVocabulary.matches($0) }
        return Array(found.prefix(Self.recentsLimit))
    }

    let api: APIClient
    let cache: AssetCache
    private let player: SpeechPlayer
    @ObservationIgnored let thumbnails: ThumbnailCache
    @ObservationIgnored private var pendingThumbnailSlugs: Set<String> = []
    @ObservationIgnored private var thumbnailFlushScheduled = false
    @ObservationIgnored private var pendingBoardETags: [String: String] = [:]
    @ObservationIgnored private var didRevalidateAssets = false

    init(
        api: APIClient = .shared,
        cache: AssetCache = .shared,
        player: SpeechPlayer = .shared,
        profile: KidProfile = .child1,
        thumbnails: ThumbnailCache = .shared
    ) {
        self.api = api
        self.cache = cache
        self.player = player
        self.thumbnails = thumbnails
        self.activeProfile = profile
        grouping = cache.loadGrouping() ?? .empty
        hiddenSlugs = cache.loadHiddenSlugs(for: profile)
        orderOverlays = cache.loadOrderOverlays(for: profile)
        labelOverlays = cache.loadLabelOverlays(for: profile)
        positionOverlays = cache.loadPositionOverlays(for: profile)
        speakOverlays = cache.loadSpeakOverlays(for: profile)
        styleOverlays = cache.loadStyleOverlays(for: profile)
        messageBar = cache.loadMessageBarSettings(for: profile)
        settings = cache.loadProfileSettings(for: profile)
        recentSlugs = Self.sanitizedRecents(cache.loadRecents(for: profile))
        folderPath = clampedFolderPath(cache.loadFolderPath(for: profile))
        loadImportedBoardIfPresent()
        if hasImportedBoard {
            let cached = cache.loadCachedCards()
            if !cached.isEmpty { cards = cached }
            messageBar = settings.messageBar
        }
    }

    /// Re-read this profile's hide, order, label, position, spoken-text and color overlays.
    /// Sync calls this after it writes an update from another device.
    func reloadOverlaysFromDisk() {
        hiddenSlugs = cache.loadHiddenSlugs(for: activeProfile)
        orderOverlays = cache.loadOrderOverlays(for: activeProfile)
        labelOverlays = cache.loadLabelOverlays(for: activeProfile)
        positionOverlays = cache.loadPositionOverlays(for: activeProfile)
        speakOverlays = cache.loadSpeakOverlays(for: activeProfile)
        styleOverlays = cache.loadStyleOverlays(for: activeProfile)
        folderPath = clampedFolderPath(folderPath)
    }

    /// Same path the caregiver profile switcher uses. Reloads this profile's
    /// hide list, order, labels, recents, and folder path. Clears the sentence strip.
    /// Recents are not wiped. Does not refetch the server board or touch cached PECS/MP3 files.
    func switchToProfile(_ profile: KidProfile) {
        guard profile != activeProfile else { return }
        activeProfile = profile
        reloadOverlaysFromDisk()
        messageBar = cache.loadMessageBarSettings(for: profile)
        settings = cache.loadProfileSettings(for: profile)
        recentSlugs = Self.sanitizedRecents(cache.loadRecents(for: profile))
        folderPath = clampedFolderPath(cache.loadFolderPath(for: profile))
        loadImportedBoardIfPresent()
        if hasImportedBoard {
            let cached = cache.loadCachedCards()
            if !cached.isEmpty { cards = cached }
            grouping = cache.loadGrouping() ?? grouping
            messageBar = settings.messageBar
        }
        strip.clear()
        lastSpokenSlug = nil
        applyProbeHides()
    }

    func bootstrap() async {
        if ProcessInfo.processInfo.arguments.contains("-UIEmptyBoard") {
            cards = []
            grouping = .empty
            folderPath = []
            return
        }
        let cached = cache.loadCachedCards()
        if !cached.isEmpty {
            cards = cached
        }
        applyProbeHides()
        prefetchThumbnails()
        player.warmUp()
        if hasImportedBoard { return }
        await refresh()
        await ensureCoreVocabulary()
    }

    /// Tests and launch-arg hooks seed the same tree the UI navigates.
    func seedLocalBoard(cards: [Card], folders: [BoardFolder]) {
        self.cards = cards
        grouping = BoardGrouping(folders: folders)
        folderPath = []
        cache.saveCards(cards)
        cache.saveGrouping(grouping)
        persistFolderPath()
        prefetchThumbnails()
    }

    func refresh() async {
        if hasImportedBoard { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let previousCards = cards
        let previousGrouping = grouping
        do {
            // Always already on screen from the cached snapshot. This only asks the server
            // whether anything changed (If-None-Match); a 304 costs one tiny round trip.
            let folderId = folderPath.last
            switch try await fetchBoardIfChanged(folderId: folderId) {
            case .updated(let board):
                applyBoard(board)
            case .unchanged:
                break
            }
            applyProbeHides()
            lastBoardFetchSucceeded = true
            if isAtRoot {
                await prefetchChildBoards()
            }
            await prefetchAssets()
        } catch {
            lastBoardFetchSucceeded = false
            // Failed GET must not wipe a warm board or its on-device assets.
            cards = previousCards
            grouping = previousGrouping
            if cards.isEmpty && grouping.folders.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            } else {
                banner = "Offline — showing saved cards."
            }
        }
    }

    @discardableResult
    func addWord(_ raw: String) async -> Card? {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        isAdding = true
        addingWord = word
        errorMessage = nil
        banner = "Making a picture and voice for “\(word)”…"
        defer {
            isAdding = false
            addingWord = nil
        }
        do {
            let card = try await api.createCard(word: word, folderId: currentFolder?.id)
            integrateNewCard(card)
            await cache.ensureAssets(for: card, api: api)
            bumpImage(card.slug)
            banner = "“\(card.word)” is on the board."
            preview(card)
            await refresh()
            return card
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            banner = nil
            return nil
        }
    }

    @discardableResult
    func addFolder(_ raw: String) async -> BoardFolder? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        isAdding = true
        errorMessage = nil
        banner = "Making a folder named “\(name)”…"
        defer { isAdding = false }
        do {
            let folder = try await api.createFolder(name: name)
            upsertFolder(folder.asFolder(parentId: folderPath.last))
            persistSnapshot()
            banner = "Folder “\(folder.displayName)” is on the board."
            await refresh()
            return folder.asFolder(parentId: folderPath.last)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            banner = nil
            return nil
        }
    }

    /// Server Delete (forever). Not Hide. Clears this slug's on-device assets, then refreshes.
    func deleteCardAfterConfirm(_ slug: String) async {
        guard !slug.isEmpty else { return }
        errorMessage = nil
        do {
            try await api.deleteCard(slug: slug)
            cache.removeAssets(for: slug)
            cards.removeAll { $0.slug == slug }
            hiddenSlugs.remove(slug)
            persistHidden()
            var next = grouping
            next.remove(slug: slug)
            grouping = next
            persistSnapshot()
            await refresh()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Server delete folder. Children move to root on the server, then we refresh.
    func deleteFolderAfterConfirm(_ slug: String) async {
        guard !slug.isEmpty else { return }
        errorMessage = nil
        do {
            try await api.deleteFolder(slug: slug)
            if folderPath.contains(slug) {
                folderPath.removeAll()
                persistFolderPath()
            }
            var next = grouping
            next.removeFolder(id: slug)
            grouping = next
            persistSnapshot()
            await refresh()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func tap(_ card: Card) {
        onInteraction?()
        strip.append(card)
        if messageBar.speakOnTap {
            preview(card)
        }
        recordSpoken(slugs: [card.slug])
    }

    /// Same path a grid word cell uses. Core-row buttons call this.
    func tapCore(_ card: Card) {
        onInteraction?()
        tap(card)
    }

    /// Same path a board/core tap uses: append to the strip and play cached MP3.
    func tapRecent(_ card: Card) {
        onInteraction?()
        tap(card)
    }

    /// After a successful live GET, POST any core that is not already a server card
    /// to **root** (`{ "word" }` — no `folder_id`). Prefer cards already loaded.
    func ensureCoreVocabulary() async {
        guard lastBoardFetchSucceeded else { return }
        var missing = CoreVocabulary.missing(from: cards)
        guard !missing.isEmpty else { return }

        do {
            let remote = try await api.fetchCards()
            for card in remote where CoreVocabulary.matches(card) {
                if cards.contains(where: { $0.slug == card.slug }) { continue }
                upsert(card)
            }
            persistSnapshot()
        } catch {
            // Fall through to POST for whatever is still missing.
        }

        missing = CoreVocabulary.missing(from: cards)
        for entry in missing {
            do {
                let card = try await api.createCard(word: entry.word, folderId: nil)
                upsert(card)
                persistSnapshot()
                await cache.ensureAssets(for: card, api: api)
                bumpImage(card.slug)
            } catch {
                if case APIError.http(409, _) = error {
                    await mergeRemoteCores()
                }
                // Do not surface a board-blocking error: cores are a bootstrap, not Add.
            }
        }
    }

    private func mergeRemoteCores() async {
        do {
            let remote = try await api.fetchCards()
            for card in remote where CoreVocabulary.matches(card) {
                upsert(card)
            }
            persistSnapshot()
        } catch {
            // Keep whatever we already have.
        }
    }

    /// Same path the board cells use: words append, folders navigate.
    func select(_ item: BoardItem) {
        onInteraction?()
        if selectImported(item) { return }
        switch item {
        case .word(let card):
            tap(card)
        case .folder(let folder):
            openFolder(folder)
        }
    }

    func openFolder(_ folder: BoardFolder) {
        onInteraction?()
        openFolder(id: folder.id)
    }

    func openFolder(id: String) {
        onInteraction?()
        let stripped = id.hasPrefix("folder:") ? String(id.dropFirst("folder:".count)) : id
        let resolved = importTargets[id] ?? importTargets[stripped] ?? stripped
        let exists = grouping.folder(id: resolved) != nil
            || (importedDocument?.boards.contains(where: { $0.id == resolved }) ?? false)
        guard exists else { return }
        if importedDocument?.profile.homeBoard == resolved {
            goHome()
            return
        }
        if folderPath.last == resolved { return }
        folderPath.append(resolved)
        persistFolderPath()
    }

    func goBack() {
        onInteraction?()
        guard !folderPath.isEmpty else { return }
        folderPath.removeLast()
        persistFolderPath()
    }

    func goHome() {
        onInteraction?()
        folderPath.removeAll()
        persistFolderPath()
    }

    /// Same path the Edit confirm button uses. Local only — no DELETE/PATCH.
    func hideAfterConfirm(_ slug: String) {
        guard !slug.isEmpty else { return }
        hiddenSlugs.insert(slug)
        persistHidden()
    }

    /// Same path the Hidden list Unhide button uses.
    func unhide(_ slug: String) {
        hiddenSlugs.remove(slug)
        persistHidden()
    }

    /// Same path Edit drag uses. Local overlay only — no order API.
    func reorderCurrentItems(ids: [String]) {
        orderOverlays[Self.orderKey(folderId: currentFolder?.id)] = ids
        persistOrder()
    }

    /// Same path a drop-on-cell uses while dragging in Edit.
    func moveCurrentItem(id: String, before targetId: String) {
        var ids = currentItemIDs
        guard let from = ids.firstIndex(of: id),
              ids.contains(targetId),
              id != targetId else { return }
        let key = currentFolderKey
        if var folderMap = positionOverlays[key],
           let origin = folderMap[id],
           let destCoord = folderMap[targetId] {
            folderMap[id] = destCoord
            folderMap[targetId] = origin
            positionOverlays[key] = folderMap
            persistPositions()
        }
        ids.remove(at: from)
        let dest = ids.firstIndex(of: targetId) ?? ids.endIndex
        ids.insert(id, at: dest)
        reorderCurrentItems(ids: ids)
    }

    /// Same path Edit rename Save uses. Empty string clears the overlay.
    /// Local only — does not PATCH `/v1/cards`.
    func setDisplayLabel(_ raw: String, for slug: String) {
        guard !slug.isEmpty else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            labelOverlays.removeValue(forKey: slug)
        } else {
            labelOverlays[slug] = trimmed
        }
        persistLabels()
    }

    /// Same path the search field and `-SearchQuery` launch hook use.
    func setSearchQuery(_ raw: String) {
        searchQuery = raw
    }

    /// Grid and strip chip label. Overlay if set, otherwise server `word`.
    func displayLabel(for card: Card) -> String {
        displayLabel(slug: card.slug, fallback: card.word)
    }

    /// Grid and folder-chrome label. Overlay if set, otherwise server `name`.
    func displayLabel(for folder: BoardFolder) -> String {
        displayLabel(slug: folder.id, fallback: folder.name)
    }

    func displayLabel(for item: BoardItem) -> String {
        switch item {
        case .word(let card):
            return displayLabel(for: card)
        case .folder(let folder):
            return displayLabel(for: folder)
        }
    }

    /// Hide probe cards through the same persist path when they exist on the board.
    func applyProbeHides() {
        for slug in Self.probeSlugs where cards.contains(where: { $0.slug == slug }) {
            hideAfterConfirm(slug)
        }
    }

    /// After a successful POST, put the card in the vocabulary and on the current board.
    func integrateNewCard(_ card: Card) {
        upsert(card)
        var next = grouping
        next.add(slug: card.slug, to: currentFolder?.id)
        grouping = next
        persistSnapshot()
    }

    func applyVoiceSettings() {
        player.voiceSettings = settings.voice
    }

    func preview(_ card: Card) {

        lastSpokenSlug = card.slug
        player.speak(card: card, spokenText: speakText(for: card), cache: cache, api: api)
        Task { await cache.ensureAssets(for: card, api: api) }
    }

    func speakStrip() {
        onInteraction?()
        guard !strip.isEmpty else { return }
        lastSpokenSlug = strip.cards.first?.slug
        let texts = strip.cards.map { speakText(for: $0) }
        player.speakSequence(strip.cards, spokenTexts: texts, cache: cache, api: api)
        recordSpoken(slugs: strip.cards.map(\.slug))
        if messageBar.clearAfterSpeak {
            clearStrip()
        }
    }

    func backspaceStrip() {
        onInteraction?()
        strip.backspace()
    }

    func clearStrip() {
        onInteraction?()
        strip.clear()
        lastSpokenSlug = nil
    }

    func appendSlugsFromBoard(_ slugs: [String]) {
        onInteraction?()
        for slug in slugs {
            if let card = cards.first(where: { $0.slug == slug }) {
                strip.append(card)
            }
        }
    }

    /// Trimmed, downsampled picture for a card, from memory only. `nil` while it is still
    /// loading in the background; the grid redraws when it lands (see `thumbnailDidLoad`).
    func image(for card: Card) -> UIImage? {
        thumbnail(slug: card.slug)
    }

    func image(for folder: BoardFolder) -> UIImage? {
        thumbnail(slug: folder.id)
    }

    private func thumbnail(slug: String) -> UIImage? {
        thumbnails.thumbnail(for: cache.imageURL(for: slug)) { [weak self] in
            Task { @MainActor in self?.thumbnailDidLoad(slug) }
        }
    }

    /// Several pictures usually land together. Redraw once per burst, not once per picture.
    private func thumbnailDidLoad(_ slug: String) {
        pendingThumbnailSlugs.insert(slug)
        guard !thumbnailFlushScheduled else { return }
        thumbnailFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self else { return }
            self.thumbnailFlushScheduled = false
            let slugs = self.pendingThumbnailSlugs
            self.pendingThumbnailSlugs = []
            var next = self.imageRevision
            for slug in slugs { next[slug, default: 0] += 1 }
            self.imageRevision = next
        }
    }

    /// Start decoding pictures for the cards on screen and the core row before they are drawn.
    func prefetchThumbnails(limit: Int = 60) {
        var slugs: [String] = coreCards.map(\.slug)
        for item in currentItems.prefix(limit) {
            switch item {
            case .word(let card): slugs.append(card.slug)
            case .folder(let folder): slugs.append(folder.id)
            }
        }
        thumbnails.prefetch(slugs.map { cache.imageURL(for: $0) })
    }

    /// Remote fallback only while nothing is on disk. With a cached picture the grid waits for
    /// the background thumbnail instead of starting a network fetch.
    func remoteImageURL(for card: Card) -> URL? {
        guard !cache.hasImage(card.slug) else { return nil }
        return api.absoluteURL(for: card.imageURL)
    }

    func remoteImageURL(for folder: BoardFolder) -> URL? {
        guard let path = folder.imageURL, !path.isEmpty, !cache.hasImage(folder.id) else { return nil }
        return api.absoluteURL(for: path)
    }

    /// Apply a successful CONTRACT board payload as the source of truth for that folder.
    func applyBoard(_ board: BoardResponse) {
        let parentId = board.folderId
        var nextCards = Dictionary(uniqueKeysWithValues: cards.map { ($0.slug, $0) })
        var nextFolders = Dictionary(uniqueKeysWithValues: grouping.folders.map { ($0.id, $0) })

        var wordSlugs: [String] = []
        var folderSlugs: [String] = []

        for item in board.items {
            switch item.kind {
            case .folder:
                folderSlugs.append(item.slug)
                nextFolders[item.slug] = item.asFolder(parentId: parentId)
            case .word:
                wordSlugs.append(item.slug)
                nextCards[item.slug] = item.asCard()
            }
        }

        if let parentId {
            if var folder = nextFolders[parentId] {
                folder.memberSlugs = wordSlugs
                nextFolders[parentId] = folder
            }
            let previousMembers = grouping.folder(id: parentId)?.memberSlugs ?? []
            for slug in previousMembers where !wordSlugs.contains(slug) {
                nextCards.removeValue(forKey: slug)
            }
            for (id, folder) in nextFolders where folder.parentId == parentId && !folderSlugs.contains(id) {
                nextFolders.removeValue(forKey: id)
            }
        } else {
            let previousRoot = cards
                .map(\.slug)
                .filter { !grouping.allMemberSlugs.contains($0) }
            for slug in previousRoot where !wordSlugs.contains(slug) {
                nextCards.removeValue(forKey: slug)
            }
            for (id, folder) in nextFolders where folder.parentId == nil && !folderSlugs.contains(id) {
                nextFolders.removeValue(forKey: id)
            }
        }

        cards = nextCards.values.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        grouping = BoardGrouping(folders: Array(nextFolders.values))
        folderPath = clampedFolderPath(folderPath)
        persistSnapshot()
        persistFolderPath()
        cache.saveBoard(board)
        cache.saveBoardETag(pendingBoardETags.removeValue(forKey: parentId ?? ""), folderId: parentId)
    }

    private func upsert(_ card: Card) {
        if let idx = cards.firstIndex(where: { $0.slug == card.slug }) {
            cards[idx] = card
        } else {
            cards.append(card)
            cards.sort { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        }
    }

    private func upsertFolder(_ folder: BoardFolder) {
        var next = grouping
        if let idx = next.folders.firstIndex(where: { $0.id == folder.id }) {
            next.folders[idx] = folder
        } else {
            next.folders.append(folder)
        }
        grouping = next
    }

    func persistSnapshot() {
        cache.saveCards(cards)
        cache.saveGrouping(grouping)
    }

    private func persistHidden() {
        cache.saveHiddenSlugs(hiddenSlugs, for: activeProfile)
    }

    private func persistOrder() {
        cache.saveOrderOverlays(orderOverlays, for: activeProfile)
    }

    func persistLabels() {
        cache.saveLabelOverlays(labelOverlays, for: activeProfile)
    }

    private func persistRecents() {
        cache.saveRecents(recentSlugs, for: activeProfile)
    }

    /// Counting events: grid tap, core-row tap, Recents tap (via `tap`), and
    /// sentence-strip Speak. Folder taps do not count. Unique by slug, insert
    /// front, cap `recentsLimit`, core-row words skipped. Speak of `[I, want, juice, ice cream]` → `ice-cream, juice`.
    func recordSpoken(slugs: [String]) {
        var next = recentSlugs
        for slug in slugs where !slug.isEmpty {
            next.removeAll { $0 == slug }
            next.insert(slug, at: 0)
        }
        recentSlugs = Self.sanitizedRecents(next)
        persistRecents()
    }

    func persistFolderPath() {
        cache.saveFolderPath(folderPath, for: activeProfile)
    }

    /// Membership of the open board after hide, before the order overlay.
    /// Default is folders first (name), then word cards.
    func membershipItems(parentId: String?) -> [BoardItem] {
        let folderItems = grouping.folders(parentId: parentId).map { BoardItem.folder($0) }
        let wordItems: [BoardItem]
        if let parentId, let folder = grouping.folder(id: parentId) {
            wordItems = folder.memberSlugs.compactMap { slug in
                cards.first { $0.slug == slug }.map { BoardItem.word($0) }
            }
        } else {
            let grouped = grouping.allMemberSlugs
            wordItems = cards
                .filter { !grouped.contains($0.slug) }
                .map { BoardItem.word($0) }
        }
        return (folderItems + wordItems).filter { item in
            if case .word(let card) = item {
                return !hiddenSlugs.contains(card.slug)
            }
            return true
        }
    }

    /// Case-insensitive substring over display label, server word/name, and slug/id.
    /// Scoped to `items` (the current board). Does not pull children onto root.
    static func filtering(_ items: [BoardItem], query: String, displayLabel: (BoardItem) -> String) -> [BoardItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter { itemMatches($0, query: needle, displayLabel: displayLabel($0)) }
    }

    static func itemMatches(_ item: BoardItem, query: String, displayLabel: String) -> Bool {
        func matches(_ value: String) -> Bool {
            value.localizedCaseInsensitiveContains(query)
        }
        if matches(displayLabel) { return true }
        switch item {
        case .word(let card):
            return matches(card.word) || matches(card.slug)
        case .folder(let folder):
            return matches(folder.name) || matches(folder.id)
        }
    }

    /// Re-apply a saved order after hide/refresh. Unknown ids drop; new members append.
    static func applyingOrder(_ items: [BoardItem], saved: [String]?) -> [BoardItem] {
        guard let saved, !saved.isEmpty else { return items }
        var remaining = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result: [BoardItem] = []
        result.reserveCapacity(items.count)
        for id in saved {
            if let item = remaining.removeValue(forKey: id) {
                result.append(item)
            }
        }
        for item in items where remaining[item.id] != nil {
            result.append(item)
            remaining.removeValue(forKey: item.id)
        }
        return result
    }

    static func orderKey(folderId: String?) -> String {
        folderId ?? ""
    }

    private func displayLabel(slug: String, fallback: String) -> String {
        let overlay = labelOverlays[slug]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let overlay, !overlay.isEmpty { return overlay }
        return fallback
    }

    private func clampedFolderPath(_ stored: [String]) -> [String] {
        if grouping.folders.isEmpty {
            return stored
        }
        var valid: [String] = []
        for id in stored {
            guard grouping.folder(id: id) != nil else { break }
            valid.append(id)
        }
        return valid
    }

    func bumpImage(_ slug: String) {
        imageRevision[slug, default: 0] += 1
    }

    private enum BoardRefresh {
        case updated(BoardResponse)
        case unchanged
    }

    /// Conditional board fetch. The validator is only sent when a snapshot of that folder is on
    /// disk and the in-memory board is not empty, so a 304 can never leave the screen blank.
    private func fetchBoardIfChanged(folderId: String?) async throws -> BoardRefresh {
        var validator: String?
        if let known = cache.boardETag(folderId: folderId), cache.loadBoard(folderId: folderId) != nil,
           !(cards.isEmpty && grouping.folders.isEmpty) {
            validator = known
        }
        switch try await api.fetchBoard(folderId: folderId, ifNoneMatch: validator) {
        case .notModified:
            return .unchanged
        case .modified(let board, let etag):
            // The validator is saved after the board snapshot (applyBoard saves it) so the two never disagree.
            pendingBoardETags[folderId ?? ""] = etag
            return .updated(board)
        }
    }

    private func prefetchChildBoards() async {
        let children = grouping.folders(parentId: nil)
        for folder in children {
            do {
                if case .updated(let board) = try await fetchBoardIfChanged(folderId: folder.id) {
                    applyBoard(board)
                }
            } catch {
                // Keep the last cached child snapshot. Root fetch already succeeded.
            }
        }
    }

    private func prefetchAssets() async {
        // Once per launch, ask the server whether pictures and voices we already have changed.
        let revalidate = !didRevalidateAssets
        didRevalidateAssets = true
        let changed = await withTaskGroup(of: String?.self) { group -> [String] in
            for card in cards {
                group.addTask { [cache, api] in
                    await cache.ensureAssets(for: card, api: api, revalidate: revalidate) ? card.slug : nil
                }
            }
            for folder in grouping.folders {
                group.addTask { [cache, api] in
                    await cache.ensureAssets(for: folder, api: api, revalidate: revalidate) ? folder.id : nil
                }
            }
            var slugs: [String] = []
            for await slug in group {
                if let slug { slugs.append(slug) }
            }
            return slugs
        }
        // Redraw only the pictures that actually changed, in one update.
        guard !changed.isEmpty else { return }
        var next = imageRevision
        for slug in changed { next[slug, default: 0] += 1 }
        imageRevision = next
    }
}
