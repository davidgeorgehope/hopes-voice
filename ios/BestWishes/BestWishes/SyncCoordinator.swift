import Foundation
import Observation
import SwiftUI
import UIKit

/// Keeps this device's profiles in step with the server without ever getting in the way.
///
/// - Edits made here are pushed in the background a moment after they happen.
/// - Updates from other devices are fetched (only when the version changed), merged, and staged.
///   They are applied at launch, or after a quiet spell with nothing in the message bar, never mid-use.
/// - Every network step runs off the main thread and fails quietly: offline just means "saved board".
@MainActor
@Observable
final class SyncCoordinator {
    enum Status: Equatable {
        case off
        case idle
        case syncing
        case offline
        case failed(String)
    }

    /// Seconds without a tap before a staged update may be applied.
    static let defaultIdleSeconds: TimeInterval = 20
    static let defaultPollSeconds: TimeInterval = 30
    static let pushDebounce: TimeInterval = 1.5

    private(set) var status: Status = .off
    private(set) var syncedVersion: Int = 0
    private(set) var lastSyncedAt: Date?
    private(set) var hasPendingUpdate = false
    private(set) var hasToken = false

    @ObservationIgnored private let store: CardStore
    @ObservationIgnored private let cache: AssetCache
    @ObservationIgnored private let baseURL: URL
    @ObservationIgnored private let namespace: String
    @ObservationIgnored private let idleSeconds: TimeInterval
    @ObservationIgnored private let pollSeconds: TimeInterval
    @ObservationIgnored private let worker: SyncWorker
    @ObservationIgnored private var tokenOverride: String?
    @ObservationIgnored private var lastInteraction = Date()
    @ObservationIgnored private var dirty: Set<KidProfile> = Set(KidProfile.allCases)
    @ObservationIgnored private var manifestETag: String?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var running = false
    /// Extra safety check from the UI: edit mode open, an editor sheet showing, and so on.
    @ObservationIgnored var isBusy: () -> Bool = { false }

    init(
        store: CardStore,
        cache: AssetCache = .shared,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        baseURL: URL? = nil
    ) {
        self.store = store
        self.cache = cache
        self.baseURL = baseURL ?? APIClient.fromLaunchArguments(arguments).baseURL
        func value(_ flag: String) -> String? {
            guard let idx = arguments.firstIndex(of: flag), arguments.indices.contains(idx + 1) else { return nil }
            return arguments[idx + 1]
        }
        self.namespace = value("-SyncNamespace").map { $0.isEmpty ? "" : $0 + "-" } ?? ""
        self.idleSeconds = value("-SyncIdleSeconds").flatMap(TimeInterval.init) ?? Self.defaultIdleSeconds
        self.pollSeconds = value("-SyncPollSeconds").flatMap(TimeInterval.init) ?? Self.defaultPollSeconds
        // Launch-arg token is a development hook: it lands in the Keychain, not in any file.
        if let token = value("-SyncToken") { SyncCredentials.setToken(token) }
        self.worker = SyncWorker(cache: cache, deviceName: UIDevice.current.name)
        self.hasToken = SyncCredentials.token() != nil
        self.status = hasToken ? .idle : .off
        self.syncedVersion = SyncPlanner.loadState(cache, store.activeProfile).baseVersion
        self.lastSyncedAt = SyncPlanner.loadState(cache, store.activeProfile).lastSyncedAt
        store.onInteraction = { [weak self] in self?.noteInteraction() }
    }

    func profileID(_ profile: KidProfile) -> String { namespace + profile.fileKey }

    // MARK: Lifecycle

