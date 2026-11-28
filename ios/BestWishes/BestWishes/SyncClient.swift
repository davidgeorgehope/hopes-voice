import Foundation

nonisolated enum SyncError: LocalizedError {
    case noToken
    case unauthorized
    case conflict(currentVersion: Int)
    case server(Int, String)
    case offline

    var errorDescription: String? {
        switch self {
        case .noToken: return "Add a sync token to turn sync on."
        case .unauthorized: return "The sync token was not accepted."
        case .conflict: return "Another device changed the board first."
        case .server(let code, let body): return body.isEmpty ? "Sync server error (\(code))." : body
        case .offline: return "Offline. Using the saved board."
        }
    }
}

nonisolated struct SyncRecord: Codable, Equatable, Sendable {
    var profile_id: String
    var version: Int
    var updated_at: String
    var author: String
    var note: String
    var doc: SyncDoc?
}

nonisolated struct SyncManifest: Codable, Sendable {
    var profiles: [SyncRecord]
}

nonisolated struct SyncVersions: Codable, Sendable {
    var head: Int
    var versions: [SyncRecord]
}

/// Talks to `/v1/sync/*` with a bearer token. Conditional GETs only: an unchanged board is a 304.
nonisolated struct SyncClient: Sendable {
    let baseURL: URL
    let token: String
    private let session: URLSession

    init(baseURL: URL, token: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.token = token
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 60
            config.waitsForConnectivity = false
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
    }

    private func request(_ method: String, _ path: String, etag: String? = nil, ifMatch: String? = nil, body: Data? = nil, contentType: String = "application/json") -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let ifMatch { req.setValue(ifMatch, forHTTPHeaderField: "If-Match") }
        if let body {
            req.httpBody = body
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw SyncError.offline }
            if http.statusCode == 401 || http.statusCode == 403 { throw SyncError.unauthorized }
            return (data, http)
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.offline
        }
    }

    private func failure(_ data: Data, _ http: HTTPURLResponse) -> SyncError {
        if http.statusCode == 412,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let current = object["current_version"] as? Int {
            return .conflict(currentVersion: current)
        }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return .server(http.statusCode, (object?["detail"] as? String) ?? "")
    }

    /// Versions of every profile in one request. `nil` means the manifest is unchanged (304).
    func manifest(etag: String?) async throws -> (manifest: SyncManifest, etag: String?)? {
        let (data, http) = try await send(request("GET", "v1/sync/profiles", etag: etag))
        if http.statusCode == 304 { return nil }
        guard http.statusCode == 200 else { throw failure(data, http) }
        return (try JSONDecoder().decode(SyncManifest.self, from: data), http.value(forHTTPHeaderField: "ETag"))
    }

    /// `nil` when the cached version is still current. Throws `.server(404, …)` for a never-synced profile.
    func fetch(profile: String, haveVersion: Int?) async throws -> SyncRecord? {
        let tag = haveVersion.map { "\"\($0)\"" }
        let (data, http) = try await send(request("GET", "v1/sync/profiles/\(profile)", etag: tag))
        if http.statusCode == 304 { return nil }
        guard http.statusCode == 200 else { throw failure(data, http) }
        return try JSONDecoder().decode(SyncRecord.self, from: data)
    }

    func push(profile: String, doc: SyncDoc, expectedVersion: Int, note: String) async throws -> SyncRecord {
        struct Body: Encodable { var doc: SyncDoc; var note: String }
        let body = try JSONEncoder().encode(Body(doc: doc, note: note))
        let (data, http) = try await send(request("PUT", "v1/sync/profiles/\(profile)", ifMatch: "\"\(expectedVersion)\"", body: body))
        guard http.statusCode == 200 else { throw failure(data, http) }
        return try JSONDecoder().decode(SyncRecord.self, from: data)
    }

    func versions(profile: String) async throws -> SyncVersions {
        let (data, http) = try await send(request("GET", "v1/sync/profiles/\(profile)/versions"))
        guard http.statusCode == 200 else { throw failure(data, http) }
        return try JSONDecoder().decode(SyncVersions.self, from: data)
    }

    func rollback(profile: String, to version: Int) async throws -> SyncRecord {
        let body = try JSONSerialization.data(withJSONObject: ["to_version": version])
        let (data, http) = try await send(request("POST", "v1/sync/profiles/\(profile)/rollback", body: body))
        guard http.statusCode == 200 else { throw failure(data, http) }
        return try JSONDecoder().decode(SyncRecord.self, from: data)
    }

    func hasBlob(_ sha: String) async throws -> Bool {
        let (_, http) = try await send(request("HEAD", "v1/sync/blobs/\(sha)"))
        return http.statusCode == 200
    }

    func putBlob(_ sha: String, data: Data) async throws {
        let (body, http) = try await send(request("PUT", "v1/sync/blobs/\(sha)", body: data, contentType: "image/png"))
        guard http.statusCode == 200 else { throw failure(body, http) }
    }

    func getBlob(_ sha: String) async throws -> Data {
        let (data, http) = try await send(request("GET", "v1/sync/blobs/\(sha)"))
        guard http.statusCode == 200 else { throw failure(data, http) }
        return data
    }
}
