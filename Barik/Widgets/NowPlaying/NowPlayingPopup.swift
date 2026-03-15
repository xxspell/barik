import EventKit
import SwiftUI

struct NowPlayingPopup: View {
    @ObservedObject var configProvider: ConfigProvider
    @State private var selectedVariant: MenuBarPopupVariant = .horizontal

    var body: some View {
        MenuBarPopupVariantView(
            selectedVariant: selectedVariant,
            onVariantSelected: { variant in
                selectedVariant = variant
                ConfigManager.shared.updateConfigValue(
                    key: "widgets.default.nowplaying.popup.view-variant",
                    newValue: variant.rawValue
                )
            },
            vertical: { NowPlayingVerticalPopup() },
            horizontal: { NowPlayingHorizontalPopup() }
        )
        .onAppear(perform: loadVariant)
        .onReceive(configProvider.$config, perform: updateVariant)
    }
    
    /// Loads the initial view variant from configuration.
    private func loadVariant() {
        if let variantString = configProvider.config["popup"]?
            .dictionaryValue?["view-variant"]?.stringValue,
           let variant = MenuBarPopupVariant(rawValue: variantString) {
            selectedVariant = variant
        } else {
            selectedVariant = .horizontal
        }
    }
    
    /// Updates the view variant when configuration changes.
    private func updateVariant(newConfig: ConfigData) {
        if let variantString = newConfig["popup"]?.dictionaryValue?["view-variant"]?.stringValue,
           let variant = MenuBarPopupVariant(rawValue: variantString) {
            selectedVariant = variant
        }
    }
}

/// A vertical layout for the now playing popup.
private struct NowPlayingVerticalPopup: View {
    @ObservedObject private var playingManager = NowPlayingManager.shared

    var body: some View {
        if let song = playingManager.nowPlaying {
            VStack(spacing: 15) {
                PopupAlbumArtView(song: song, size: CGSize(width: 200, height: 200))

                VStack(alignment: .center) {
                    Text(song.title)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15))
                        .fontWeight(.medium)
                    Text(song.artist)
                        .opacity(0.6)
                        .font(.system(size: 15))
                        .fontWeight(.light)
                }

                PlaybackProgressView(song: song)

                HStack(spacing: 40) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .onTapGesture { playingManager.previousTrack() }
                    Image(systemName: song.state == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 30))
                        .onTapGesture { playingManager.togglePlayPause() }
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .onTapGesture { playingManager.nextTrack() }
                }
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 30)
            .frame(width: 300)
            .animation(.easeInOut, value: song.id)
        }
    }
}

/// A horizontal layout for the now playing popup.
struct NowPlayingHorizontalPopup: View {
    @ObservedObject private var playingManager = NowPlayingManager.shared

    var body: some View {
        if let song = playingManager.nowPlaying {
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    PopupAlbumArtView(song: song, size: CGSize(width: 60, height: 60))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(song.title)
                            .font(.headline)
                            .fontWeight(.medium)
                        Text(song.artist)
                            .opacity(0.6)
                            .font(.headline)
                            .fontWeight(.light)
                    }
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                PlaybackProgressView(song: song)

                HStack(spacing: 40) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .onTapGesture { playingManager.previousTrack() }
                    Image(systemName: song.state == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 30))
                        .onTapGesture { playingManager.togglePlayPause() }
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .onTapGesture { playingManager.nextTrack() }
                }
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 20)
            .frame(width: 300)
            .frame(minHeight: 140)
            .animation(.easeInOut, value: song.id)
        }
    }
}

private struct PopupAlbumArtView: View {
    let song: NowPlayingSong
    let size: CGSize

    var body: some View {
        ZStack {
            if let albumArtImage = song.albumArtImage {
                Image(nsImage: albumArtImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let albumArtURL = song.albumArtURL {
                RotateAnimatedCachedImage(
                    url: albumArtURL,
                    targetSize: size
                )
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: min(size.width, size.height) * 0.28))
                            .foregroundStyle(.white.opacity(0.55))
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(song.state == .paused ? 0.9 : 1)
        .overlay {
            if song.state == .paused {
                Color.black.opacity(0.3)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .animation(.smooth(duration: 0.5, extraBounce: 0.4), value: song.state == .paused)
    }
}

private struct PlaybackProgressView: View {
    let song: NowPlayingSong

    var body: some View {
        if let duration = song.duration, duration > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let position = estimatedPosition(for: song, at: context.date)

                HStack {
                    Text(timeString(from: position))
                        .font(.caption)
                    ProgressView(value: position, total: duration)
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(.white)
                    Text("-" + timeString(from: max(duration - position, 0)))
                        .font(.caption)
                }
                .foregroundColor(.gray)
                .monospacedDigit()
            }
        }
    }

    private func estimatedPosition(for song: NowPlayingSong, at date: Date) -> Double {
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
}

/// Converts a time interval in seconds to a formatted string (minutes:seconds).
private func timeString(from seconds: Double) -> String {
    let intSeconds = Int(seconds)
    let minutes = intSeconds / 60
    let remainingSeconds = intSeconds % 60
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

// MARK: - Previews

struct NowPlayingPopup_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NowPlayingVerticalPopup()
                .background(Color.black)
                .frame(height: 600)
                .previewDisplayName("Vertical")
            
            NowPlayingHorizontalPopup()
                .background(Color.black)
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Horizontal")
        }
    }
}
