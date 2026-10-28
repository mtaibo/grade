import SwiftUI
import UIKit

extension View {
    /// Lowers the keyboard on a tap anywhere that isn't a text field or a control, and when the
    /// content is dragged. Covers every screen pushed inside, since it listens on the window.
    func dismissesKeyboardOnBackgroundTap() -> some View {
        background(KeyboardDismissTap()).scrollDismissesKeyboard(.interactively)
    }
}

/// SwiftUI has no "tap outside" for the keyboard, and a tap gesture on a `Form` would swallow its
/// rows' taps. A UIKit recognizer on the window that doesn't cancel touches lets every tap through
/// and only ends editing when the tap lands outside a field or a control.
private struct KeyboardDismissTap: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = WindowObservingView()
        view.isUserInteractionEnabled = false
        view.onWindow = { window in context.coordinator.attach(to: window) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var recognizer: UITapGestureRecognizer?

        /// Pushing a screen takes the editor's first screen (and this view) out of the window, so a
        /// missing window keeps the recognizer where it is; it only goes away with the editor.
        func attach(to window: UIWindow?) {
            guard let window, window !== recognizer?.view else { return }
            detach()
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }

        func detach() {
            recognizer?.view?.removeGestureRecognizer(recognizer!)
            recognizer = nil
        }

        @objc private func tap(_ recognizer: UITapGestureRecognizer) {
            recognizer.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UIControl { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Reports the window it lands in, which a representable doesn't have yet when it's made.
private final class WindowObservingView: UIView {
    var onWindow: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindow?(window)
    }
}
