import SwiftUI
import UIKit

// MARK: - iOS 17 scroll bridge
//
// iOS 18 replaced the old scroll callbacks with `ScrollPosition`,
// `onScrollPhaseChange`, `onScrollGeometryChange` and `onScrollVisibilityChange`.
// This bridge exposes the same information from the underlying `UIScrollView` so
// the timeline keeps its opening, history restoration and return-to-bottom
// behaviour on iOS 17.
//
// The scroll view is never re-delegated: `UIScrollView.delegate` stays owned by
// SwiftUI. Geometry is observed with key-value observation, and the scroll phase
// comes from the pan gesture recognizer plus `isDecelerating`.

enum AAScrollPhase {
    case idle
    case tracking
    case interacting
    case decelerating
    case animating
}

/// Reports the geometry and phase of the nearest enclosing `UIScrollView`.
struct AAScrollViewReader: UIViewRepresentable {
    var onAttach: ((UIScrollView, AAScrollProbeView) -> Void)?
    var onGeometry: ((UIScrollView) -> Void)?
    var onPhase: ((AAScrollPhase, UIScrollView) -> Void)?

    func makeUIView(context: Context) -> AAScrollProbeView {
        let view = AAScrollProbeView()
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: AAScrollProbeView, context: Context) {
        apply(to: uiView)
        uiView.resolveScrollView()
    }

    private func apply(to view: AAScrollProbeView) {
        view.onAttach = onAttach
        view.onGeometry = onGeometry
        view.onPhase = onPhase
    }
}

final class AAScrollProbeView: UIView {
    var onAttach: ((UIScrollView, AAScrollProbeView) -> Void)?
    var onGeometry: ((UIScrollView) -> Void)?
    var onPhase: ((AAScrollPhase, UIScrollView) -> Void)?

    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var lastPhase: AAScrollPhase = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleResolve()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        scheduleResolve()
    }

    /// Resolve after the current layout pass: attaching observers synchronously
    /// from a layout callback would publish state while SwiftUI is laying out.
    private func scheduleResolve() {
        guard scrollView == nil else { return }
        DispatchQueue.main.async { [weak self] in self?.resolveScrollView() }
    }

    func resolveScrollView() {
        guard scrollView == nil else { return }
        var candidate: UIView? = superview
        while let view = candidate {
            if let found = view as? UIScrollView {
                attach(to: found)
                return
            }
            candidate = view.superview
        }
    }

    private func attach(to scrollView: UIScrollView) {
        self.scrollView = scrollView

        observations = [
            scrollView.observe(\.contentOffset) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let live = self.scrollView else { return }
                    self.refreshPhase(from: live)
                    self.onGeometry?(live)
                }
            },
            scrollView.observe(\.contentSize) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let live = self.scrollView else { return }
                    self.onGeometry?(live)
                }
            },
            scrollView.observe(\.contentInset) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let live = self.scrollView else { return }
                    self.onGeometry?(live)
                }
            },
            scrollView.observe(\.isDecelerating) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let live = self.scrollView else { return }
                    self.report(live.isDecelerating ? .decelerating : .idle, live)
                    self.onGeometry?(live)
                }
            },
        ]

        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))

        onGeometry?(scrollView)
        onAttach?(scrollView, self)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let scrollView else { return }
        switch recognizer.state {
        case .began:
            report(.tracking, scrollView)
        case .changed:
            report(scrollView.isDragging ? .interacting : .tracking, scrollView)
        case .ended, .cancelled, .failed:
            report(scrollView.isDecelerating ? .decelerating : .idle, scrollView)
        default:
            break
        }
    }

    /// Programmatic offsets keep the current phase, but a drag or deceleration
    /// must take over immediately when the user grabs the list again.
    private func refreshPhase(from scrollView: UIScrollView) {
        if scrollView.isDecelerating {
            report(.decelerating, scrollView)
        } else if scrollView.isDragging {
            report(.interacting, scrollView)
        }
    }

    private func report(_ phase: AAScrollPhase, _ scrollView: UIScrollView) {
        guard phase != lastPhase else { return }
        lastPhase = phase
        onPhase?(phase, scrollView)
    }

    /// Used by `AAScrollPosition` so a programmatic animation reports the same
    /// phases the native scroll callbacks would.
    func reportExternal(_ phase: AAScrollPhase, scrollView: UIScrollView) {
        lastPhase = phase
        onPhase?(phase, scrollView)
    }
}

/// Stand-in for iOS 18's `ScrollPosition`.
///
/// Only the surface the timeline uses is implemented: user-positioned intent plus
/// edge and point scrolling commands forwarded to the attached scroll view.
@MainActor
final class AAScrollPosition {
    var isPositionedByUser = false

    private(set) var edge: VerticalEdge?
    private(set) var point: CGPoint?

    fileprivate weak var scrollView: UIScrollView?
    fileprivate weak var probe: AAScrollProbeView?

    func attach(_ scrollView: UIScrollView, probe: AAScrollProbeView) {
        self.scrollView = scrollView
        self.probe = probe
    }

    func scrollTo(edge: VerticalEdge) {
        self.edge = edge
        point = nil
        guard let scrollView else { return }

        let top = -scrollView.adjustedContentInset.top
        let bottom = max(top,
                         scrollView.contentSize.height
                            + scrollView.adjustedContentInset.bottom
                            - scrollView.bounds.height)
        let target = edge == .bottom ? bottom : top

        probe?.reportExternal(.animating, scrollView: scrollView)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: true)

        // UIScrollView gives no completion callback for animated offsets; report
        // the settled phase after the default animation window instead.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(340))
            guard let self, let scrollView = self.scrollView, let probe = self.probe else { return }
            probe.reportExternal(scrollView.isDecelerating ? .decelerating : .idle, scrollView: scrollView)
        }
    }

    func scrollTo(y: CGFloat) {
        point = CGPoint(x: 0, y: y)
        edge = nil
        guard let scrollView else { return }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
    }
}

extension TimelineViewport {
    init(scrollView: UIScrollView) {
        self.init(
            contentHeight: scrollView.contentSize.height,
            containerHeight: scrollView.bounds.height,
            topInset: scrollView.adjustedContentInset.top,
            bottomInset: scrollView.adjustedContentInset.bottom,
            offsetY: scrollView.contentOffset.y
        )
    }
}
