import SwiftUI

// MARK: - Overview
//
// TextBuilder constructs SwiftUI.Text from attributed content with inline attachments.
// It caches Text values keyed by attachment sizes to avoid unnecessary rebuilds during
// resize. When the container size changes, attachment sizes are recomputed and the cache
// is consulted. If the new sizes hash to the same key, the cached Text is reused.
//
// The cache key is derived from the hash of [AttachmentKey: CGSize]. Since attachment
// sizes often remain constant or repeat during incremental resize (e.g., window resizing),
// this compact key enables effective caching without storing the full proposal or
// attributed string. The cache has a count limit of 10 to prevent unbounded growth.
//
// Runs with attachments are converted to placeholder images sized by the attachment's
// sizeThatFits(_:in:) result. Placeholders are tagged with AttachmentAttribute so overlays
// can identify and render the actual attachment views at the resolved layout positions.

extension TextFragment {
  @MainActor @Observable final class TextBuilder {
    var text: Text

    @ObservationIgnored private var currentAttachmentSizes: [AttachmentKey: CGSize]
    @ObservationIgnored private let content: Content
    @ObservationIgnored let attachments: Set<AnyAttachment>
    @ObservationIgnored let hasLinks: Bool
    @ObservationIgnored private let cache: NSCache<KeyBox<AttachmentSizesCacheKey>, Box<Text>>

    init(_ content: Content, environment: TextEnvironmentValues) {
      let attachmentSizes = content.attachmentSizes(for: .unspecified, in: environment)

      self.text = Text(
        attributedString: content,
        attachmentSizes: attachmentSizes,
        in: environment
      )
      self.currentAttachmentSizes = attachmentSizes
      self.content = content
      self.attachments = content.attachments()
      self.hasLinks = content.runs.contains { $0.link != nil }
      self.cache = NSCache()
      self.cache.countLimit = 10

      self.cache.setObject(Box(self.text), forKey: KeyBox(AttachmentSizesCacheKey(sizes: attachmentSizes)))
    }

    func sizeChanged(_ size: CGSize, environment: TextEnvironmentValues) {
      // Plain text cannot change when the attachment container resizes.
      guard !currentAttachmentSizes.isEmpty else { return }
      let attachmentSizes = content.attachmentSizes(for: .init(size), in: environment)
      guard attachmentSizes != currentAttachmentSizes else { return }
      currentAttachmentSizes = attachmentSizes
      let cacheKey = KeyBox(AttachmentSizesCacheKey(sizes: attachmentSizes))

      if let text = cache.object(forKey: cacheKey) {
        self.text = text.wrappedValue
      } else {
        let text = Text(
          attributedString: content,
          attachmentSizes: attachmentSizes,
          in: environment
        )
        cache.setObject(Box(text), forKey: cacheKey)

        self.text = text
      }
    }
  }
}

extension Text {
  fileprivate init(
    attributedString: some AttributedStringProtocol,
    attachmentSizes: [AttachmentKey: CGSize],
    in environment: TextEnvironmentValues
  ) {
    let textValues = attributedString.runs.map { run in
      var text: Text

      var runEnvironment = environment
      runEnvironment.font = run.font ?? environment.font

      let key = run.textual.attachment.map {
        AttachmentKey(attachment: $0, font: runEnvironment.font)
      }

      if let key, let size = attachmentSizes[key] {
        // Create placeholder
        text = Text(placeholderSize: size)
          .baselineOffset(key.attachment.baselineOffset(in: runEnvironment))
          .customAttribute(
            AttachmentAttribute(
              key.attachment,
              presentationIntent: run.presentationIntent
            )
          )
      } else {
        text = Text(AttributedString(attributedString[run.range]))
      }

      // Add link attribute for TextLinkInteraction
      if let link = run.link {
        text = text.customAttribute(LinkAttribute(link))
      }

      return text
    }

    self = textValues.reduce(Text(verbatim: "")) { partialResult, text in
      partialResult + text
    }
  }

  private init(placeholderSize size: CGSize) {
    self.init(SwiftUI.Image(size: size) { _ in })
  }
}

extension AttributedStringProtocol {
  fileprivate func attachmentSizes(
    for proposal: ProposedViewSize, in environment: TextEnvironmentValues
  ) -> [AttachmentKey: CGSize] {
    Dictionary(
      self.runs.compactMap { run in
        guard let attachment = run.textual.attachment else {
          return nil
        }
        var environment = environment
        environment.font = run.font ?? environment.font
        return (
          AttachmentKey(
            attachment: attachment,
            font: environment.font
          ),
          attachment.sizeThatFits(proposal, in: environment)
        )
      },
      uniquingKeysWith: { existing, _ in existing }
    )
  }
}

private struct AttachmentKey: Hashable {
  let attachment: AnyAttachment
  let font: Font?
}

/// iOS 17 compatibility: `CGSize` only conforms to `Hashable` from iOS 18 on, and
/// `Dictionary` is not `Hashable`, so the cache key hashes the size bit patterns
/// explicitly while equality keeps using the dictionary's own comparison.
private struct AttachmentSizesCacheKey: Hashable {
  let sizes: [AttachmentKey: CGSize]

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sizes == rhs.sizes
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(sizes.count)
    for (key, size) in sizes {
      hasher.combine(key)
      hasher.combine(size.width.bitPattern)
      hasher.combine(size.height.bitPattern)
    }
  }
}
