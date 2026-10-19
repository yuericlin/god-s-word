// EdgeNavigation.swift — edge swipe navigation.
// Right edge, swipe left: go forward (versions -> books -> chapters -> reading).
// Left edge, swipe right: go backward (reading -> chapters -> books -> versions)
// via the system's swipe-back.

import SwiftUI

/// Guards against a single long swipe cascading through multiple levels:
/// edge navigations are rate-limited to one per 0.5s across all edge zones.
private var lastEdgeNavigationAt = Date.distantPast

func allowEdgeNavigation() -> Bool {
    let now = Date()
    guard now.timeIntervalSince(lastEdgeNavigationAt) > 0.5 else { return false }
    lastEdgeNavigationAt = now
    return true
}

/// Right-edge strip: a leftward swipe goes forward in the drill-down.
struct ForwardEdge: ViewModifier {
    var action: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .trailing) {
            Color.clear
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            if value.translation.width < -40, allowEdgeNavigation() {
                                action()
                            }
                        }
                )
        }
    }
}

extension View {
    /// Leftward swipe from the right edge performs the forward action.
    func forwardOnRightEdge(action: @escaping () -> Void) -> some View {
        modifier(ForwardEdge(action: action))
    }
}
