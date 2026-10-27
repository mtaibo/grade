import SwiftUI
import UIKit

/// A transparent view that calls `action` once the finger has been held for `duration`, while
/// it's still down. SwiftUI's own long-press gesture was firing on release inside a `ScrollView`,
/// so this wraps UIKit's recognizer, which fires when the time is up. Moving more than a few
/// points (a scroll) cancels it.
struct LongPressBackground: UIViewRepresentable {
    var duration: TimeInterval = 0.4
    var action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        recognizer.minimumPressDuration = duration
        recognizer.allowableMovement = 10
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) { self.action = action }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { action() }
        }
    }
}
