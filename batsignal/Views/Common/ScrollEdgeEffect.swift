import SwiftUI

// The scroll edge effect arrived in iOS 26, and so did the modifier that turns
// it off. Both scroll views that want it off still have to compile against the
// deployment target, so the availability check lives here once rather than at
// each call site.
extension View {
    func hidingScrollEdgeEffect() -> some View {
        modifier(ScrollEdgeEffectHidden())
    }
}

private struct ScrollEdgeEffectHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden()
        } else {
            content
        }
    }
}
