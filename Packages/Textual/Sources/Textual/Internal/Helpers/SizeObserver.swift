import SwiftUI

// MARK: - iOS 17 compatibility shims
//
// `onGeometryChange(for:of:action:)` and `onScrollGeometryChange` are iOS 18 APIs.
// These observers reproduce the same "report the container size" behaviour with
// APIs available on iOS 17 (`GeometryReader` + preference-free `onChange`).

/// Reports the size of the view it is attached to as a background.
struct SizeObserver: View {
  var onChange: (CGSize) -> Void

  var body: some View {
    GeometryReader { geometry in
      Color.clear
        .onAppear { onChange(geometry.size) }
        .onChange(of: geometry.size) { _, newValue in
          onChange(newValue)
        }
    }
    .allowsHitTesting(false)
  }
}

/// Reports the size of the `.textContainer` named coordinate space.
struct TextContainerSizeObserver: View {
  var onChange: (CGSize) -> Void

  var body: some View {
    GeometryReader { geometry in
      Color.clear
        .onAppear {
          if let size = geometry.compatTextContainerSize { onChange(size) }
        }
        .onChange(of: geometry.compatTextContainerSize) { _, newValue in
          if let newValue { onChange(newValue) }
        }
    }
    .allowsHitTesting(false)
  }
}

extension GeometryProxy {
  fileprivate var compatTextContainerSize: CGSize? {
    bounds(of: .textContainer)?.size
  }
}
