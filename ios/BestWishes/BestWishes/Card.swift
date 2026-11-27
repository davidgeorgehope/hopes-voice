import Foundation

struct Card: Codable, Identifiable, Hashable, Sendable {
    var id: String { slug }

    let word: String
    let slug: String
    let imageURL: String
    let audioURL: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case word, slug
        case imageURL = "image_url"
        case audioURL = "audio_url"
        case createdAt = "created_at"
        case card
    }

    init(word: String, slug: String, imageURL: String, audioURL: String, createdAt: String? = nil) {
        self.word = word
        self.slug = slug
        self.imageURL = imageURL
        self.audioURL = audioURL
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.card), let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .card) {
            word = try nested.decode(String.self, forKey: .word)
            slug = try nested.decode(String.self, forKey: .slug)
            imageURL = try nested.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
            audioURL = try nested.decodeIfPresent(String.self, forKey: .audioURL) ?? ""
            createdAt = try nested.decodeIfPresent(String.self, forKey: .createdAt)
            return
        }
        word = try container.decode(String.self, forKey: .word)
        slug = try container.decode(String.self, forKey: .slug)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
        audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(word, forKey: .word)
        try container.encode(slug, forKey: .slug)
        try container.encode(imageURL, forKey: .imageURL)
        try container.encode(audioURL, forKey: .audioURL)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

struct CardsResponse: Codable, Sendable {
    let cards: [Card]
    let count: Int?
}

enum BoardItemKind: String, Codable, Sendable {
    case word
    case folder
}

/// One cell from CONTRACT `GET /v1/board` (`kind` word|folder).
struct BoardPayloadItem: Codable, Hashable, Sendable {
    let kind: BoardItemKind
    let slug: String
    let word: String
    let imageURL: String
    let audioURL: String?
    let folderId: String?
    let children: [String]?
    let name: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case kind, slug, word, children, name
        case imageURL = "image_url"
        case audioURL = "audio_url"
        case folderId = "folder_id"
        case createdAt = "created_at"
        case folder, item, card
    }

    init(
        kind: BoardItemKind,
        slug: String,
        word: String,
        imageURL: String,
        audioURL: String? = nil,
        folderId: String? = nil,
        children: [String]? = nil,
        name: String? = nil,
        createdAt: String? = nil
    ) {
        self.kind = kind
        self.slug = slug
        self.word = word
        self.imageURL = imageURL
        self.audioURL = audioURL
        self.folderId = folderId
        self.children = children
        self.name = name
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nestedKey = Self.nestedKey(in: container),
           let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: nestedKey) {
            try self.init(container: nested)
            return
        }
        try self.init(container: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(slug, forKey: .slug)
        try container.encode(word, forKey: .word)
        try container.encode(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(audioURL, forKey: .audioURL)
        try container.encodeIfPresent(folderId, forKey: .folderId)
        try container.encodeIfPresent(children, forKey: .children)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    var displayName: String { name ?? word }

    func asCard() -> Card {
        Card(
            word: word,
            slug: slug,
            imageURL: imageURL,
            audioURL: audioURL ?? "",
            createdAt: createdAt
        )
    }

    func asFolder(parentId: String?) -> BoardFolder {
        BoardFolder(
            id: slug,
            name: displayName,
            parentId: folderId ?? parentId,
            memberSlugs: children ?? [],
            imageURL: imageURL.isEmpty ? nil : imageURL
        )
    }

    private init(container: KeyedDecodingContainer<CodingKeys>) throws {
        if let raw = try container.decodeIfPresent(String.self, forKey: .kind) {
            kind = BoardItemKind(rawValue: raw) ?? .word
        } else {
            kind = .word
        }
        slug = try container.decode(String.self, forKey: .slug)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
        let decodedWord = try container.decodeIfPresent(String.self, forKey: .word)
        word = decodedWord ?? decodedName ?? slug
        name = decodedName
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
        audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        children = try container.decodeIfPresent([String].self, forKey: .children)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    private static func nestedKey(in container: KeyedDecodingContainer<CodingKeys>) -> CodingKeys? {
        if container.contains(.folder) { return .folder }
        if container.contains(.item) { return .item }
        if container.contains(.card) { return .card }
        return nil
    }
}

/// CONTRACT v0.2.0 `GET /v1/board` and `GET /v1/board?folder_id=`.
struct BoardResponse: Codable, Sendable {
    let items: [BoardPayloadItem]
    let folderId: String?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case items, count
        case folderId = "folder_id"
    }

    init(items: [BoardPayloadItem], folderId: String?, count: Int) {
        self.items = items
        self.folderId = folderId
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([BoardPayloadItem].self, forKey: .items)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? items.count
    }
}
