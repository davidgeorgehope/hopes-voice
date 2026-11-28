import SwiftUI

/// Type any word, with big keys and word prediction. Speak says it; Add to bar puts each
/// word on the message bar. Opens from the toolbar keyboard button, in kid mode too.
struct KeyboardPage: View {
    let store: CardStore
    let onClose: () -> Void

    @State private var text = ""
    @State private var predictor = WordPredictor()

    private static let rows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m", "'"],
    ]

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 600
            let gap: CGFloat = compact ? 5 : 8
            let pad: CGFloat = compact ? 8 : 16
            let keyWidth = ((geo.size.width - pad * 2 - gap * 9) / 10).rounded(.down)
            let keyHeight = min(keyWidth * 1.1, (geo.size.height - (compact ? 230 : 300)) / 4)
            VStack(spacing: compact ? 8 : 14) {
                topRow(compact: compact)
                predictions(compact: compact)
                VStack(spacing: gap) {
                    ForEach(Self.rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(row, id: \.self) { letter in
                                key(letter, width: keyWidth, height: keyHeight, compact: compact) { type(letter) }
                                    .accessibilityIdentifier("key-\(letter)")
                            }
                        }
                    }
                    HStack(spacing: gap) {
                        action("Clear", system: "xmark", width: keyWidth * 1.6, height: keyHeight, fill: Theme.muted) { text = "" }
                            .accessibilityIdentifier("keyboardClear")
                        key("space", width: keyWidth * 4.6, height: keyHeight, compact: compact) { type(" ") }
                            .accessibilityLabel("Space")
                            .accessibilityIdentifier("keySpace")
                        action("Back", system: "delete.left.fill", width: keyWidth * 1.6, height: keyHeight, fill: Theme.muted) {
                            if !text.isEmpty { text.removeLast() }
                        }
                        .accessibilityIdentifier("keyBackspace")
                        action("Add", system: "text.badge.plus", width: keyWidth * 1.6, height: keyHeight, fill: Theme.slate) {
                            store.addTypedToMessageBar(text)
                            text = ""
                            onClose()
                        }
                        .accessibilityLabel("Add to message bar")
                        .accessibilityIdentifier("keyboardAddToBar")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(pad)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Theme.board.ignoresSafeArea())
        .onAppear { predictor = store.keyboardPredictor() }
    }

    private func topRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 18 : 24, weight: .heavy))
                    .foregroundStyle(Theme.cream)
                    .frame(width: compact ? 48 : 64, height: compact ? 56 : 72)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.slate))
            }
            .accessibilityLabel("Close keyboard")
            .accessibilityIdentifier("keyboardClose")
            Text(text.isEmpty ? "Type a word" : text)
                .font(.system(size: compact ? 24 : 34, weight: .heavy, design: .rounded))
                .foregroundStyle(text.isEmpty ? Theme.muted : Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: compact ? 56 : 72, alignment: .leading)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cream))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.muted.opacity(0.4), lineWidth: 2))
                .accessibilityIdentifier("keyboardText")
                .accessibilityValue(text)
            Button { store.speakTyped(text) } label: {
                Label("Speak", systemImage: "speaker.wave.2.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: compact ? 22 : 28, weight: .heavy))
                    .foregroundStyle(Theme.cream)
                    .frame(width: compact ? 64 : 96, height: compact ? 56 : 72)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.coral))
            }
            .accessibilityLabel("Speak")
            .accessibilityIdentifier("keyboardSpeak")
        }
    }

    private func predictions(compact: Bool) -> some View {
        let words = predictor.suggestions(for: text, limit: compact ? 3 : 5)
        return HStack(spacing: compact ? 6 : 10) {
            ForEach(words, id: \.self) { word in
                Button { text = WordPredictor.accept(word, into: text) } label: {
                    Text(word)
                        .font(.system(size: compact ? 18 : 24, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: compact ? 46 : 58)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.ink, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("prediction-\(word)")
            }
            if words.isEmpty { Color.clear.frame(height: compact ? 46 : 58) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Word predictions")
    }

    private func type(_ s: String) {
        if s == " ", text.isEmpty || text.last == " " { return }
        text += s
    }

    private func key(_ label: String, width: CGFloat, height: CGFloat, compact: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.system(size: label.count > 1 ? (compact ? 16 : 22) : (compact ? 24 : 34), weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cream)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: compact ? 8 : 12).fill(Theme.labelWell))
        }
        .buttonStyle(.plain)
    }

    private func action(_ label: String, system: String, width: CGFloat, height: CGFloat, fill: Color, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 2) {
                Image(systemName: system).font(.system(size: 20, weight: .heavy))
                Text(label).font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Theme.cream)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 12).fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
