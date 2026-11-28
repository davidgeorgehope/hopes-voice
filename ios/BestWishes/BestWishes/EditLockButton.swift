import SwiftUI
import UIKit

/// Kid-proof Edit control for the top toolbar.
/// In kid mode it is low-contrast and only unlocks after a 1.5s press or a two-finger hold.
/// A short tap does nothing, so a child who finds the button cannot enter Edit by accident.
struct EditLockButton: View {
    @Bindable var mode: CaregiverMode
    var isCompact: Bool = false
    var onLock: () -> Void = {}

    var body: some View {
        if mode.showsEditChrome {
            Button(action: onLock) {
                label(title: "Done", systemImage: "checkmark", emphasized: true)
            }
            .accessibilityLabel("Done editing")
            .accessibilityIdentifier("doneEditing")
        } else if mode.isCaregiver {
            Button(action: { mode.enterEdit() }) {
                label(title: "Edit", systemImage: "pencil", emphasized: false)
            }
            .accessibilityLabel("Edit board")
            .accessibilityIdentifier("editBoard")
        } else {
            kidProofControl
        }
    }

    @State private var isPressing = false

    /// One finger: SwiftUI's own long-press, which commits the state change in the same
    /// SwiftUI transaction as the gesture, exactly like the title long-press. Two fingers: UIKit
    /// recognizer (SwiftUI has no multi-touch long press) that hops back onto the main actor.
    private var kidProofControl: some View {
        // No on-screen hint text in kid mode; the control stays low-contrast and hold-to-unlock.
        label(title: "Edit", systemImage: "lock.fill", emphasized: false, faded: true)
            .scaleEffect(isPressing ? 0.94 : 1)
            .opacity(isPressing ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: isPressing)
            .overlay {
                TwoFingerHoldRecognizer(duration: 1.0, onHold: unlock)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onLongPressGesture(
                minimumDuration: CaregiverMode.unlockHoldDuration,
                maximumDistance: 24,
                perform: unlock,
                onPressingChanged: { isPressing = $0 }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Edit")
            .accessibilityHint("Hold for one and a half seconds, or hold with two fingers, to edit the board")
            .accessibilityIdentifier("editLock")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Unlock editing", unlock)
    }

    private func unlock() {
        isPressing = false
        mode.unlockAndEdit()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func label(
        title: String,
        systemImage: String,
        emphasized: Bool,
        faded: Bool = false,
        hint: String? = nil
    ) -> some View {
        VStack(spacing: 1) {
            Image(systemName: systemImage)
                .font(.system(size: isCompact ? 14 : 16, weight: .bold))
            Text(title)
                .font(.system(size: isCompact ? 12 : 14, weight: .heavy, design: .rounded))
            if let hint {
                Text(hint)
                    .font(.system(size: isCompact ? 9 : 10, weight: .semibold, design: .rounded))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(Theme.cream.opacity(faded ? 0.45 : 1))
        .frame(minWidth: isCompact ? 56 : 64, minHeight: isCompact ? 48 : 56)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(emphasized ? Theme.coral : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.cream.opacity(faded ? 0.28 : 0.65), lineWidth: faded ? 1.5 : 3)
                )
        )
    }
}

/// Two-finger hold. SwiftUI has no multi-touch long press, so this is a UIKit recognizer.
/// It never intercepts the one-finger SwiftUI long press (it requires two touches) and it
/// changes state only through `onHold`, dispatched asynchronously onto the main queue so the
/// SwiftUI update is never made from inside UIKit's gesture delivery.
private struct TwoFingerHoldRecognizer: UIViewRepresentable {
    var duration: TimeInterval
    var onHold: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.fired(_:))
        )
        recognizer.numberOfTouchesRequired = 2
        recognizer.minimumPressDuration = duration
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onHold = onHold
    }

    func makeCoordinator() -> Coordinator { Coordinator(onHold: onHold) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onHold: () -> Void
        init(onHold: @escaping () -> Void) { self.onHold = onHold }

        @objc func fired(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            DispatchQueue.main.async { [weak self] in self?.onHold() }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