    /// Call once from the app. Applies anything staged by the last session before the first tap.
    func start() {
        guard loop == nil else { return }
        cache.setChangeObserver { [weak self] profile in
            Task { @MainActor [weak self] in self?.localEdit(profile) }
        }
        applyStagedNow()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let deadline = Date().addingTimeInterval(self.pollSeconds)
                while Date() < deadline, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    self.applyIfSafe()
                }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        cache.setChangeObserver(nil)
    }

    func sceneBecameActive() {
        Task { await tick() }
    }

    // MARK: Signals from the app

    func noteInteraction() { lastInteraction = Date() }

    private func localEdit(_ profile: KidProfile?) {
        noteInteraction()
        guard hasToken else { return }
        if let profile { dirty.insert(profile) } else { dirty.formUnion(KidProfile.allCases) }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pushDebounce))
            guard !Task.isCancelled, let self else { return }
            self.debounce = nil
            await self.tick()
        }
    }

    // MARK: Token

    func setToken(_ token: String) {
        SyncCredentials.setToken(token)
        hasToken = SyncCredentials.token() != nil
        status = hasToken ? .idle : .off
        manifestETag = nil
        dirty = Set(KidProfile.allCases)
        if hasToken { Task { await tick() } }
    }

    func signOut() {
        SyncCredentials.setToken(nil)
        hasToken = false
        status = .off
    }

    // MARK: Sync pass

    private func client() -> SyncClient? {
        guard let token = SyncCredentials.token() else { return nil }
        return SyncClient(baseURL: baseURL, token: token)
    }

    /// One pass: ask which profiles changed (304 when nothing did), then sync only those.
    func tick() async {
        guard !running, let client = client() else { return }
        running = true
        defer { running = false }
        status = .syncing
        do {
            var changed = dirty
            if let result = try await client.manifest(etag: manifestETag) {
                manifestETag = result.etag
                for record in result.manifest.profiles {
                    for profile in KidProfile.allCases where profileID(profile) == record.profile_id {
                        if await worker.storedVersion(profile) != record.version { changed.insert(profile) }
                    }
                }
            }
            dirty.subtract(changed)
            for profile in KidProfile.allCases where changed.contains(profile) {
                do {
                    let outcome = try await worker.sync(profile: profile, profileID: profileID(profile), client: client)
                    if profile == store.activeProfile {
                        syncedVersion = outcome.version
                        if outcome.hasPendingUpdate { hasPendingUpdate = true }
                    }
                    if outcome.pushed { manifestETag = nil }
                } catch {
                    dirty.insert(profile)
                    throw error
                }
            }
            lastSyncedAt = Date()
            status = .idle
            applyIfSafe()
        } catch let error as SyncError {
            switch error {
            case .offline: status = .offline
            case .unauthorized: status = .failed(error.localizedDescription)
            default: status = .failed(error.localizedDescription)
            }
        } catch {
            status = .offline
        }
    }

    // MARK: Applying

    var isSafeToApply: Bool {
        Date().timeIntervalSince(lastInteraction) >= idleSeconds && !isBusy() && store.strip.isEmpty && !store.isAdding
    }

    private func applyIfSafe() {
        guard hasPendingUpdate, isSafeToApply else { return }
        applyStagedNow()
    }

    /// Apply the staged update for the active profile right now (launch, profile switch, restore).
    func applyStagedNow() {
        let profile = store.activeProfile
        guard let plan = SyncPlanner.makeApplyPlan(cache, profile) else {
            hasPendingUpdate = false
            return
        }
        cache.withoutChangeNotifications {
            if let raw = plan.board, let document = try? BoardImport.decode(raw), BoardImport.validate(document).isValid {
                store.applyImportedDocument(document, raw: raw, bundle: nil)
            }
            SyncPlanner.writeOverlays(plan.final.overlays, cache: cache, profile: profile)
        }
        store.reloadOverlaysFromDisk()
        plan.changedImageSlugs.forEach(store.bumpImage)
        SyncPlanner.commitApply(cache, profile)
        hasPendingUpdate = false
        syncedVersion = SyncPlanner.loadState(cache, profile).baseVersion
        // If the caregiver edited while the update waited, those edits still need to go up.
        dirty.insert(profile)
    }

    /// The caregiver switched profile: anything staged for it may apply now.
    func profileDidChange() {
        syncedVersion = SyncPlanner.loadState(cache, store.activeProfile).baseVersion
        hasPendingUpdate = SyncPlanner.loadState(cache, store.activeProfile).pending != nil
        if hasPendingUpdate { applyStagedNow() }
    }

    // MARK: History and restore

    func history() async -> [SyncRecord] {
        guard let client = client() else { return [] }
        return (try? await client.versions(profile: profileID(store.activeProfile)))?.versions ?? []
    }

    /// Restore an older version: the server writes it as a new version, then this device applies it.
    func restore(version: Int) async -> Bool {
        guard let client = client() else { return false }
        do {
            _ = try await client.rollback(profile: profileID(store.activeProfile), to: version)
            manifestETag = nil
            while running { try? await Task.sleep(for: .milliseconds(100)) }
            await tick()
            applyStagedNow()
            return true
        } catch {
            return false
        }
    }

    var statusText: String {
        switch status {
        case .off: return "Sync is off"
        case .idle:
            if syncedVersion > 0 { return "Synced · version \(syncedVersion)" }
            return "Ready to sync"
        case .syncing: return "Syncing…"
        case .offline: return "Offline · using the saved board"
        case .failed(let message): return message
        }
    }
}
