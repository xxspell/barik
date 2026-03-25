import SwiftUI

private enum NowPlayingWidgetLayout {
    static let compactHeight: CGFloat = 34
    static let capsuleHeight: CGFloat = 28
    static let albumArtSize: CGFloat = 18
}

// MARK: - Now Playing Widget

struct NowPlayingWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject var playingManager = NowPlayingManager.shared

    @State private var widgetFrame: CGRect = .zero
    @State private var animatedWidth: CGFloat = 0

    private var showAlbumArt: Bool { configProvider.config["show-album-art"]?.boolValue ?? true }
    private var showArtist: Bool { configProvider.config["show-artist"]?.boolValue ?? true }
    private var showPauseIndicator: Bool { configProvider.config["show-pause-indicator"]?.boolValue ?? true }

    var body: some View {
        ZStack(alignment: .trailing) {
            if let song = playingManager.nowPlaying {
                // Hidden view for measuring the intrinsic width.
                MeasurableNowPlayingContent(
                    song: song,
                    showAlbumArt: showAlbumArt,
                    showArtist: showArtist,
                    showPauseIndicator: showPauseIndicator
                ) { measuredWidth in
                    if animatedWidth == 0 {
                        animatedWidth = measuredWidth
                    } else if animatedWidth != measuredWidth {
                        withAnimation(.smooth) {
                            animatedWidth = measuredWidth
                        }
                    }
                }
                .hidden()

                // Visible content with fixed animated width.
                VisibleNowPlayingContent(
                    song: song,
                    width: animatedWidth,
                    showAlbumArt: showAlbumArt,
                    showArtist: showArtist,
                    showPauseIndicator: showPauseIndicator
                )
                    .onTapGesture {
                        MenuBarPopup.show(rect: widgetFrame, id: "nowplaying") {
                            NowPlayingPopup(configProvider: configProvider)
                        }
                    }
            }
        }
        .captureScreenRect(into: $widgetFrame)
    }
}

// MARK: - Now Playing Content

/// A view that composes the album art and song text into a capsule-shaped content view.
struct NowPlayingContent: View {
    let song: NowPlayingSong
    let showAlbumArt: Bool
    let showArtist: Bool
    let showPauseIndicator: Bool
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    
    var body: some View {
        Group {
            if foregroundHeight < 38 {
                HStack(spacing: 8) {
                    if showAlbumArt {
                        AlbumArtView(song: song, showPauseIndicator: showPauseIndicator)
                    }
                    SongTextView(song: song, showArtist: showArtist)
                }
            } else {
                HStack(spacing: 8) {
                    if showAlbumArt {
                        AlbumArtView(song: song, showPauseIndicator: showPauseIndicator)
                    }
                    SongTextView(song: song, showArtist: showArtist)
                }
                .padding(.horizontal, foregroundHeight < 45 ? 8 : 12)
                .frame(height: foregroundHeight < 45 ? NowPlayingWidgetLayout.capsuleHeight : NowPlayingWidgetLayout.compactHeight)
                .background(configManager.config.experimental.foreground.widgetsBackground.blur)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.noActive, lineWidth: 1)
                )
            }
        }
        .foregroundColor(.foreground)
    }
}

// MARK: - Measurable Now Playing Content

/// A wrapper view that measures the intrinsic width of the now playing content.
struct MeasurableNowPlayingContent: View {
    let song: NowPlayingSong
    let showAlbumArt: Bool
    let showArtist: Bool
    let showPauseIndicator: Bool
    let onSizeChange: (CGFloat) -> Void

    var body: some View {
        NowPlayingContent(
            song: song,
            showAlbumArt: showAlbumArt,
            showArtist: showArtist,
            showPauseIndicator: showPauseIndicator
        )
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            onSizeChange(geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            onSizeChange(newWidth)
                        }
                }
            )
    }
}

// MARK: - Visible Now Playing Content

/// A view that displays now playing content with a fixed, animated width and transition.
struct VisibleNowPlayingContent: View {
    let song: NowPlayingSong
    let width: CGFloat
    let showAlbumArt: Bool
    let showArtist: Bool
    let showPauseIndicator: Bool

    var body: some View {
        NowPlayingContent(
            song: song,
            showAlbumArt: showAlbumArt,
            showArtist: showArtist,
            showPauseIndicator: showPauseIndicator
        )
            .frame(width: width, height: NowPlayingWidgetLayout.compactHeight)
            .animation(.smooth(duration: 0.1), value: song)
            .transition(.blurReplace)
    }
}

// MARK: - Album Art View

/// A view that displays the album art with a fade animation and a pause indicator if needed.
struct AlbumArtView: View {
    let song: NowPlayingSong
    let showPauseIndicator: Bool

    var body: some View {
        ZStack {
            // Use in-memory image if available, otherwise use URL-based cached image
            if let albumArtImage = song.albumArtImage {
                // Directly display the NSImage
                Image(nsImage: albumArtImage)
                    .resizable()
                    .frame(width: NowPlayingWidgetLayout.albumArtSize, height: NowPlayingWidgetLayout.albumArtSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .scaleEffect(song.state == .paused ? 0.9 : 1)
                    .brightness(song.state == .paused ? -0.3 : 0)
            } else if let albumArtURL = song.albumArtURL {
                // Fallback to URL-based caching system
                FadeAnimatedCachedImage(
                    url: albumArtURL,
                    targetSize: CGSize(width: NowPlayingWidgetLayout.albumArtSize, height: NowPlayingWidgetLayout.albumArtSize)
                )
                .frame(width: NowPlayingWidgetLayout.albumArtSize, height: NowPlayingWidgetLayout.albumArtSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .scaleEffect(song.state == .paused ? 0.9 : 1)
                .brightness(song.state == .paused ? -0.3 : 0)
            } else {
                // Placeholder when no image is available
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: NowPlayingWidgetLayout.albumArtSize, height: NowPlayingWidgetLayout.albumArtSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if showPauseIndicator && song.state == .paused {
                Image(systemName: "pause.fill")
                    .foregroundColor(.icon)
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.1), value: song.state == .paused)
    }
}

// MARK: - Song Text View

/// A view that displays the song title and artist.
struct SongTextView: View {
    let song: NowPlayingSong
    let showArtist: Bool
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {

        VStack(alignment: .leading, spacing: -1) {
            if foregroundHeight >= 30 {
                Text(song.title)
                    .font(.system(size: 11))
                    .fontWeight(.medium)
                    .padding(.trailing, 2)
                if showArtist {
                    Text(song.artist)
                        .opacity(0.8)
                        .font(.system(size: 10))
                        .padding(.trailing, 2)
                }
            } else {
                Text(showArtist ? song.artist + " — " + song.title : song.title)
                    .font(.system(size: 12))
            }
        }
        // Disable animations for text changes.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

// MARK: - Preview

struct NowPlayingWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            NowPlayingWidget()
        }
        .frame(width: 500, height: 100)
    }
}
