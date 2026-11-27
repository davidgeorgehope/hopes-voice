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

    private var kidProofControl: some View {
        label(title: "Edit", systemImage: "lock.fill", emphasized: false, faded: true, hint: "Hold to edit")
            .overlay {
                UnlockHoldRecognizer(
                    oneFingerDuration: CaregiverMode.unlockHoldDuration,
                    twoFingerDuration: 1.0
                ) {
                    mode.unlockAndEdit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Edit")
            .accessibilityHint("Hold for one and a half seconds, or hold with two fingers, to edit the board")
            .accessibilityIdentifier("editLock")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Unlock editing") {
                mode.unlockAndEdit()
            }
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

/// UIKit recognizers so a one-finger 1.5s hold and a two-finger hold both unlock Edit.
private struct UnlockHoldRecognizer: UIViewRepresentable {
    var oneFingerDuration: TimeInterval
    var twoFingerDuration: TimeInterval
    var onUnlock: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onUnlock = onUnlock
        context.coordinator.oneFinger.minimumPressDuration = oneFingerDuration
        context.coordinator.twoFinger.minimumPressDuration = twoFingerDuration
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(oneFingerDuration: oneFingerDuration, twoFingerDuration: twoFingerDuration, onUnlock: onUnlock)
    }

    final class Coordinator: NSObject {
        var onUnlock: () -> Void
        let oneFinger: UILongPressGestureRecognizer
        let twoFinger: UILongPressGestureRecognizer

        init(oneFingerDuration: TimeInterval, twoFingerDuration: TimeInterval, onUnlock: @escaping () -> Void) {
            self.onUnlock = onUnlock
            oneFinger = UILongPressGestureRecognizer()
            oneFinger.minimumPressDuration = oneFingerDuration
            oneFinger.numberOfTouchesRequired = 1
            twoFinger = UILongPressGestureRecognizer()
            twoFinger.minimumPressDuration = twoFingerDuration
            twoFinger.numberOfTouchesRequired = 2
            super.init()
            oneFinger.addTarget(self, action: #selector(fired(_:)))
            twoFinger.addTarget(self, action: #selector(fired(_:)))
        }

        func install(on view: UIView) {
            view.addGestureRecognizer(oneFinger)
            view.addGestureRecognizer(twoFinger)
        }

        @objc func fired(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            onUnlock()
        }
    }
}
