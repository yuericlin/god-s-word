// EdgeNavigation.swift — edge swipe navigation.
// Right edge: swipe left goes forward (versions -> books -> chapters -> reading),
//             swipe right goes backward (reading -> chapters -> books -> versions).
// Left edge (on the reader): the settings/history drawer's zone. The
// reader's start-zone decision opens it (REQ-GS-2), fed by this
// file's observing pan recognizer reporting window coordinates;
// the edge recognizer here only keeps the system's back-swipe out
// of the reader.

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

/// Observes swipes on the reader and reports each finished swipe's
/// start point and travel, in window coordinates, to the reader's
/// start-zone decision (REQ-GS-2). Two recognizers are installed on
/// the navigation controller's view while the reader is visible:
///
/// - A screen-edge pan on the left edge that decides nothing: it
///   exists only so the system's back-swipe has something to wait
///   for (`require(toFail:)`), and the back-swipe is disabled
///   outright, so a left-edge swipe on the reader is never a
///   navigation pop. (When this recognizer made the drawer decision
///   itself, its system edge zone — wider than the app's 20pt —
///   turned middle swipes into drawer pulls.)
/// - A plain pan that only OBSERVES: it never cancels touches, it
///   recognizes simultaneously with everything else (scrolling,
///   taps, the edge strips), and it ignores a drag as soon as the
///   drag proves to be a vertical scroll. On end it reports the touch's
///   start location in the navigation view — the window's own
///   coordinates, the ground truth for where the finger landed —
///   which the reader converts into its own frame and classifies
///   with `ReaderSwipeZones.action`. SwiftUI's drag gesture is no
///   longer trusted for this: on device its reported start location
///   still classified middle swipes as left-edge starts.
///
/// Everything is installed on appear and torn down on disappear, so
/// other screens keep their swipe-back. Backward navigation on the
/// reader uses the right edge instead.
struct ReaderSwipeGesture: UIViewControllerRepresentable {
    /// Called on the main thread when a swipe ends: the start point
    /// in window coordinates and the total translation.
    var onSwipe: (CGPoint, CGSize) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        SwipeObserverViewController()
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        (vc as? SwipeObserverViewController)?.onSwipe = onSwipe
    }

    final class SwipeObserverViewController: UIViewController,
        UIGestureRecognizerDelegate
    {
        var onSwipe: ((CGPoint, CGSize) -> Void)?
        private weak var navView: UIView?
        private var edgePan: UIScreenEdgePanGestureRecognizer?
        private var swipePan: UIPanGestureRecognizer?
        private var swipeStart: CGPoint = .zero
        /// Set once a drag proves to be a vertical scroll; its end
        /// is then never reported as a swipe.
        private var swipeIsScroll = false

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
            if swipePan == nil {
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSwipePan(_:)))
                pan.cancelsTouchesInView = false
                pan.delegate = self
                navView.addGestureRecognizer(pan)
                swipePan = pan
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
            if let pan = swipePan {
                navView?.removeGestureRecognizer(pan)
                swipePan = nil
            }
            navView = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        /// The observing pan must never block the scroll view, the
        /// edge strips, or any other recognizer.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        /// Deliberately no action: this recognizer exists only so
        /// the system's back-swipe has something to wait for. The
        /// drawer is opened by the reader's start-zone decision
        /// (REQ-GS-2), not from here.
        @objc private func ignoreEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {}

        @objc private func handleSwipePan(_ pan: UIPanGestureRecognizer) {
            guard let navView else { return }
            switch pan.state {
            case .began:
                swipeStart = pan.location(in: navView)
                swipeIsScroll = false
            case .changed:
                // A clearly vertical drag is a scroll, not a swipe:
                // mark it so its end is never reported.
                let t = pan.translation(in: navView)
                if abs(t.y) > 40, abs(t.y) > 1.5 * abs(t.x) {
                    swipeIsScroll = true
                }
            case .ended:
                if !swipeIsScroll {
                    let t = pan.translation(in: navView)
                    onSwipe?(swipeStart, CGSize(width: t.x, height: t.y))
                }
            default:
                break
            }
        }
    }
}
