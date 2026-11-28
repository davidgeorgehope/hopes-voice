import Foundation
import UIKit
import os

/// Disk cache for PECS images, MP3s, and the last successful board snapshot.
final class AssetCache: Sendable {
    static let shared = AssetCache()

    private let root: URL
    private let cardsIndexURL: URL
    private let groupingURL: URL
    private let hiddenURL: URL
    private let boardsURL: URL
    private let fileManager = FileManager.default
    private let changeState = OSAllocatedUnfairLock(initialState: ChangeState())

    private struct ChangeState {
        var observer: (@Sendable (KidProfile?) -> Void)?
        var mutedDepth = 0
    }

    var rootURL: URL { root }

    /// Called after a local edit is written (`nil` profile = a picture, shared by every profile).
    /// Sync uses this to know when to push. Writes made by sync itself are muted.
    func setChangeObserver(_ observer: (@Sendable (KidProfile?) -> Void)?) {
        changeState.withLock { $0.observer = observer }
    }

    func withoutChangeNotifications<T>(_ body: () throws -> T) rethrows -> T {
        changeState.withLock { $0.mutedDepth += 1 }
        defer { changeState.withLock { $0.mutedDepth -= 1 } }
        return try body()
    }

    private func noteChange(_ profile: KidProfile?) {
        let observer = changeState.withLock { $0.mutedDepth == 0 ? $0.observer : nil }
        observer?(profile)
    }

    init(root: URL? = nil) {
        let resolved: URL
        if let root {
            resolved = root
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            resolved = base.appendingPathComponent("BestWishes", isDirectory: true)
        }
        self.root = resolved
        cardsIndexURL = resolved.appendingPathComponent("cards.json")
        groupingURL = resolved.appendingPathComponent("grouping.json")
        hiddenURL = resolved.appendingPathComponent("hidden.json")
        boardsURL = resolved.appendingPathComponent("boards.json")
        try? fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
    }

    func directory(for slug: String) -> URL {
        root.appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
    }

    func imageURL(for slug: String) -> URL {
        directory(for: slug).appendingPathComponent("image.png")
    }

    func audioURL(for slug: String) -> URL {
        directory(for: slug).appendingPathComponent("audio.mp3")
    }

    func hasImage(_ slug: String) -> Bool {
        fileManager.fileExists(atPath: imageURL(for: slug).path)
    }

    func hasAudio(_ slug: String) -> Bool {
        fileManager.fileExists(atPath: audioURL(for: slug).path)
    }

    func loadImage(_ slug: String) -> UIImage? {
        UIImage(contentsOfFile: imageURL(for: slug).path)
    }

    func localImageMarkerURL(for slug: String) -> URL {
        directory(for: slug).appendingPathComponent("image.local")
    }

    /// True when the caregiver chose an on-device photo. Remote fetches must not overwrite it.
    func isLocalImage(_ slug: String) -> Bool {
        fileManager.fileExists(atPath: localImageMarkerURL(for: slug).path)
    }

