import SwiftUI

// MARK: - iOS 17 runtime compatibility layer
//
// The upstream client is built against iOS 26 (Liquid Glass, iOS 18 scroll APIs).
// This file keeps the upstream call sites nearly unchanged while providing
// implementations that exist on iOS 17:
//
//   .glassEffect(...)              -> .aaGlass(...)
//   GlassEffectContainer           -> AAGlassEffectContainer
//   .glassEffectID(...)            -> .aaGlassEffectID(...)
//   .buttonStyle(.glass[Prominent])-> .aaGlassButtonStyle(...)
//   .scrollEdgeEffectStyle(...)    -> .aaScrollEdgeEffectStyle(...)
//
// On iOS 26 and later every helper forwards to the native API, so behaviour is
// unchanged on a current device.

extension View {
    /// `.glassEffect(_:in:)` replacement.
    @ViewBuilder
    func aaGlass<S: Shape>(interactive: Bool = false, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                }
                .clipShape(shape)
        }
    }

    /// `.glassEffectID(_:in:)` replacement. No-op before iOS 26.
    @ViewBuilder
    func aaGlassEffectID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// `.glass` / `.glassProminent` button style replacement.
    @ViewBuilder
    func aaGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// `.scrollEdgeEffectStyle(_:for:)` replacement. No-op before iOS 26.
    @ViewBuilder
    func aaScrollEdgeEffectStyle(_ style: AAScrollEdgeEffectStyle, for edges: Edge.Set) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .soft:
                self.scrollEdgeEffectStyle(.soft, for: edges)
            case .hard:
                self.scrollEdgeEffectStyle(.hard, for: edges)
            }
        } else {
            self
        }
    }
}

/// `ScrollEdgeEffectStyle` replacement.
enum AAScrollEdgeEffectStyle {
    case soft
    case hard
}

extension View {
    /// `onScrollVisibilityChange(threshold:_:)` replacement (iOS 18).
    ///
    /// The affected views live in the timeline's lazy stack, so appearing and
    /// disappearing tracks visibility closely enough for prompt and tail
    /// detection.
    func aaScrollVisibility(_ handler: @escaping (Bool) -> Void) -> some View {
        self
            .onAppear { handler(true) }
            .onDisappear { handler(false) }
    }
}

/// `GlassEffectContainer` replacement.
struct AAGlassEffectContainer<Content: View>: View {
    var spacing: CGFloat = 0

    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            ZStack {
                content
            }
        }
    }
}
