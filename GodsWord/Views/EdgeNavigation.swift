// EdgeNavigation.swift — edge swipe navigation.
// Right edge: swipe left goes forward (versions -> books -> chapters -> reading).
//             Swiping back is disabled everywhere in the drill-down
//             (Nov 11, 2026): no right-edge swipe right, and the
//             system's interactive back gesture is vetoed on every
//             drill-down screen — going back is the navigation
//             bar's back button only.
// Left edge (on the reader): the settings/history drawer's zone. The
// reader's start-zone decision opens it (REQ-GS-2), fed by this
// file's observing pan recognizer reporting window coordinates;
// the edge recognizer here only keeps the system's back-swipe out
// of the reader.

import SwiftUI
import UIKit

/// DIAGNOSTIC (branch diag/swipe-readout-2, never merge):
/// a sink the reader's overlay renders.
enum SwipeDiag {
    static var sink: ((String) -> Void)?
    static func add(_ s: String) { sink?(s) }
    static func cls(_ o: AnyObject?) -> String {
        guard let o else { return "nil" }
        return String(describing: type(of: o))
    }
}

/// Right-edge strip: a leftward swipe goes forward. There is no
/// backward swipe (Nov 11, 2026): swiping back is disabled.
struct RightEdgeNavigation: ViewModifier {
    var onForward: (() -> Void)?

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
                            }
                        }
                )
        }
    }
}

extension View {
    /// Right-edge swipe: left goes forward. (No backward swipe —
    /// swiping back is disabled; see the file header.)
    func edgeNavigation(onForward: (() -> Void)? = nil) -> some View {
        modifier(RightEdgeNavigation(onForward: onForward))
    }

    /// Vetoes the system's interactive back gesture while this
    /// screen is visible (see SwipeBackVeto). The reader does
    /// not use this: its own background trigger installs the
    /// same guard (REQ-GS-2).
    func disableSwipeBack() -> some View {
        background(SwipeBackVeto().frame(width: 0, height: 0))
    }
}

/// Installs the back-gesture veto (SwipeBackGuard, below)
/// for the drill-down screens that have no reader-style
/// trigger of their own (books, chapters): appearance calls
/// the guard's one-time installation. Swiping back is
/// disabled (Nov 11, 2026) — the drill-down moves forward by
/// swipe and goes back by the navigation bar's back button
/// only.
struct SwipeBackVeto: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        ReaderSwipeGesture.GuardTriggerViewController()
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}

/// A trigger for SwipeBackGuard, carried in the reader's
/// background: appearing installs the guard (once — later
/// appearances are no-ops), and every update (re)arms the
/// reader's swipe handler. There is deliberately NO teardown:
/// the guard outlives any view (see its doc).
struct ReaderSwipeGesture: UIViewControllerRepresentable {
    /// Called on the main thread when a swipe ends: the start point
    /// in window coordinates and the total translation.
    var onSwipe: (CGPoint, CGSize) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        GuardTriggerViewController()
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        SwipeBackGuard.shared.onSwipe = onSwipe
    }

    final class GuardTriggerViewController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            SwipeBackGuard.shared.install(from: self)
        }
    }
}

