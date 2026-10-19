// EdgeNavigation.swift — edge swipe navigation.
// Right edge: swipe left goes forward (versions -> books -> chapters -> reading),
//             swipe right goes backward (reading -> chapters -> books -> versions).
// Left edge (on the reader): opens the settings/history drawer.

import SwiftUI
import UIKit

/// Guards against a single long swipe cascading through multiple levels:
/// edge navigations are rate-limited to one per 0.5s across all edge zones.
private var lastEdgeNavigationAt = Date.distantPast

func allowEdgeNavigation() -> Bool {
    let now = Date()
    guard now.timeIntervalSince(lastEdgeNavigationAt) > 0.5 else { return false }
    lastEdgeNavigationAt = now
    return true
}

/// Right-edge strip: leftward swipe goes forward, rightward swipe goes backward.
struct RightEdgeNavigation: ViewModifier {
    var onForward: (() -> Void)?
    var onBackward: (() -> Void)?

    func body(content: Content) -> some View {
        content.overlay(alignment: .trailing) {
            Color.clear
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            if value.translation.width < -40 {
                                if allowEdgeNavigation() { onForward?() }
                            } else if value.translation.width > 40 {
                                if allowEdgeNavigation() { onBackward?() }
                            }
                        }
                )
        }
    }
}

extension View {
    /// Right-edge swipes: left goes forward, right goes backward.
    func edgeNavigation(onForward: (() -> Void)? = nil,
                        onBackward: (() -> Void)? = nil) -> some View {
        modifier(RightEdgeNavigation(onForward: onForward, onBackward: onBackward))
    }
}

/// Gives the settings/history drawer a hard claim on the left edge while
/// reading. Installs a dedicated screen-edge pan recognizer on the navigation
/// controller's view and makes the system's back-swipe wait for it
/// (`require(toFail:)`), so a left-edge swipe reliably opens the drawer.
/// Everything is installed on appear and torn down on disappear, so other
/// screens keep their swipe-back. Backward navigation on the reader uses the
/// right edge instead.
struct DrawerEdgeGesture: UIViewControllerRepresentable {
    var onOpen: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        EdgeGestureViewController(onOpen: onOpen)
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        (vc as? EdgeGestureViewController)?.onOpen = onOpen
    }

    final class EdgeGestureViewController: UIViewController {
        var onOpen: () -> Void
        private weak var navView: UIView?
        private var edgePan: UIScreenEdgePanGestureRecognizer?

        init(onOpen: @escaping () -> Void) {
            self.onOpen = onOpen
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navController = navigationController,
                  let navView = navigationController?.view,
                  let pop = navController.interactivePopGestureRecognizer else { return }
            if edgePan == nil {
                let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
                pan.edges = .left
                // The drawer wins the left edge; backward navigation uses the right edge.
                pop.require(toFail: pan)
                navView.addGestureRecognizer(pan)
                edgePan = pan
            }
            self.navView = navView
            navController.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let pan = edgePan {
                navView?.removeGestureRecognizer(pan)
                edgePan = nil
            }
            navView = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        @objc private func handleEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            if recognizer.state == .ended {
                onOpen()
            }
        }
    }
}
