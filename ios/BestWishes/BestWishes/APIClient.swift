import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case emptyWord
    case emptyName
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Could not reach Hope's Voice."
        case .http(let code, let body):
            if code == 409 { return "That word is already on the board." }
            if !body.isEmpty { return body }
            return "Server error (\(code))."
        case .emptyWord:
            return "Type a word first."
        case .emptyName:
            return "Type a folder name first."
        case .decode:
            return "The server sent a card the app could not read."
        }
    }
}

/// Talks only to the Hope's Voice API. The iOS app never calls xAI.
struct APIClient: Sendable {
    static let shared = APIClient()
    static let productionBaseURL = URL(string: "https://hopesvoice.davidgeorgehope.com")!
    /// Unreachable loopback used by `-APIBaseURL` and OfflineBoardTests. Fails fast.
    static let unreachableBaseURL = URL(string: "http://127.0.0.1:1")!

    /// GET / download give up quickly when the host is down. POST generation may still take minutes.
    static let getTimeout: TimeInterval = 8
    static let postTimeout: TimeInterval = 180

    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = productionBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Self.getTimeout
            config.timeoutIntervalForResource = Self.postTimeout
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
    }

    /// Simulator / launch-arg hook. `-APIBaseURL <url>` points the shipped client at a blocked host.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> APIClient {
        if let idx = arguments.firstIndex(of: "-APIBaseURL"),
           arguments.indices.contains(idx + 1),
           let url = URL(string: arguments[idx + 1]),
           url.scheme != nil {
            return APIClient(baseURL: url)
        }
        return APIClient()
    }

    func health() async throws -> Bool {
        let url = baseURL.appending(path: "health")
        let (data, response) = try await data(for: getRequest(url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return String(data: data, encoding: .utf8)?.contains("true") == true
    }

    /// Result of a conditional board GET.
    enum BoardFetch: Sendable {
        /// 200: the board changed (or no validator was sent). `etag` is the validator to send next time.
        case modified(BoardResponse, etag: String?)
        /// 304: the cached copy is still current. No body was transferred.
        case notModified
    }

    /// CONTRACT v0.2.0 board. `folderId` nil is the root; otherwise `GET /v1/board?folder_id=`.
    func fetchBoard(folderId: String? = nil) async throws -> BoardResponse {
        switch try await fetchBoard(folderId: folderId, ifNoneMatch: nil) {
        case .modified(let board, _):
            return board
        case .notModified:
            // Unreachable without a validator, but a server may still answer 304 to `*`.
            throw APIError.http(304, "")
        }
    }

    /// Same GET, but sends `If-None-Match` so an unchanged board costs one tiny 304.
    func fetchBoard(folderId: String?, ifNoneMatch etag: String?) async throws -> BoardFetch {
        guard var components = URLComponents(url: baseURL.appending(path: "v1/board"), resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        if let folderId, !folderId.isEmpty {
            components.queryItems = [URLQueryItem(name: "folder_id", value: folderId)]
        }
        guard let url = components.url else { throw APIError.badURL }
        var request = getRequest(url)
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 304 {
            return .notModified
        }
        try throwIfNeeded(response, data: data)
        do {
            let board = try JSONDecoder().decode(BoardResponse.self, from: data)
            let validator = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
            return .modified(board, etag: validator)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decode(error)
        }
    }

    /// Legacy flat list. CONTRACT still serves `kind` / `folder_id` on each card.
    func fetchCards() async throws -> [Card] {
        let url = baseURL.appending(path: "v1/cards")
        let (data, response) = try await data(for: getRequest(url))
        try throwIfNeeded(response, data: data)
        do {
            let decoded = try JSONDecoder().decode(CardsResponse.self, from: data)
            return decoded.cards
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decode(error)
        }
    }

    func fetchCard(slug: String) async throws -> Card {
        let url = baseURL.appending(path: "v1/cards/\(slug)")
        let (data, response) = try await data(for: getRequest(url))
        try throwIfNeeded(response, data: data)
        return try decodeCard(data)
    }

    func createCard(word: String, folderId: String? = nil) async throws -> Card {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.emptyWord }
        let url = baseURL.appending(path: "v1/cards")
        var body: [String: Any] = ["word": trimmed]
        if let folderId, !folderId.isEmpty {
            body["folder_id"] = folderId
        }
        let (data, response) = try await data(for: jsonRequest(url: url, method: "POST", body: body, timeout: Self.postTimeout))
        try throwIfNeeded(response, data: data)
        return try decodeCard(data)
    }

    /// Ask the server for a new original picture for an existing card (audio is kept).
    func regenerateImage(slug: String) async throws -> Card {
        let url = baseURL.appending(path: "v1/cards/\(slug)/image")
        let (data, response) = try await data(for: jsonRequest(url: url, method: "POST", body: [:], timeout: Self.postTimeout))
        try throwIfNeeded(response, data: data)
        return try decodeCard(data)
    }

    func deleteCard(slug: String) async throws {
        let url = baseURL.appending(path: "v1/cards/\(slug)")
        let (data, response) = try await data(for: methodRequest(url: url, method: "DELETE"))
        try throwIfNeeded(response, data: data)
    }

    func createFolder(name: String) async throws -> BoardPayloadItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.emptyName }
        let url = baseURL.appending(path: "v1/folders")
        let (data, response) = try await data(for: jsonRequest(
            url: url,
            method: "POST",
            body: ["name": trimmed],
            timeout: Self.postTimeout
        ))
        try throwIfNeeded(response, data: data)
        do {
            return try JSONDecoder().decode(BoardPayloadItem.self, from: data)
        } catch {
            throw APIError.decode(error)
        }
    }

    func deleteFolder(slug: String) async throws {
        let url = baseURL.appending(path: "v1/folders/\(slug)")
        let (data, response) = try await data(for: methodRequest(url: url, method: "DELETE"))
        try throwIfNeeded(response, data: data)
    }

    func absoluteURL(for path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let cleaned = path.hasPrefix("/") ? path : "/" + path
        components.path = cleaned
        components.query = nil
        return components.url
    }

    /// Result of a (possibly conditional) file download.
    enum DownloadOutcome: Sendable, Equatable {
        /// The file was written. `etag` is the validator to keep next to it.
        case downloaded(etag: String?)
        /// 304: the file on disk is still current.
        case notModified
    }

    func download(_ remote: URL, to local: URL) async throws {
        _ = try await download(remote, to: local, ifNoneMatch: nil, ifModifiedSince: nil)
    }

    /// Download `remote` to `local`. With a validator the server may answer 304 and nothing is written.
    @discardableResult
    func download(
        _ remote: URL,
        to local: URL,
        ifNoneMatch etag: String?,
        ifModifiedSince modified: Date?
    ) async throws -> DownloadOutcome {
        var request = URLRequest(url: remote)
        request.timeoutInterval = Self.getTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        } else if let modified {
            request.setValue(Self.httpDate(modified), forHTTPHeaderField: "If-Modified-Since")
        }
        let (temp, response) = try await session.download(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 304 {
            return .notModified
        }
        try throwIfNeeded(response, data: Data())
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Replace, don't delete-then-move: a failed GET must not wipe a warm cache file.
        if FileManager.default.fileExists(atPath: local.path) {
            _ = try FileManager.default.replaceItemAt(local, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: local)
        }
        return .downloaded(etag: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"))
    }

    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private func getRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.getTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func methodRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.getTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func jsonRequest(url: URL, method: String, body: [String: Any], timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.badURL
        }
    }

    private func decodeCard(_ data: Data) throws -> Card {
        do {
            return try JSONDecoder().decode(Card.self, from: data)
        } catch {
            throw APIError.decode(error)
        }
    }

    private func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.badURL }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, humanMessage(from: data))
        }
    }

    private func humanMessage(from data: Data) -> String {
        struct DetailString: Decodable { let detail: String }
        struct DetailList: Decodable {
            struct Item: Decodable { let msg: String? }
            let detail: [Item]
        }
        if let parsed = try? JSONDecoder().decode(DetailString.self, from: data), !parsed.detail.isEmpty {
            return parsed.detail
        }
        if let parsed = try? JSONDecoder().decode(DetailList.self, from: data) {
            let msgs = parsed.detail.compactMap(\.msg)
            if !msgs.isEmpty { return msgs.joined(separator: " ") }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
