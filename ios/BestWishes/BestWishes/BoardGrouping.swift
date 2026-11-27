import Foundation

/// A folder on the board. Online, membership comes from GET /v1/board.
struct BoardFolder: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    /// `nil` means the folder sits on the root board.
    var parentId: String?
    /// Word-card slugs that belong on this folder's board.
    var memberSlugs: [String]
    /// Server `image_url` (live folders use `/system/folder.png`).
    var imageURL: String?

    init(
        id: String,
        name: String,
        parentId: String? = nil,
        memberSlugs: [String] = [],
        imageURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.memberSlugs = memberSlugs
        self.imageURL = imageURL
    }
}

/// Grid cell: a spoken word or a folder that opens a nested board.
enum BoardItem: Identifiable, Hashable {
    case word(Card)
    case folder(BoardFolder)

    var id: String {
        switch self {
        case .word(let card):
            return card.slug
        case .folder(let folder):
            return "folder:\(folder.id)"
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

/// Folder tree from the last successful `GET /v1/board`. Offline fallback only.
struct BoardGrouping: Codable, Equatable, Sendable {
    var folders: [BoardFolder]

    static let empty = BoardGrouping(folders: [])

    func folder(id: String) -> BoardFolder? {
        folders.first { $0.id == id }
    }

    var allMemberSlugs: Set<String> {
        Set(folders.flatMap(\.memberSlugs))
    }

    func folders(parentId: String?) -> [BoardFolder] {
        folders
            .filter { $0.parentId == parentId }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Attach a newly added word to `folderId`. Root (`nil`) leaves the card ungrouped.
    mutating func add(slug: String, to folderId: String?) {
        guard let folderId, let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        if !folders[idx].memberSlugs.contains(slug) {
            folders[idx].memberSlugs.append(slug)
        }
    }

    mutating func remove(slug: String) {
        for idx in folders.indices {
            folders[idx].memberSlugs.removeAll { $0 == slug }
        }
    }

    mutating func removeFolder(id: String) {
        folders.removeAll { $0.id == id }
    }
}