    /// Write a caregiver photo (or a trimmed generated replacement) and mark it on-device only.
    @discardableResult
    func saveLocalImage(_ image: UIImage, for slug: String) -> Bool {
        defer { noteChange(nil) }
        guard let data = image.pngData() else { return false }
        let dir = directory(for: slug)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try data.write(to: imageURL(for: slug), options: .atomic)
            try Data("local".utf8).write(to: localImageMarkerURL(for: slug), options: .atomic)
            return true
        } catch {
            print("BestWishes: failed to save local image for \(slug): \(error)")
            return false
        }
    }

    /// Forget this card's picture (and that it was an on-device photo) so the next fetch
    /// downloads the server's picture from scratch. Used after "New picture".
    func dropImageForRefetch(_ slug: String) {
        defer { noteChange(nil) }
        let image = imageURL(for: slug)
        try? fileManager.removeItem(at: localImageMarkerURL(for: slug))
        try? fileManager.removeItem(at: validatorURL(for: image))
        try? fileManager.removeItem(at: image)
    }

    /// Slugs that have a caregiver photo on this device (these are what sync shares).
    func localImageSlugs() -> [String] {
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        let names = (try? fileManager.contentsOfDirectory(atPath: assets.path)) ?? []
        return names.filter { isLocalImage($0) && hasImage($0) }.sorted()
    }

    /// Write picture bytes that came from sync (already PNG) and mark them on-device.
    @discardableResult
    func writeLocalImageData(_ data: Data, for slug: String) -> Bool {
        defer { noteChange(nil) }
        let dir = directory(for: slug)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try data.write(to: imageURL(for: slug), options: .atomic)
            try Data("local".utf8).write(to: localImageMarkerURL(for: slug), options: .atomic)
            return true
        } catch {
            print("BestWishes: failed to write synced image for \(slug): \(error)")
            return false
        }
    }

    /// Wipe one slug's on-device picture and MP3. Used after a server Delete, not Hide.
    func removeAssets(for slug: String) {
        let dir = directory(for: slug)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try? fileManager.removeItem(at: dir)
    }

    func saveCards(_ cards: [Card]) {
        do {
            let data = try JSONEncoder().encode(cards)
            try data.write(to: cardsIndexURL, options: .atomic)
        } catch {
            print("BestWishes: failed to persist card index: \(error)")
        }
    }

    func loadCachedCards() -> [Card] {
        guard let data = try? Data(contentsOf: cardsIndexURL) else { return [] }
        return (try? JSONDecoder().decode([Card].self, from: data)) ?? []
    }

    func saveGrouping(_ grouping: BoardGrouping) {
        do {
            let data = try JSONEncoder().encode(grouping)
            try data.write(to: groupingURL, options: .atomic)
        } catch {
            print("BestWishes: failed to persist folder grouping: \(error)")
        }
    }

    func loadGrouping() -> BoardGrouping? {
        guard let data = try? Data(contentsOf: groupingURL) else { return nil }
        return try? JSONDecoder().decode(BoardGrouping.self, from: data)
    }

    /// Last successful GET /v1/board per folder (empty key is root). Offline fallback only.
    func saveBoard(_ board: BoardResponse) {
        var file = loadBoardFile()
        file[Self.boardKey(board.folderId)] = board
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: boardsURL, options: .atomic)
        } catch {
            print("BestWishes: failed to persist board snapshot: \(error)")
        }
    }

    func loadBoard(folderId: String?) -> BoardResponse? {
        loadBoardFile()[Self.boardKey(folderId)]
    }

    /// Validator (`ETag`) of the board snapshot saved for this folder, if any.
    func boardETag(folderId: String?) -> String? {
        loadETagFile()[Self.boardKey(folderId)]
    }

    func saveBoardETag(_ etag: String?, folderId: String?) {
        var file = loadETagFile()
        if let etag, !etag.isEmpty {
            file[Self.boardKey(folderId)] = etag
        } else {
            file.removeValue(forKey: Self.boardKey(folderId))
        }
        do {
            try JSONEncoder().encode(file).write(to: boardETagsURL, options: .atomic)
        } catch {
            print("BestWishes: failed to persist board validators: \(error)")
        }
    }

    private var boardETagsURL: URL { root.appendingPathComponent("board-etags.json") }

    private func loadETagFile() -> [String: String] {
        guard let data = try? Data(contentsOf: boardETagsURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Local hide overlay. Not a server DELETE — persists next to grouping.json.
    func saveHiddenSlugs(_ slugs: Set<String>, for profile: KidProfile) {
        defer { noteChange(profile) }
        do {
            let data = try JSONEncoder().encode(slugs.sorted())
            try data.write(to: hiddenFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist hidden slugs: \(error)")
        }
    }

    func loadHiddenSlugs(for profile: KidProfile) -> Set<String> {
        if let slugs = decodeStringSet(at: hiddenFileURL(for: profile)) {
            return slugs
        }
        // Legacy un-namespaced hide file: Child 1 only.
        if profile == .child1, let slugs = decodeStringSet(at: hiddenURL) {
            return slugs
        }
        return []
    }

    /// Last open folder path for this profile. Empty is the root board.
    func saveFolderPath(_ path: [String], for profile: KidProfile) {
        do {
            let data = try JSONEncoder().encode(path)
            try data.write(to: folderPathFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist folder path: \(error)")
        }
    }

    func loadFolderPath(for profile: KidProfile) -> [String] {
        guard let data = try? Data(contentsOf: folderPathFileURL(for: profile)) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func hiddenFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("hidden-\(profile.fileKey).json")
    }

    func folderPathFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("folder-path-\(profile.fileKey).json")
    }

    /// Local cell order overlay per folder (empty key is root). Not a server order API.
    func saveOrderOverlays(_ overlays: [String: [String]], for profile: KidProfile) {
        defer { noteChange(profile) }
        do {
            let data = try JSONEncoder().encode(overlays)
            try data.write(to: orderFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist order overlay: \(error)")
        }
    }

    func loadOrderOverlays(for profile: KidProfile) -> [String: [String]] {
        guard let data = try? Data(contentsOf: orderFileURL(for: profile)) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    /// Local display-label overlay keyed by slug. Server `word` is unchanged.
    func saveLabelOverlays(_ overlays: [String: String], for profile: KidProfile) {
        defer { noteChange(profile) }
        do {
            let data = try JSONEncoder().encode(overlays)
            try data.write(to: labelsFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist label overlay: \(error)")
        }
    }

    func loadLabelOverlays(for profile: KidProfile) -> [String: String] {
        guard let data = try? Data(contentsOf: labelsFileURL(for: profile)) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func orderFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("order-\(profile.fileKey).json")
    }

    func labelsFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("labels-\(profile.fileKey).json")
    }

    func savePositionOverlays(_ overlays: [String: [String: GridCoord]], for profile: KidProfile) {
        defer { noteChange(profile) }
        do {
            let data = try JSONEncoder().encode(overlays)
            try data.write(to: positionsFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist positions: \(error)")
        }
    }

    func loadPositionOverlays(for profile: KidProfile) -> [String: [String: GridCoord]] {
        guard let data = try? Data(contentsOf: positionsFileURL(for: profile)) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: GridCoord]].self, from: data)) ?? [:]
    }

    func positionsFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("positions-\(profile.fileKey).json")
    }

    func saveSpeakOverlays(_ overlays: [String: String], for profile: KidProfile) {
        defer { noteChange(profile) }
        do {
            let data = try JSONEncoder().encode(overlays)
            try data.write(to: speakFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist speak overlay: \(error)")
        }
    }

    func loadSpeakOverlays(for profile: KidProfile) -> [String: String] {
        guard let data = try? Data(contentsOf: speakFileURL(for: profile)) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func speakFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("speak-\(profile.fileKey).json")
    }

    func saveStyleOverlays(_ overlays: [String: CellStyle], for profile: KidProfile) {
        defer { noteChange(profile) }
        do {
            let data = try JSONEncoder().encode(overlays)
            try data.write(to: stylesFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist style overlay: \(error)")
        }
    }

    func loadStyleOverlays(for profile: KidProfile) -> [String: CellStyle] {
        guard let data = try? Data(contentsOf: stylesFileURL(for: profile)) else { return [:] }
        return (try? JSONDecoder().decode([String: CellStyle].self, from: data)) ?? [:]
    }

    func stylesFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("styles-\(profile.fileKey).json")
    }

    func saveMessageBarSettings(_ settings: MessageBarSettings, for profile: KidProfile) {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: messageBarFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist message bar settings: \(error)")
        }
    }

    func loadMessageBarSettings(for profile: KidProfile) -> MessageBarSettings {
        guard let data = try? Data(contentsOf: messageBarFileURL(for: profile)),
              let settings = try? JSONDecoder().decode(MessageBarSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func messageBarFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("message-bar-\(profile.fileKey).json")
    }

    /// Last spoken slugs, most-recent-first, unique, no core words, capped at `CardStore.recentsLimit`. Per profile.
    func saveRecents(_ slugs: [String], for profile: KidProfile) {
        do {
            let data = try JSONEncoder().encode(CardStore.sanitizedRecents(slugs))
            try data.write(to: recentsFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist recents: \(error)")
        }
    }

    func loadRecents(for profile: KidProfile) -> [String] {
        guard let data = try? Data(contentsOf: recentsFileURL(for: profile)) else { return [] }
        return CardStore.sanitizedRecents((try? JSONDecoder().decode([String].self, from: data)) ?? [])
    }

    /// Words typed on the keyboard page, for prediction. Per profile, on this device only.
    func saveKeyboardHistory(_ history: KeyboardHistory, for profile: KidProfile) {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: keyboardHistoryFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist keyboard history: \(error)")
        }
    }

    func loadKeyboardHistory(for profile: KidProfile) -> KeyboardHistory {
        guard let data = try? Data(contentsOf: keyboardHistoryFileURL(for: profile)) else { return KeyboardHistory() }
        return (try? JSONDecoder().decode(KeyboardHistory.self, from: data)) ?? KeyboardHistory()
    }

    func keyboardHistoryFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("keyboard-\(profile.fileKey).json")
    }

    func recentsFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("recents-\(profile.fileKey).json")
    }

    private func decodeStringSet(at url: URL) -> Set<String>? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let list = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return Set(list)
    }

    /// Make sure the card's picture and voice are on disk. Missing files are downloaded. With
    /// `revalidate`, files already on disk are checked with a conditional GET (`If-None-Match`,
    /// or `If-Modified-Since` for files saved before validators were kept) and replaced only if
    /// the server has a newer one. Returns true if the picture file changed.
    @discardableResult
    func ensureAssets(for card: Card, api: APIClient, revalidate: Bool = false) async -> Bool {
        let imageChanged = await withTaskGroup(of: Bool.self) { group -> Bool in
            if !isLocalImage(card.slug), let remote = api.absoluteURL(for: card.imageURL) {
                group.addTask {
                    await self.fetch(remote, to: self.imageURL(for: card.slug), api: api, revalidate: revalidate, label: "image \(card.slug)")
                }
            }
            if !card.audioURL.isEmpty, let remote = api.absoluteURL(for: card.audioURL) {
                group.addTask {
                    _ = await self.fetch(remote, to: self.audioURL(for: card.slug), api: api, revalidate: revalidate, label: "audio \(card.slug)")
                    return false
                }
            }
            var changed = false
            for await result in group where result { changed = true }
            return changed
        }
        return imageChanged
    }

    @discardableResult
    func ensureAssets(for folder: BoardFolder, api: APIClient, revalidate: Bool = false) async -> Bool {
        guard let path = folder.imageURL, !path.isEmpty, let remote = api.absoluteURL(for: path) else { return false }
        return await fetch(remote, to: imageURL(for: folder.id), api: api, revalidate: revalidate, label: "folder image \(folder.id)")
    }

    private func validatorURL(for file: URL) -> URL {
        file.deletingPathExtension().appendingPathExtension("etag")
    }

    /// Download if missing; if present and `revalidate`, ask the server whether it changed.
    /// Returns true when the file was written.
    private func fetch(_ remote: URL, to local: URL, api: APIClient, revalidate: Bool, label: String) async -> Bool {
        let exists = fileManager.fileExists(atPath: local.path)
        if exists && !revalidate { return false }
        let validator = validatorURL(for: local)
        var etag: String?
        var modified: Date?
        if exists {
            etag = (try? String(contentsOf: validator, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            if etag?.isEmpty ?? true {
                etag = nil
                modified = (try? fileManager.attributesOfItem(atPath: local.path))?[.modificationDate] as? Date
            }
        }
        do {
            switch try await api.download(remote, to: local, ifNoneMatch: etag, ifModifiedSince: modified) {
            case .notModified:
                return false
            case .downloaded(let newTag):
                if let newTag, !newTag.isEmpty {
                    try? Data(newTag.utf8).write(to: validator, options: .atomic)
                } else {
                    try? fileManager.removeItem(at: validator)
                }
                return true
            }
        } catch {
            print("BestWishes: cache failed for \(label): \(error)")
            return false
        }
    }

    private func loadBoardFile() -> [String: BoardResponse] {
        guard let data = try? Data(contentsOf: boardsURL) else { return [:] }
        return (try? JSONDecoder().decode([String: BoardResponse].self, from: data)) ?? [:]
    }

    private static func boardKey(_ folderId: String?) -> String {
        folderId ?? ""
    }

    func importedBoardFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("import-\(profile.fileKey).json")
    }

    func importedImagesDirectory(for profile: KidProfile) -> URL {
        let url = root.appendingPathComponent("import-images-\(profile.fileKey)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func saveImportedBoard(_ data: Data, for profile: KidProfile) {
        defer { noteChange(profile) }
        do {
            try data.write(to: importedBoardFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist imported board: \(error)")
        }
    }

    func loadImportedBoard(for profile: KidProfile) -> Data? {
        try? Data(contentsOf: importedBoardFileURL(for: profile))
    }

    func clearImportedBoard(for profile: KidProfile) {
        try? FileManager.default.removeItem(at: importedBoardFileURL(for: profile))
        try? FileManager.default.removeItem(at: importedImagesDirectory(for: profile))
    }

    func saveProfileSettings(_ settings: ProfileSettings, for profile: KidProfile) {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: profileSettingsFileURL(for: profile), options: .atomic)
        } catch {
            print("BestWishes: failed to persist profile settings: \(error)")
        }
    }

    func loadProfileSettings(for profile: KidProfile) -> ProfileSettings {
        guard let data = try? Data(contentsOf: profileSettingsFileURL(for: profile)),
              let settings = try? JSONDecoder().decode(ProfileSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func profileSettingsFileURL(for profile: KidProfile) -> URL {
        root.appendingPathComponent("settings-\(profile.fileKey).json")
    }

    /// Copy a private import image into the on-device cache. The source path is never uploaded.
    @discardableResult
    func importLocalImage(from source: URL, for slug: String) -> Bool {
        guard let image = UIImage(contentsOfFile: source.path) ?? loadHeic(source) else { return false }
        return saveLocalImage(image, for: slug)
    }

    private func loadHeic(_ url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }
}
