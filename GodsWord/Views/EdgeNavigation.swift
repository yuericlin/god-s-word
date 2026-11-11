// EdgeNavigation.swift — edge swipe navigation.
// Right edge: swipe left goes forward (versions -> books -> chapters -> reading),
//             swipe right goes backward (reading -> chapters -> books -> versions).
// Left edge (on the reader): the settings/history drawer's zone. The
// reader's own swipe handling opens it (REQ-GS-2); this file only
// keeps the system's back-swipe out of the reader.

import SwiftUI
import UIKit

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
                                onForward?()
                            } else if value.translation.width > 40 {
                                onBackward?()
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

/// Keeps the system's back-swipe out of the reader while reading.
/// Installs a dedicated screen-edge pan recognizer on the navigation
/// controller's view and makes the system's back-swipe wait for it
/// (`require(toFail:)`), and disables the back-swipe outright, so a
/// left-edge swipe on the reader is never a navigation pop. The
/// recognizer itself decides nothing: the system's edge zone is
/// wider than the app's 20pt zone (REQ-GS-2), and when it opened
/// the drawer itself, swipes starting well inside the view — which
/// the user counts as middle swipes that should turn chapters —
/// brought the drawer out instead. The reader's own drag gesture
/// now makes every swipe decision by start zone. Everything is
/// installed on appear and torn down on disappear, so other screens
/// keep their swipe-back. Backward navigation on the reader uses
/// the right edge instead.
struct DrawerEdgeGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        EdgeGestureViewController()
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    final class EdgeGestureViewController: UIViewController {
        private weak var navView: UIView?
        private var edgePan: UIScreenEdgePanGestureRecognizer?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navController = navigationController,
                  let navView = navigationController?.view,
                  let pop = navController.interactivePopGestureRecognizer else { return }
            if edgePan == nil {
                let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(ignoreEdgePan(_:)))
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

        /// Deliberately no action: this recognizer exists only so
        /// the system's back-swipe has something to wait for. The
        /// drawer is opened by the reader's start-zone decision
        /// (REQ-GS-2), not from here.
        @objc private func ignoreEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {}
    }
}
