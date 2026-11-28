import SwiftUI

/// Saved sentences. Tap a phrase to say it; the plus puts it on the message bar.
/// Anyone can save what is on the message bar; adding by typing and deleting are caregiver-only.
struct PhrasesSheet: View {
    let store: CardStore
    let canEdit: Bool
    let onClose: () -> Void

    @State private var draft = ""
    @State private var justSaved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !store.strip.isEmpty {
                        saveBarButton
                    }
                    if canEdit {
                        addRow
                    }
                    ForEach(Array(store.quickPhrases.phrases.enumerated()), id: \.element) { index, phrase in
                        row(phrase, index: index)
                    }
                    if store.quickPhrases.phrases.isEmpty {
                        Text("No phrases yet. Build a sentence on the message bar, then save it here.")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                    }
                }
                .padding(16)
            }
            .background(Theme.board)
            .navigationTitle("Phrases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("phrasesClose")
                }
            }
        }
    }

    private var saveBarButton: some View {
        let text = store.messageBarText
        return Button {
            justSaved = store.saveQuickPhrase(text) || justSaved
        } label: {
            HStack(spacing: 10) {
                Image(systemName: justSaved ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                    .font(.system(size: 22, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(justSaved ? "Saved" : "Save the message bar")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text("“\(text)”")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.cream)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.slate))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phrasesSaveBar")
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("Type a new phrase", text: $draft)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(addDraft)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
                .accessibilityIdentifier("phrasesNewField")
            Button("Add", action: addDraft)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.coral))
                .disabled(QuickPhrases.clean(draft).isEmpty)
                .accessibilityIdentifier("phrasesAdd")
        }
    }

    private func row(_ phrase: String, index: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                store.speakPhrase(phrase)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.coral)
                    Text(phrase)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardStroke, lineWidth: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Say \(phrase)")
            .accessibilityIdentifier("phrase-\(index)")

            Button {
                store.addPhraseToMessageBar(phrase)
                onClose()
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.slate))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Put \(phrase) on the message bar")
            .accessibilityIdentifier("phraseToBar-\(index)")

            if canEdit {
                Button(role: .destructive) {
                    store.deleteQuickPhrase(phrase)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.cream)
                        .frame(width: 48, height: 64)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.muted))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(phrase)")
                .accessibilityIdentifier("phraseDelete-\(index)")
            }
        }
    }

    private func addDraft() {
        if store.saveQuickPhrase(draft) { draft = "" }
    }
}
