import SwiftUI

private enum NowPlayingWidgetLayout {
    static let compactHeight: CGFloat = 34
    static let capsuleHeight: CGFloat = 28
    static let albumArtSize: CGFloat = 18
}

// MARK: - Now Playing Widget

struct NowPlayingWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject var playingManager = NowPlayingManager.shared

    @State private var widgetFrame: CGRect = .zero
    @State private var animatedWidth: CGFloat = 0
    @State private var pauseHideWorkItem: DispatchWorkItem?
    @State private var pauseVisibilityRevision = 0

    private var liveConfig: ConfigData {
        configManager.globalWidgetConfig(for: "default.nowplaying")
    }

    private var showAlbumArt: Bool { liveConfig["show-album-art"]?.boolValue ?? true }
    private var showArtist: Bool { liveConfig["show-artist"]?.boolValue ?? true }
    private var showPauseIndicator: Bool { liveConfig["show-pause-indicator"]?.boolValue ?? true }
    private var backgroundFillEnabled: Bool { liveConfig["background-fill-enabled"]?.boolValue ?? false }
    private var backgroundFillSource: String { liveConfig["background-fill-source"]?.stringValue ?? "accent" }
    private var backgroundFillColorHex: String { liveConfig["background-fill-color"]?.stringValue ?? "#4A90E2" }
    private var hideAfterPausedMinutes: Int { liveConfig["hide-after-paused-minutes"]?.intValue ?? 10 }
    private var maxCharactersPerLine: Int { max(liveConfig["max-characters-per-line"]?.intValue ?? 25, 1) }
    private var scrollLongText: Bool { liveConfig["scroll-long-text"]?.boolValue ?? false }

    private var visibleSong: NowPlayingSong? {
        guard let song = playingManager.nowPlaying else { return nil }
        guard song.state == .paused else { return song }
        let hideAfterSeconds = Double(hideAfterPausedMinutes * 60)
        return Date().timeIntervalSince(song.stateTimestamp) >= hideAfterSeconds ? nil : song
    }

    @Environment(\.isBarikExporting) private var isExporting

    private var pauseRefreshKey: String {
        guard let song = playingManager.nowPlaying else { return "none:\(hideAfterPausedMinutes)" }
        return "\(song.id):\(song.state.rawValue):\(song.stateTimestamp.timeIntervalSinceReferenceDate):\(hideAfterPausedMinutes)"
    }

    var body: some View {
        BarikStyle.current.isTUI ? AnyView(tuiBody) : AnyView(defaultBody)
    }

    private var tuiBody: some View {
        let style = BarikStyle.current
        return Group {
            if let song = visibleSong {
                TimelineView(.animation(minimumInterval: 1)) { context in
                    let progress = tuiPlaybackProgress(for: song, at: context.date)
                    HStack(spacing: 5) {
                        Image(systemName: song.state == .paused ? "pause.fill" : "music.note")
                            .barikFont(size: 10)
                        Text(tuiText(for: song))
                            .barikFont(size: 12, weight: .regular)
                            .lineLimit(1)
                    }
                    .foregroundStyle(style.dim)
                    .padding(.horizontal, BarikStyle.tuiChipHPadding)
                    .frame(height: BarikStyle.tuiChipHeight)
                    .background {
                        ZStack {
                            if style.chipEnabled {
                                RoundedRectangle(cornerRadius: style.chipCornerRadius, style: .continuous)
                                    .fill(style.chipFillStyle(isExporting: isExporting))
                            }
                            if backgroundFillEnabled {
                                tuiFillLayer(progress: progress)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: style.chipCornerRadius, style: .continuous))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        MenuBarPopup.show(rect: widgetFrame, id: "nowplaying") {
                            NowPlayingPopup(configProvider: configProvider)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .captureScreenRect(into: $widgetFrame)
        .onAppear(perform: schedulePauseVisibilityRefresh)
        .onChange(of: pauseRefreshKey) { _, _ in
            schedulePauseVisibilityRefresh()
        }
        .onReceive(configManager.$config) { _ in
            schedulePauseVisibilityRefresh()
        }
        .onDisappear {
            pauseHideWorkItem?.cancel()
            pauseHideWorkItem = nil
        }
    }

    private func tuiText(for song: NowPlayingSong) -> String {
        let base = (showArtist && !song.artist.isEmpty) ? "\(song.title) — \(song.artist)" : song.title
        let maxLen = maxCharactersPerLine
        guard base.count > maxLen, maxLen > 2 else { return base }
        return String(base.prefix(maxLen - 2)) + ".."
    }

    private func tuiPlaybackProgress(for song: NowPlayingSong, at date: Date) -> CGFloat {
        guard let duration = song.duration, duration > 0, let base = song.position else { return 0 }
        let pos: Double
        if song.state == .playing, let timestamp = song.positionTimestamp {
            pos = base + max(date.timeIntervalSince(timestamp), 0)
        } else {
            pos = base
        }
        return CGFloat(min(max(pos / duration, 0), 1))
    }

    private var tuiFillColor: Color {
        if backgroundFillSource == "custom", let custom = Color(hex: backgroundFillColorHex) {
            return custom
        }
        return BarikStyle.current.accent
    }

    private func tuiFillLayer(progress: CGFloat) -> some View {
        let color = tuiFillColor
        return GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let progressWidth = totalWidth * progress
            let feather: CGFloat = 16

            HStack(spacing: 0) {
                Rectangle()
                    .fill(color.opacity(0.22))
                    .frame(width: max(progressWidth - feather, 0))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: min(progressWidth, feather))
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var defaultBody: some View {
        let _ = pauseVisibilityRevision
        ZStack(alignment: .trailing) {
            if let song = visibleSong {
                // Hidden view for measuring the intrinsic width.
                MeasurableNowPlayingContent(
                    song: song,
                    showAlbumArt: showAlbumArt,
                    showArtist: showArtist,
                    showPauseIndicator: showPauseIndicator,
                    backgroundFillEnabled: backgroundFillEnabled,
                    backgroundFillSource: backgroundFillSource,
                    backgroundFillColorHex: backgroundFillColorHex,
                    maxCharactersPerLine: maxCharactersPerLine,
                    scrollLongText: scrollLongText
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
                    showPauseIndicator: showPauseIndicator,
                    backgroundFillEnabled: backgroundFillEnabled,
                    backgroundFillSource: backgroundFillSource,
                    backgroundFillColorHex: backgroundFillColorHex,
                    maxCharactersPerLine: maxCharactersPerLine,
                    scrollLongText: scrollLongText
                )
                    .onTapGesture {
                        MenuBarPopup.show(rect: widgetFrame, id: "nowplaying") {
                            NowPlayingPopup(configProvider: configProvider)
                        }
                    }
            }
        }
        .captureScreenRect(into: $widgetFrame)
        .onAppear(perform: schedulePauseVisibilityRefresh)
        .onChange(of: pauseRefreshKey) { _, _ in
            schedulePauseVisibilityRefresh()
        }
        .onReceive(configManager.$config) { _ in
            schedulePauseVisibilityRefresh()
        }
        .onDisappear {
            pauseHideWorkItem?.cancel()
            pauseHideWorkItem = nil
        }
    }

    private func schedulePauseVisibilityRefresh() {
        pauseHideWorkItem?.cancel()
        pauseHideWorkItem = nil

        guard let song = playingManager.nowPlaying, song.state == .paused else { return }

        let hideAfterSeconds = Double(hideAfterPausedMinutes * 60)
        let delay = hideAfterSeconds - Date().timeIntervalSince(song.stateTimestamp)
        guard delay > 0 else {
            pauseVisibilityRevision += 1
            return
        }

        let workItem = DispatchWorkItem {
            pauseVisibilityRevision += 1
        }
        pauseHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// MARK: - Now Playing Content

/// A view that composes the album art and song text into a capsule-shaped content view.
struct NowPlayingContent: View {
    let song: NowPlayingSong
    let showAlbumArt: Bool
    let showArtist: Bool
    let showPauseIndicator: Bool
    let backgroundFillEnabled: Bool
    let backgroundFillSource: String
    let backgroundFillColorHex: String
    let maxCharactersPerLine: Int
    let scrollLongText: Bool
    @ObservedObject var configManager = ConfigManager.shared
    @Environment(\.isBarikExporting) private var isExporting
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    private var backgroundFillColor: Color {
        if backgroundFillSource == "custom", let customColor = Color(hex: backgroundFillColorHex) {
            return customColor
        }
        return .accentColor
    }
    private func estimatedPosition(at date: Date) -> Double {
        guard let basePosition = song.position else {
            return 0
        }

        let progressedPosition: Double
        if song.state == .playing,
           let timestamp = song.positionTimestamp {
            progressedPosition = basePosition + max(date.timeIntervalSince(timestamp), 0)
        } else {
            progressedPosition = basePosition
        }

        if let duration = song.duration {
            return min(max(progressedPosition, 0), duration)
        }

        return max(progressedPosition, 0)
    }

    private func playbackProgress(at date: Date) -> CGFloat {
        guard let duration = song.duration, duration > 0 else {
            return 0
        }

        let progress = estimatedPosition(at: date) / duration
        return CGFloat(min(max(progress, 0), 1))
    }

    @ViewBuilder
    private func backgroundFillLayer(for date: Date) -> some View {
        GeometryReader { geometry in
            let progress = playbackProgress(at: date)
            let totalWidth = geometry.size.width
            let progressWidth = totalWidth * progress
            let featherWidth = min(max(totalWidth * 0.045, 16), 34)

            ZStack(alignment: .leading) {
                Capsule().fill(.clear)

                if progress > 0.001 {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(backgroundFillColor.opacity(0.12))
                            .frame(width: max(progressWidth - featherWidth, 0))

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        backgroundFillColor.opacity(0.12),
                                        backgroundFillColor.opacity(0.08),
                                        backgroundFillColor.opacity(0.03),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: min(progressWidth, featherWidth))

                        Spacer(minLength: 0)
                    }
                    .mask(Capsule())
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1)) { context in
            if foregroundHeight < 38 {
                ZStack(alignment: .leading) {
                    if backgroundFillEnabled {
                        backgroundFillLayer(for: context.date)
                    }

                    HStack(spacing: 8) {
                        if showAlbumArt {
                            AlbumArtView(song: song, showPauseIndicator: showPauseIndicator)
                        }
                        SongTextView(song: song, showArtist: showArtist, maxCharactersPerLine: maxCharactersPerLine, scrollLongText: scrollLongText)
                    }
                }
                .foregroundColor(.foreground)
            } else {
                HStack(spacing: 8) {
                    if showAlbumArt {
                        AlbumArtView(song: song, showPauseIndicator: showPauseIndicator)
                    }
                    SongTextView(song: song, showArtist: showArtist, maxCharactersPerLine: maxCharactersPerLine, scrollLongText: scrollLongText)
                }
                .padding(.horizontal, foregroundHeight < 45 ? 8 : 12)
                .frame(height: foregroundHeight < 45 ? NowPlayingWidgetLayout.capsuleHeight : NowPlayingWidgetLayout.compactHeight)
                .background {
                    ZStack {
                        Capsule().fill(configManager.config.experimental.foreground.widgetsBackground.fillStyle(isExporting: isExporting))
                        if backgroundFillEnabled {
                            backgroundFillLayer(for: context.date)
                        }
                    }
                }
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.noActive, lineWidth: 1)
                )
                .foregroundColor(.foreground)
            }
        }
    }
}

// MARK: - Measurable Now Playing Content

/// A wrapper view that measures the intrinsic width of the now playing content.
struct MeasurableNowPlayingContent: View {
    let song: NowPlayingSong
    let showAlbumArt: Bool
    let showArtist: Bool
    let showPauseIndicator: Bool
    let backgroundFillEnabled: Bool
    let backgroundFillSource: String
    let backgroundFillColorHex: String
    let maxCharactersPerLine: Int
    let scrollLongText: Bool
    let onSizeChange: (CGFloat) -> Void
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {
        HStack(spacing: 8) {
            if showAlbumArt {
                AlbumArtView(song: song, showPauseIndicator: showPauseIndicator)
            }
            StaticSongTextView(
                song: song,
                showArtist: showArtist,
                maxCharactersPerLine: maxCharactersPerLine
            )
        }
        .padding(.horizontal, foregroundHeight < 38 ? 0 : (foregroundHeight < 45 ? 8 : 12))
        .frame(height: foregroundHeight < 45 ? NowPlayingWidgetLayout.capsuleHeight : NowPlayingWidgetLayout.compactHeight)
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
    let backgroundFillEnabled: Bool
    let backgroundFillSource: String
    let backgroundFillColorHex: String
    let maxCharactersPerLine: Int
    let scrollLongText: Bool

    var body: some View {
        NowPlayingContent(
            song: song,
            showAlbumArt: showAlbumArt,
            showArtist: showArtist,
            showPauseIndicator: showPauseIndicator,
            backgroundFillEnabled: backgroundFillEnabled,
            backgroundFillSource: backgroundFillSource,
            backgroundFillColorHex: backgroundFillColorHex,
            maxCharactersPerLine: maxCharactersPerLine,
            scrollLongText: scrollLongText
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
    let maxCharactersPerLine: Int
    let scrollLongText: Bool
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {

        VStack(alignment: .leading, spacing: -1) {
            if foregroundHeight >= 30 {
                WidgetTextLine(text: song.title, maxCharacters: maxCharactersPerLine, fontSize: 11, weight: .medium, scrollLongText: scrollLongText)
                if showArtist {
                    WidgetTextLine(text: song.artist, maxCharacters: maxCharactersPerLine, fontSize: 10, weight: .regular, scrollLongText: scrollLongText, opacity: 0.8)
                }
            } else {
                WidgetTextLine(text: showArtist ? song.artist + " — " + song.title : song.title, maxCharacters: maxCharactersPerLine, fontSize: 12, weight: .regular, scrollLongText: scrollLongText)
            }
        }
        // Disable animations for text changes.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct StaticSongTextView: View {
    let song: NowPlayingSong
    let showArtist: Bool
    let maxCharactersPerLine: Int
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            if foregroundHeight >= 30 {
                Text(Self.truncated(song.title, maxCharacters: maxCharactersPerLine))
                    .barikFont(size: 11, weight: .medium)
                    .lineLimit(1)
                if showArtist {
                    Text(Self.truncated(song.artist, maxCharacters: maxCharactersPerLine))
                        .barikFont(size: 10, weight: .regular)
                        .lineLimit(1)
                        .opacity(0.8)
                }
            } else {
                Text(Self.truncated(showArtist ? song.artist + " — " + song.title : song.title, maxCharacters: maxCharactersPerLine))
                    .barikFont(size: 12, weight: .regular)
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 2)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private static func truncated(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters, maxCharacters > 2 else { return text }
        return String(text.prefix(maxCharacters - 2)) + ".."
    }
}

private struct WidgetTextLine: View {
    let text: String
    let maxCharacters: Int
    let fontSize: CGFloat
    let weight: Font.Weight
    let scrollLongText: Bool
    var opacity: Double = 1

    private var exceedsLimit: Bool { text.count > maxCharacters }
    private var staticPreviewText: String {
        exceedsLimit ? truncatedText : text
    }
    private var truncatedText: String {
        guard exceedsLimit, maxCharacters > 2 else { return text }
        return String(text.prefix(maxCharacters - 2)) + ".."
    }

    var body: some View {
        Group {
            if scrollLongText && exceedsLimit {
                ScrollingTextLine(
                    text: text,
                    previewText: truncatedText,
                    fontSize: fontSize,
                    weight: weight,
                    opacity: opacity
                )
            } else {
                Text(staticPreviewText)
                    .barikFont(size: fontSize, weight: weight)
                    .lineLimit(1)
                    .opacity(opacity)
            }
        }
        .padding(.trailing, 2)
    }
}

private struct ScrollingTextLine: View {
    let text: String
    let previewText: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let opacity: Double

    @State private var textWidth: CGFloat = 0
    @State private var separatorWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private let separator = "     "

    var body: some View {
        Text(previewText)
            .barikFont(size: fontSize, weight: weight)
            .lineLimit(1)
            .hidden()
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { containerWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newValue in
                            containerWidth = newValue
                        }
                }
            )
            .overlay(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1 / 15)) { context in
                    let cycleWidth = textWidth + separatorWidth
                    let shouldScroll = textWidth > containerWidth && cycleWidth > 0
                    let speed: CGFloat = 18
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let offset = shouldScroll
                        ? -CGFloat(elapsed * Double(speed)).truncatingRemainder(dividingBy: cycleWidth)
                        : 0

                    HStack(spacing: 0) {
                        scrollingSegment(text)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear
                                        .onAppear { textWidth = geometry.size.width }
                                        .onChange(of: geometry.size.width) { _, newValue in
                                            textWidth = newValue
                                        }
                                }
                            )
                        scrollingSegment(separator)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear
                                        .onAppear { separatorWidth = geometry.size.width }
                                        .onChange(of: geometry.size.width) { _, newValue in
                                            separatorWidth = newValue
                                        }
                                }
                            )
                        scrollingSegment(text)
                    }
                    .offset(x: offset)
                    .frame(width: containerWidth, alignment: .leading)
                    .clipped()
                    .opacity(opacity)
                }
            }
        .clipped()
    }

    @ViewBuilder
    private func scrollingSegment(_ value: String) -> some View {
        Text(value)
            .barikFont(size: fontSize, weight: weight)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
