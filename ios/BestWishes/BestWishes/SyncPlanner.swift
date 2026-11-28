import CryptoKit
import Foundation

/// Per-profile bookkeeping that survives relaunch (`sync-state-<profile>.json` next to the cache).
nonisolated struct SyncState: Codable, Equatable, Sendable {
    /// Server version this device last agreed with, and the document at that version.
    var baseVersion = 0
    var base = SyncDoc.empty
    /// Remote (merged) update waiting for a safe moment, and the local snapshot it was merged against.
    var pending: SyncDoc?
    var pendingVersion: Int?
    var pendingLocalBase: SyncDoc?
    /// Pictures the server is known to have.
    var uploaded: Set<String> = []
    /// Skip re-hashing a picture whose size and mtime did not change.
    var fingerprints: [String: Fingerprint] = [:]
    var lastSyncedAt: Date?

    struct Fingerprint: Codable, Equatable, Sendable {
        var size: Int
        var mtime: Double
        var sha: String
    }
}

nonisolated struct SyncApplyPlan: Sendable {
    var profile: KidProfile
    var final: SyncDoc
    /// Set only when the imported board itself changes.
    var board: Data?
    var changedImageSlugs: [String]
}

/// Disk-backed pieces of sync that need no network. All static so launch can use them before any task runs.
nonisolated enum SyncPlanner {
    static func stateURL(_ cache: AssetCache, _ profile: KidProfile) -> URL {
        cache.rootURL.appendingPathComponent("sync-state-\(profile.fileKey).json")
    }

    static func blobURL(_ cache: AssetCache, _ sha: String) -> URL {
        let dir = cache.rootURL.appendingPathComponent("sync-blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(sha)
    }

    static func loadState(_ cache: AssetCache, _ profile: KidProfile) -> SyncState {
        guard let data = try? Data(contentsOf: stateURL(cache, profile)),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    static func saveState(_ state: SyncState, _ cache: AssetCache, _ profile: KidProfile) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL(cache, profile), options: .atomic)
        }
    }

    /// What this device has right now, read from the same files the app persists.
    static func snapshot(_ cache: AssetCache, _ profile: KidProfile, state: inout SyncState) -> SyncDoc {
        var doc = SyncDoc()
        doc.overlays.hidden = cache.loadHiddenSlugs(for: profile).sorted()
        doc.overlays.order = cache.loadOrderOverlays(for: profile)
        doc.overlays.labels = cache.loadLabelOverlays(for: profile)
        doc.overlays.positions = cache.loadPositionOverlays(for: profile)
        doc.overlays.speak = cache.loadSpeakOverlays(for: profile)
        doc.overlays.styles = cache.loadStyleOverlays(for: profile)
        if let raw = cache.loadImportedBoard(for: profile),
           let object = try? JSONSerialization.jsonObject(with: raw),
           let value = JSONValue.from(object) {
            doc.board = value
        }
        for slug in cache.localImageSlugs() {
            if let sha = sha(of: slug, cache: cache, state: &state) { doc.images[slug] = sha }
        }
        return doc
    }

    static func sha(of slug: String, cache: AssetCache, state: inout SyncState) -> String? {
        let url = cache.imageURL(for: slug)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? Int) ?? 0
        let mtime = ((attrs[.modificationDate] as? Date) ?? .distantPast).timeIntervalSince1970
        if let known = state.fingerprints[slug], known.size == size, known.mtime == mtime { return known.sha }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        state.fingerprints[slug] = .init(size: size, mtime: mtime, sha: digest)
        return digest
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encodeBoard(_ value: JSONValue) -> Data? {
        try? JSONEncoder().encode(value)
    }

    /// Merge the staged remote update with whatever the caregiver did since, and copy pictures into the cache.
    /// Returns nil when nothing is staged. Safe to call repeatedly: it changes only pictures.
    static func makeApplyPlan(_ cache: AssetCache, _ profile: KidProfile) -> SyncApplyPlan? {
        var state = loadState(cache, profile)
        guard let pending = state.pending, let localBase = state.pendingLocalBase else { return nil }
        let local = snapshot(cache, profile, state: &state)
        let final = SyncDoc.merge(base: localBase, local: local, remote: pending)
        var changed: [String] = []
        cache.withoutChangeNotifications {
            for (slug, sha) in final.images where local.images[slug] != sha {
                guard let data = try? Data(contentsOf: blobURL(cache, sha)), hash(data) == sha else { continue }
                if cache.writeLocalImageData(data, for: slug) {
                    changed.append(slug)
                    let url = cache.imageURL(for: slug)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                        state.fingerprints[slug] = .init(
                            size: (attrs[.size] as? Int) ?? 0,
                            mtime: ((attrs[.modificationDate] as? Date) ?? .distantPast).timeIntervalSince1970,
                            sha: sha
                        )
                    }
                }
            }
        }
        saveState(state, cache, profile)
        let board: Data?
        if let value = final.board, final.board.map(SyncDoc.normalised) != local.board.map(SyncDoc.normalised) {
            board = encodeBoard(value)
        } else {
            board = nil
        }
        return SyncApplyPlan(profile: profile, final: final, board: board, changedImageSlugs: changed.sorted())
    }

    static func commitApply(_ cache: AssetCache, _ profile: KidProfile) {
        var state = loadState(cache, profile)
        state.pending = nil
        state.pendingLocalBase = nil
        state.pendingVersion = nil
        saveState(state, cache, profile)
    }

    /// Write merged overlays to disk. Notifications are muted so applying never looks like a local edit.
    static func writeOverlays(_ overlays: SyncDoc.Overlays, cache: AssetCache, profile: KidProfile) {
        cache.withoutChangeNotifications {
            cache.saveHiddenSlugs(Set(overlays.hidden), for: profile)
            cache.saveOrderOverlays(overlays.order, for: profile)
            cache.saveLabelOverlays(overlays.labels, for: profile)
            cache.savePositionOverlays(overlays.positions, for: profile)
            cache.saveSpeakOverlays(overlays.speak, for: profile)
            cache.saveStyleOverlays(overlays.styles, for: profile)
        }
    }
}