/// The one owner of the reader's swipe recognizers and the
/// back-gesture veto (REQ-GS-2). Installed ONCE, the first time
/// any drill-down screen appears, and never torn down.
///
/// Why a permanent singleton: the recognizers used to be
/// installed and removed with a background view controller's
/// appearance, and that lifecycle is not reliable under
/// SwiftUI view rebuilds — showing and hiding the bookmarks
/// panel rebuilt the reader's tree and fired the teardown
/// (recognizers removed, back gesture re-enabled) with no
/// balancing reinstall, after which the drawer and chapter
/// turns were dead and any rightward swipe popped to the
/// chapter picker (reproduced Nov 11, 2026: open the
/// bookmarks panel, hide it, swipe — pop). Installation here
/// is idempotent and the state lives in this object, not in
/// any view, so rebuilds cannot take it down; the reader arms
/// its handler on appear and clears it on disappear.
///
/// The veto: the guard is the interactive pop recognizer's
/// delegate for the app's lifetime and answers "never begin"
/// (see gestureRecognizerShouldBegin) — the one mechanism
/// that prohibits rather than postpones. As second layers it
/// is also disabled (re-asserted on every drag, in case the
/// framework turns it back on) and bound by failure
/// requirements to two recognizers that never fail mid-touch
/// — an inert
/// screen-edge pan on the left edge (which also decides
/// nothing; the drawer is the reader's start-zone decision)
/// and the observing pan below, which is what reports reader
/// swipes: it never cancels touches, recognizes simultaneously
/// with everything else (scrolling, taps, the edge strips),
/// ignores a drag as soon as the drag proves to be a vertical
/// scroll, and on end reports the touch's start in the
/// navigation view — the window's own coordinates, the ground
/// truth for where the finger landed — which the reader
/// converts into its own frame and classifies with
/// `ReaderSwipeZones.action`.
final class SwipeBackGuard: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackGuard()

    /// The reader's swipe handler: (start, translation), both
    /// in the navigation view's coordinates.
    var onSwipe: ((CGPoint, CGSize) -> Void)?

    private var installed = false
    private weak var popRecognizer: UIGestureRecognizer?
    private var swipeStart: CGPoint = .zero
    /// Set once a drag proves to be a vertical scroll; its end
    /// is then never reported as a swipe.
    private var swipeIsScroll = false

    /// Installs the recognizers on the navigation controller's
    /// view. Safe to call on every drill-down appearance; only
    /// the first call does anything.
    func install(from vc: UIViewController) {
        guard !installed,
              let navController = vc.navigationController,
              let navView = navController.view,
              let pop = navController.interactivePopGestureRecognizer
        else { return }
        installed = true
        popRecognizer = pop
        SwipeDiag.add("INSTALL from \(SwipeDiag.cls(vc))")
        for r in navView.gestureRecognizers ?? [] {
            SwipeDiag.add("NAVREC \(SwipeDiag.cls(r)) en=\(r.isEnabled)")
        }
        SwipeDiag.add("POP class=\(SwipeDiag.cls(pop))")
        // The veto's core: the guard becomes the pop
        // recognizer's delegate PERMANENTLY (never restored —
        // see gestureRecognizerShouldBegin). In PR #82 this
        // delegate lived on a view controller whose teardown
        // restored the original delegate, taking the veto with
        // it; the singleton outlives every view.
        pop.delegate = self

        let edgePan = UIScreenEdgePanGestureRecognizer(
            target: self, action: #selector(ignoreEdgePan(_:)))
        edgePan.edges = .left
        // The drawer wins the left edge; the back gesture's
        // start there has to wait on this inert recognizer.
        pop.require(toFail: edgePan)
        navView.addGestureRecognizer(edgePan)

        let swipePan = UIPanGestureRecognizer(
            target: self, action: #selector(handleSwipePan(_:)))
        swipePan.cancelsTouchesInView = false
        swipePan.delegate = self
        pop.require(toFail: swipePan)
        navView.addGestureRecognizer(swipePan)

        pop.isEnabled = false
    }

    /// The veto itself: the back gesture may never begin,
    /// on any screen, ever (swiping back is disabled). The
    /// guard is the pop recognizer's delegate for the app's
    /// lifetime, so this answer never depends on a view's
    /// lifecycle. The failure requirements in install(from:)
    /// are only a second layer: a requirement postpones the
    /// pop until the anchor recognizer fails, and a pan the
    /// system cancels mid-drag DOES fail — releasing the pop
    /// in the middle of the swipe (the PR #84 build's leak).
    /// Every other recognizer the guard delegates for (the
    /// observing pan) may always begin.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let answer = gestureRecognizer !== popRecognizer
        SwipeDiag.add("SHOULD-BEGIN \(SwipeDiag.cls(gestureRecognizer)) -> \(answer)")
        return answer
    }

    /// The observing pan must never block the scroll view, the
    /// edge strips, or any other recognizer.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    /// Deliberately no action: this recognizer exists only so
    /// the system's back-swipe has something to wait for.
    @objc private func ignoreEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {}

    @objc private func handleSwipePan(_ pan: UIPanGestureRecognizer) {
        guard let navView = pan.view else { return }
        switch pan.state {
        case .began:
            swipeStart = pan.location(in: navView)
            swipeIsScroll = false
            SwipeDiag.add("PAN began at \(Int(swipeStart.x)),\(Int(swipeStart.y)) popEn=\(popRecognizer?.isEnabled ?? true) popDel=\(SwipeDiag.cls(popRecognizer?.delegate))")
            // Re-assert the disable on every drag: the
            // framework may have turned the recognizer back on
            // since installation. (The failure requirements
            // above are what actually keep it from beginning.)
            popRecognizer?.isEnabled = false
        case .changed:
            // A clearly vertical drag is a scroll, not a swipe:
            // mark it so its end is never reported.
            let t = pan.translation(in: navView)
            if abs(t.y) > 40, abs(t.y) > 1.5 * abs(t.x) {
                swipeIsScroll = true
            }
        case .ended:
            let t = pan.translation(in: navView)
            SwipeDiag.add("PAN ended t=\(Int(t.x)),\(Int(t.y)) scroll=\(swipeIsScroll) armed=\(onSwipe != nil)")
            if !swipeIsScroll {
                onSwipe?(swipeStart, CGSize(width: t.x, height: t.y))
            }
        case .cancelled, .failed:
            SwipeDiag.add("PAN \(pan.state == .cancelled ? "CANCELLED" : "FAILED")")
        default:
            break
        }
    }
}
