import SwiftUI

/// Caregiver settings: turn sync on with a token, see the synced version, restore an older one.
struct SyncSettingsSection: View {
    var sync: SyncCoordinator
    var profileName: String

    @State private var tokenDraft = ""
    @State private var history: [SyncRecord] = []
    @State private var showingHistory = false
    @State private var restoreTarget: SyncRecord?
    @State private var restoreFailed = false

    var body: some View {
        Section("Sync") {
            if sync.hasToken {
                LabeledContent("Status", value: sync.statusText)
                    .accessibilityIdentifier("syncStatus")
                if sync.hasPendingUpdate {
                    Text("A newer board from another device is ready. It applies after a quiet moment or next launch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Sync now") { Task { await sync.tick() } }
                    .accessibilityIdentifier("syncNow")
                Button("Versions and restore…") {
                    showingHistory = true
                    Task { history = await sync.history() }
                }
                .accessibilityIdentifier("syncHistory")
                Button("Turn sync off on this device", role: .destructive) { sync.signOut() }
            } else {
                SecureField("Paste sync token", text: $tokenDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("syncTokenField")
                Button("Turn sync on") {
                    sync.setToken(tokenDraft)
                    tokenDraft = ""
                }
                .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Edits to \(profileName)'s board go to your private server and show up on your other devices. Nothing changes while the board is in use. Without a token, nothing leaves this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                List(history, id: \.version) { record in
                    Button {
                        restoreTarget = record
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(record.version)").font(.headline)
                            Text("\(record.updated_at) · \(record.author) · \(record.note)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .overlay { if history.isEmpty { ProgressView() } }
                .navigationTitle("Versions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { showingHistory = false } }
                }
                .alert(
                    "Restore version \(restoreTarget?.version ?? 0)?",
                    isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } })
                ) {
                    Button("Restore") {
                        if let target = restoreTarget {
                            Task {
                                let ok = await sync.restore(version: target.version)
                                restoreFailed = !ok
                                if ok { showingHistory = false }
                            }
                        }
                        restoreTarget = nil
                    }
                    Button("Cancel", role: .cancel) { restoreTarget = nil }
                } message: {
                    Text("This becomes the newest version on every device. Nothing is deleted; you can restore again.")
                }
            }
        }
        .alert("Could not restore", isPresented: $restoreFailed) {
            Button("OK", role: .cancel) {}
        }
    }
}