/// Network half of sync. One profile at a time; never touches the UI.
actor SyncWorker {
    struct Outcome: Sendable {
        var version: Int
        var hasPendingUpdate: Bool
        var pushed: Bool
    }

    private let cache: AssetCache
    private let deviceName: String

    init(cache: AssetCache, deviceName: String) {
        self.cache = cache
        self.deviceName = deviceName
    }

    func storedVersion(_ profile: KidProfile) -> Int {
        SyncPlanner.loadState(cache, profile).baseVersion
    }

    func sync(profile: KidProfile, profileID: String, client: SyncClient) async throws -> Outcome {
        for _ in 0..<4 {
            var state = SyncPlanner.loadState(cache, profile)
            let local = SyncPlanner.snapshot(cache, profile, state: &state)

            var remoteVersion = state.baseVersion
            var remoteDoc = state.base
            var remoteIsNew = false
            do {
                if let record = try await client.fetch(profile: profileID, haveVersion: state.baseVersion > 0 ? state.baseVersion : nil),
                   let doc = record.doc {
                    remoteVersion = record.version
                    remoteDoc = doc
                    remoteIsNew = record.version != state.baseVersion
                }
            } catch SyncError.server(404, _) {
                remoteVersion = 0
                remoteDoc = .empty
            }

            let merged = remoteIsNew ? SyncDoc.merge(base: state.base, local: local, remote: remoteDoc) : local
            var pushed = false
            if merged != remoteDoc {
                try await uploadPictures(merged, local: local, state: &state, client: client)
                do {
                    let record = try await client.push(
                        profile: profileID, doc: merged, expectedVersion: remoteVersion,
                        note: "edit on \(deviceName)"
                    )
                    state.base = merged
                    state.baseVersion = record.version
                    pushed = true
                } catch SyncError.conflict {
                    SyncPlanner.saveState(state, cache, profile)
                    continue
                }
            } else {
                state.base = remoteDoc
                state.baseVersion = remoteVersion
            }

            if merged != local {
                try await downloadPictures(merged, local: local, client: client)
                state.pending = merged
                state.pendingVersion = state.baseVersion
                state.pendingLocalBase = local
            } else {
                state.pending = nil
                state.pendingLocalBase = nil
                state.pendingVersion = nil
            }
            state.lastSyncedAt = Date()
            SyncPlanner.saveState(state, cache, profile)
            return Outcome(version: state.baseVersion, hasPendingUpdate: state.pending != nil, pushed: pushed)
        }
        throw SyncError.conflict(currentVersion: -1)
    }

    private func uploadPictures(_ doc: SyncDoc, local: SyncDoc, state: inout SyncState, client: SyncClient) async throws {
        for (slug, sha) in doc.images where local.images[slug] == sha && !state.uploaded.contains(sha) {
            if try await client.hasBlob(sha) {
                state.uploaded.insert(sha)
                continue
            }
            guard let data = try? Data(contentsOf: cache.imageURL(for: slug)), SyncPlanner.hash(data) == sha else { continue }
            try await client.putBlob(sha, data: data)
            state.uploaded.insert(sha)
        }
    }

    private func downloadPictures(_ doc: SyncDoc, local: SyncDoc, client: SyncClient) async throws {
        for (slug, sha) in doc.images where local.images[slug] != sha {
            let url = SyncPlanner.blobURL(cache, sha)
            if let data = try? Data(contentsOf: url), SyncPlanner.hash(data) == sha { continue }
            let data = try await client.getBlob(sha)
            guard SyncPlanner.hash(data) == sha else { continue }
            try data.write(to: url, options: .atomic)
        }
    }
}
