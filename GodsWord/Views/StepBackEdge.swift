// StepBackEdge.swift — invisible strip on the right edge: a leftward swipe
// steps back one level in the drill-down (reader -> chapters -> books ->
// versions), mirroring the pickers' order.

import SwiftUI

struct StepBackEdge: ViewModifier {
    @Binding var path: NavigationPath

    func body(content: Content) -> some View {
        content.overlay(alignment: .trailing) {
            Color.clear
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            if value.translation.width < -40, !path.isEmpty {
                                path.removeLast()
                            }
                        }
                )
        }
    }
}

extension View {
    /// Leftward swipe from the right edge pops one level off the navigation path.
    func stepBackOnRightEdge(path: Binding<NavigationPath>) -> some View {
        modifier(StepBackEdge(path: path))
    }
}
