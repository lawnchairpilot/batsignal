import UIKit

// Dismisses the keyboard when the user taps anywhere outside it.
//
// Installed once on the app's window rather than per-view, so every form gets
// the behavior without each screen wiring up its own gesture — and so it works
// on screens whose scroll views are disabled (CreateEventView), where
// `.scrollDismissesKeyboard` has nothing to act on.
final class KeyboardDismissGesture: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissGesture()

    private var isInstalled = false

    private override init() {
        super.init()
    }

    // SwiftUI creates the window after launch, so wait for it rather than
    // trying to reach for one during didFinishLaunching.
    func installWhenWindowAvailable() {
        guard !isInstalled else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: UIWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard !isInstalled, let window = notification.object as? UIWindow else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        // Let the touch continue through to whatever it landed on, so buttons,
        // list rows, map pins and the swipe-to-send drag all still fire.
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        isInstalled = true
        NotificationCenter.default.removeObserver(self, name: UIWindow.didBecomeKeyNotification, object: nil)
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - UIGestureRecognizerDelegate

    // Taps that land on a text field must not reach this recognizer: it would
    // resign the field in the same tap that is trying to focus it, leaving the
    // keyboard unable to open at all.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isTextInput(touch.view)
    }

    // Never claim a touch away from another recognizer — this only ends
    // editing, so scrolling and dragging must keep working alongside it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // The hit view for a tap on a text field is often a private subview of it,
    // so check the whole chain rather than just the view that was touched.
    private func isTextInput(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UITextField || candidate is UITextView { return true }
            current = candidate.superview
        }
        return false
    }
}
