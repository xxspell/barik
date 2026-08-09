import MarkdownUI
import SwiftUI

extension Theme {
    static let barik = Theme()
        .text {
            ForegroundColor(.white.opacity(0.8))
            BackgroundColor(.clear)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            BackgroundColor(.white.opacity(0.1))
        }
        .codeBlock { configuration in
          ScrollView(.horizontal) {
            configuration.label
              .fixedSize(horizontal: false, vertical: true)
              .relativeLineSpacing(.em(0.225))
              .markdownTextStyle {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
              }
              .padding(16)
          }
          .background(.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .markdownMargin(top: 0, bottom: 16)
        }
        .strong {
            FontWeight(.semibold)
            ForegroundColor(.white)
        }
        .link {
            ForegroundColor(.blue)
        }
        .heading2 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.5))
                    }
            }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.25))
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                }
        }
        .heading5 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.875))
                }
        }
        .heading6 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.85))
                    ForegroundColor(.gray)
                }
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.gray)
                        FontSize(12)
                    }.markdownMargin(bottom: 20)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.25))
        }
        .image { configuration in
            configuration.label.clipShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.25))
                .markdownMargin(top: 0, bottom: 16)
        }
}

/// An `NSViewRepresentable` wrapping `NSImageView` so that multi-frame GIF
/// `NSImage`s animate using their embedded per-frame delays. For a
/// single-frame image (PNG/JPG) `animates = true` is a no-op, so the same
/// view works for both without needing to sniff the image format.
struct AnimatedNSImageRepresentable: NSViewRepresentable {
    let image: NSImage?

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image {
            nsView.image = image
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        guard let image = nsView.image else { return nil }
        return image.size
    }
}

/// A thin wrapper that owns an `ImageLoader` (unmodified, shared with the
/// rest of the app) and feeds its loaded `NSImage?` into
/// `AnimatedNSImageRepresentable`. Unlike `FadeAnimatedCachedImage`, it has
/// no cross-fade-on-url-change transition: for a markdown image element the
/// `url` is fixed for the element's lifetime, so that code path is never
/// reached here.
struct AnimatedWebImage: View {
    let url: URL?
    let targetSize: CGSize?

    @StateObject private var loader: ImageLoader
    @State private var displayedImage: NSImage?

    init(url: URL?, targetSize: CGSize? = nil) {
        self.url = url
        self.targetSize = targetSize
        _loader = StateObject(wrappedValue: ImageLoader(url: url, targetSize: targetSize))
    }

    var body: some View {
        Group {
            if let displayedImage {
                AnimatedNSImageRepresentable(image: displayedImage)
            } else {
                Color.clear
            }
        }
        .onAppear { loader.load() }
        .onReceive(loader.$image) { newImage in
            displayedImage = newImage
        }
        .onChange(of: url) { _, newURL in
            loader.url = newURL
            loader.load()
        }
    }
}

struct WebImageProvider: ImageProvider {
  func makeImage(url: URL?) -> some View {
    ResizeToFit {
        AnimatedWebImage(url: url)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }
}

/// A layout that resizes its content to fit the container **only** if the content width is greater than the container width.
struct ResizeToFit: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let view = subviews.first else {
      return .zero
    }

    var size = view.sizeThatFits(.unspecified)

    if let width = proposal.width, size.width > width {
      let aspectRatio = size.width / size.height
      size.width = width
      size.height = width / aspectRatio
    }
    return size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard let view = subviews.first else { return }
    view.place(at: bounds.origin, proposal: .init(bounds.size))
  }
}
