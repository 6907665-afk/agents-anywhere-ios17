#if canImport(UIKit)
import SwiftUI
import UIKit

// Establishes horizontal intent before recognition so drawer pans cancel row taps
// without stealing vertical scrolling.
//
// iOS 17 has no `UIGestureRecognizerRepresentable`, so an invisible anchor view
// installs the recognizer on its SwiftUI host instead.
struct SidebarDrawerPanGesture: UIViewRepresentable {
    let progress: CGFloat
    let edgeActivationWidth: CGFloat
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.progress = progress
        context.coordinator.edgeActivationWidth = max(edgeActivationWidth, 0)
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.install(from: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var host: UIView?
        private var recognizer: UIPanGestureRecognizer?

        var progress: CGFloat = 0
        var edgeActivationWidth: CGFloat = 0
        var onBegan: () -> Void = {}
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }

        func install(from view: UIView) {
            guard recognizer == nil, let container = view.superview else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.cancelsTouchesInView = true
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            container.addGestureRecognizer(pan)
            recognizer = pan
            host = container
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            guard let host else { return }
            let translation = pan.translation(in: host).x
            let velocity = pan.velocity(in: host).x

            switch pan.state {
            case .began:
                onBegan()
            case .changed:
                onChanged(translation)
            case .ended:
                onEnded(translation, velocity, false)
            case .cancelled, .failed:
                onEnded(translation, velocity, true)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let view = pan.view
            else {
                return false
            }

            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }

            if progress <= 0.001 {
                let translation = pan.translation(in: view)
                let initialX = pan.location(in: view).x - translation.x
                return initialX <= edgeActivationWidth && velocity.x > 0
            }

            if progress >= 0.999 {
                return velocity.x < 0
            }

            return true
        }
    }
}
#endif
