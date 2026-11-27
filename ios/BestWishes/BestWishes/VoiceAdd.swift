import SwiftUI

/// Pure parse of a spoken transcript into a card word, plus the confirm → Add path.
/// Speech I/O lives in `VoiceRecognizer`; this type never talks to a mic or xAI.
enum VoiceAdd {
    /// `"add word X"`, `"add X"`, `"new card for X"`, or a bare word/phrase → X.
    /// Longer prefixes win so `"add word juice"` → `"juice"`, not `"word juice"`.
    /// Empty / whitespace / a prefix with nothing after it does not yield a card.
    static func word(from transcript: String) -> String? {
        let collapsed = Self.normalized(transcript)
        guard !collapsed.isEmpty else { return nil }

        let lower = collapsed.lowercased()
        let prefixes = ["new card for", "add word", "add"]
        for prefix in prefixes {
            if lower == prefix { return nil }
            let spaced = prefix + " "
            guard lower.hasPrefix(spaced) else { continue }
            let remainder = Self.normalized(String(collapsed.dropFirst(spaced.count)))
            return remainder.isEmpty ? nil : remainder
        }
        return collapsed
    }

    /// Same path the confirm sheet Add button uses: existing `CardStore.addWord`,
    /// which `POST`s `/v1/cards` with `folder_id` when a folder is open.
    static func confirm(_ word: String, into store: CardStore) async {
        await store.addWord(word)
    }

    private static func normalized(_ raw: String) -> String {
        let squeezed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return squeezed
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!¡¿…"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Caregiver confirm before `POST /v1/cards`. Kid mode never presents this.
/// The proposed word is editable; Add posts the current bound string.
struct VoiceConfirmSheet: View {
    @Binding var word: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Text("Add this word?")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            TextField("word", text: $word)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.ink.opacity(0.35), lineWidth: 3)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityLabel("Word to add")
                .accessibilityIdentifier("voiceConfirmWord")
            Text("Best Wishes will make the picture and the voice.")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
            HStack(spacing: 16) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .frame(minWidth: 140, minHeight: 64)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Theme.ink.opacity(0.35), lineWidth: 3)
                        )
                }
                .accessibilityLabel("Cancel voice add")
                .accessibilityIdentifier("voiceConfirmCancel")

                Button(action: onAdd) {
                    Text("Add")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .frame(minWidth: 140, minHeight: 64)
                        .foregroundStyle(Theme.cream)
                        .background(Theme.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityLabel("Confirm add \(word)")
                .accessibilityIdentifier("voiceConfirmAdd")
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.board.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voiceConfirmSheet")
    }
}
