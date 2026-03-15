import AppKit
import Combine
import Foundation

// MARK: - Playback State

/// Represents the current playback state.
enum PlaybackState: String {
    case playing, paused, stopped
}

import AppKit

// MARK: - Now Playing Song Model

/// A model representing the currently playing song.
struct NowPlayingSong: Equatable, Identifiable {
    var id: String { title + artist }
    let appName: String
    let state: PlaybackState
    let title: String
    let artist: String
    let albumArtURL: URL?  // Still keep for compatibility with existing UI components
    let albumArtImage: NSImage?  // New property to hold the image directly in memory
    let position: Double?
    let duration: Double?  // Duration in seconds
    let positionTimestamp: Date?

    /// Initializes a song model with all parameters (new version with image).
    init(appName: String, state: PlaybackState, title: String, artist: String, albumArtURL: URL?, albumArtImage: NSImage?, position: Double?, duration: Double?, positionTimestamp: Date?) {
        self.appName = appName
        self.state = state
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.albumArtImage = albumArtImage
        self.position = position
        self.duration = duration
        self.positionTimestamp = positionTimestamp
    }

    /// Initializes a song model with all parameters (legacy version without image).
    init(appName: String, state: PlaybackState, title: String, artist: String, albumArtURL: URL?, position: Double?, duration: Double?, positionTimestamp: Date? = nil) {
        self.appName = appName
        self.state = state
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.albumArtImage = nil  // Legacy initialization
        self.position = position
        self.duration = duration
        self.positionTimestamp = positionTimestamp
    }
}

import AppKit

// MARK: - Now Playing Manager

/// An observable manager that updates the now playing song using MediaRemote Adapter.
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published private(set) var nowPlaying: NowPlayingSong?
    private var process: Process?
    private var cancellables = Set<AnyCancellable>()
    private let decoder = JSONDecoder()
    private var outputBuffer = ""

    // Cache for artwork images to avoid temporary files
    private let artworkCache = NSCache<NSString, NSImage>()

    private init() {
        startMediaRemoteStreaming()
    }

    /// Starts the MediaRemote Adapter stream to listen for now playing updates
    private func startMediaRemoteStreaming() {
        stopMediaRemoteStreaming()

        // Determine the correct path for media-control
        let mediaControlPath = findMediaControlPath()

        // Set up the process to run media-control stream command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")

        process.arguments = [
            "-c",
            "\(mediaControlPath) stream --no-diff"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorPipe = Pipe()
        process.standardError = errorPipe

        // Set up observers for the output
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        // Handle output with better buffering to handle partial JSON
        var buffer = ""
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let stringChunk = String(data: data, encoding: .utf8) {
                    buffer += stringChunk

                    // Split by newlines to process individual JSON objects
                    let lines = buffer.components(separatedBy: "\n")

                    // Keep the last incomplete line in the buffer
                    buffer = lines.last ?? ""

                    // Process all complete lines
                    let completeLines = Array(lines.dropLast())
                    for line in completeLines {
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedLine.isEmpty {
                            self?.parseMediaRemoteOutput(trimmedLine)
                        }
                    }
                }
            }
        }

        // Handle errors with buffering
        var errorBuffer = ""
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let errorString = String(data: data, encoding: .utf8) {
                    errorBuffer += errorString

                    let errorLines = errorBuffer.components(separatedBy: "\n")
                    errorBuffer = errorLines.last ?? ""

                    let completeErrorLines = Array(errorLines.dropLast())
                    for line in completeErrorLines {
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedLine.isEmpty {
                            print("MediaRemote Adapter Error: \(trimmedLine)")
                        }
                    }
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            print("Failed to start media-control stream: \(error). Attempting fallback...")

            // Fallback to distributed notification system if media-control is not available
            setupDistributedNotificationObserver()
        }
    }

    /// Finds the correct path for media-control executable
    private func findMediaControlPath() -> String {
        // Check common paths for media-control
        let possiblePaths = [
            "/opt/homebrew/bin/media-control",
            "/usr/local/bin/media-control",
            "/usr/bin/media-control"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                print("Using media-control from: \(path)")
                return path
            }
        }

        // If not found in specific paths, try to find using which
        if let pathFromWhich = executeShellCommand("which media-control")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pathFromWhich.isEmpty {
            print("Using media-control from: \(pathFromWhich)")
            return pathFromWhich
        }

        // If still not found, return a generic reference which will likely fail but be informative
        print("media-control not found in common paths. Using 'media-control' command directly.")
        return "media-control"
    }

    /// Helper function to execute shell commands
    private func executeShellCommand(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        task.standardOutput = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Helper function to truncate artworkData in JSON for debugging
    private func truncateArtworkData(_ jsonString: String) -> String {
        guard let jsonData = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return jsonString
        }

        var mutableJsonObject = jsonObject

        // Check if payload exists and contains artworkData
        if var payload = mutableJsonObject["payload"] as? [String: Any],
           let artworkData = payload["artworkData"] as? String {
            if artworkData.count > 60 { // If artworkData is longer than 60 characters
                let startIndex = artworkData.startIndex
                let prefixEndIndex = artworkData.index(startIndex, offsetBy: min(30, artworkData.count))
                let suffixStartIndex = artworkData.index(artworkData.endIndex, offsetBy: -min(30, artworkData.count))

                let prefix = String(artworkData[startIndex..<prefixEndIndex])
                let suffix = String(artworkData[suffixStartIndex...])
                payload["artworkData"] = "\(prefix)...\(suffix)"
                mutableJsonObject["payload"] = payload

                // Convert back to JSON string
                if let truncatedData = try? JSONSerialization.data(withJSONObject: mutableJsonObject),
                   let truncatedString = String(data: truncatedData, encoding: .utf8) {
                    return truncatedString
                }
            }
        }

        return jsonString
    }

    /// Parses the JSON output from the MediaRemote Adapter
    private func parseMediaRemoteOutput(_ rawJsonLine: String) {
        // Split by newlines in case multiple JSON objects came in one chunk
        let lines = rawJsonLine.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let jsonLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !jsonLine.isEmpty else { continue }

            // Print raw JSON for debugging, truncating artworkData if too long
            let debugJsonLine = truncateArtworkData(jsonLine)
            print("DEBUG RAW JSON: \(debugJsonLine)")

            // The MediaRemote Adapter outputs JSON lines in the format:
            // {"type": "data", "diff": true/false, "payload": {...}}
            guard let data = jsonLine.data(using: .utf8) else { continue }

            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let payload = jsonObject["payload"] as? [String: Any],
                   let bundleId = payload["bundleIdentifier"] as? String {

                    // Check if playing state exists
                    let isPlaying = payload["playing"] as? Bool ?? false

                    // Get the title
                    let title = payload["title"] as? String ?? ""

                    // Handle the case when playback stops or pauses
                    if !isPlaying && title.isEmpty {
                        // No title and not playing - clear the now playing info
                        DispatchQueue.main.async { [weak self] in
                            print("NowPlaying cleared - no title and not playing")
                            self?.nowPlaying = nil
                        }
                        continue
                    } else if !isPlaying && !title.isEmpty {
                        // Title exists but playback is paused - still show the song but with paused state
                        // This will be handled below
                    } else if title.isEmpty {
                        // No title but might be playing (rare case) - skip
                        continue
                    }

                    // Only update if we have a valid playing state
                    DispatchQueue.main.async { [weak self] in
                        let state: PlaybackState = isPlaying ? .playing : .paused

                        // Handle artwork data (base64 encoded) first
                        var albumArtURL: URL?
                        var albumArtImage: NSImage?

                        // Check if this payload contains only artworkData (separate artwork update)
                        if let artworkData = payload["artworkData"] as? String {
                            print("DEBUG: Processing artworkData of length: \(artworkData.count)")

                            // Convert base64 to data and store in memory
                            if let imageData = Data(base64Encoded: artworkData) {
                                print("DEBUG: Successfully decoded artwork image data of size: \(imageData.count)")

                                // Create NSImage directly from the data
                                if let image = NSImage(data: imageData) {
                                    albumArtImage = image
                                    print("DEBUG: Successfully created NSImage from artwork data")
                                    // Use in-memory image only, no temporary file creation
                                } else {
                                    print("DEBUG: Failed to create NSImage from image data")
                                }
                            } else {
                                print("DEBUG: Failed to decode artwork data from base64")
                            }
                        } else {
                            print("DEBUG: artworkData is not a string or is nil")
                        }

                        // Extract other metadata - if this is just artwork data, we may need to update the existing song
                        let title = payload["title"] as? String ?? ""
                        let artist = payload["artist"] as? String ?? ""

                        // If this is just artwork data without track info, update the existing song with artwork
                        if title.isEmpty && artist.isEmpty && albumArtImage != nil {
                            // This is a separate artwork update - update the existing song if it matches the bundleId
                            if let existingSong = self?.nowPlaying, existingSong.appName == bundleId {
                                let updatedSong = NowPlayingSong(
                                    appName: existingSong.appName,
                                    state: existingSong.state,
                                    title: existingSong.title,
                                    artist: existingSong.artist,
                                    albumArtURL: albumArtURL,
                                    albumArtImage: albumArtImage,
                                    position: existingSong.position,
                                    duration: existingSong.duration,
                                    positionTimestamp: existingSong.positionTimestamp
                                )

                                print("NowPlaying Artwork Update via MediaRemote Adapter: \(updatedSong.title) by \(updatedSong.artist) [\(updatedSong.state.rawValue)] from \(updatedSong.appName), albumArtURL: \(albumArtURL != nil ? "available" : "none"), albumArtImage: \(albumArtImage != nil ? "available" : "none")")
                                self?.nowPlaying = updatedSong
                                return // Exit early since we're just updating artwork
                            }
                        }

                        // If we have track info, create a new song object
                        if !title.isEmpty || !artist.isEmpty {
                            // Extract other metadata
                            let actualTitle = title.isEmpty ? (self?.nowPlaying?.title ?? "Unknown Title") : title
                            let actualArtist = artist.isEmpty ? (self?.nowPlaying?.artist ?? "Unknown Artist") : artist

                            // Handle duration and elapsed time
                            var duration: Double?
                            var position: Double?

                            // The adapter may provide duration in microseconds with durationMicros key
                            if let durationMicros = payload["durationMicros"] as? Int {
                                duration = Double(durationMicros) / 1_000_000.0
                            } else if let durationSec = payload["duration"] as? Double {
                                duration = durationSec
                            }

                            if let elapsedTimeMicros = payload["elapsedTimeMicros"] as? Int {
                                position = Double(elapsedTimeMicros) / 1_000_000.0
                            } else if let elapsedTime = payload["elapsedTime"] as? Double {
                                position = elapsedTime
                            }

                            let positionTimestamp: Date?
                            if let timestampEpochMicros = payload["timestampEpochMicros"] as? Int {
                                positionTimestamp = Date(timeIntervalSince1970: Double(timestampEpochMicros) / 1_000_000.0)
                            } else if payload["timestamp"] != nil {
                                positionTimestamp = Date()
                            } else {
                                positionTimestamp = nil
                            }

                            // Use existing artwork if new artwork isn't available
                            var finalAlbumArtURL = albumArtURL
                            var finalAlbumArtImage = albumArtImage

                            if finalAlbumArtImage == nil, let existingSong = self?.nowPlaying, existingSong.appName == bundleId {
                                // Preserve existing artwork if we're updating the same track
                                finalAlbumArtImage = existingSong.albumArtImage
                                finalAlbumArtURL = existingSong.albumArtURL
                            }

                            // Create the song object
                            let song = NowPlayingSong(
                                appName: bundleId,
                                state: state,
                                title: actualTitle,
                                artist: actualArtist,
                                albumArtURL: nil, // No more temporary files
                                albumArtImage: finalAlbumArtImage,
                                position: position,
                                duration: duration,
                                positionTimestamp: positionTimestamp
                            )

                            // Log for debugging
                            print("NowPlaying Update via MediaRemote Adapter: \(song.title) by \(song.artist) [\(song.state.rawValue)] from \(song.appName), albumArtImage: \(finalAlbumArtImage != nil ? "available" : "none")")

                            self?.nowPlaying = song
                        }

                        // Debug: Print all available keys in payload
                        print("DEBUG: Available keys in payload: \(payload.keys)")
                        if let artworkDataRaw = payload["artworkData"] {
                            let artworkDataStr = String(describing: artworkDataRaw)
                            let truncatedArtworkData = artworkDataStr.count > 60 ?
                                "\(artworkDataStr.prefix(30))...\(artworkDataStr.suffix(30))" :
                                artworkDataStr
                            print("DEBUG: artworkData type: \(type(of: artworkDataRaw)), value: \(truncatedArtworkData)")
                        } else {
                            print("DEBUG: artworkData key not found in payload")
                        }
                    }
                }
            } catch {
                // It's possible that the JSON is incomplete or malformed due to buffering
                // We can ignore these errors as they're often caused by partial reads
                // Only log if it's not a parsing issue related to partial data
                if !jsonLine.contains("{") || jsonLine.hasPrefix("{\"type\"") {
                    // Log only if it looks like it should be a proper JSON object
                    print("Error parsing MediaRemote Adapter JSON (line: \(jsonLine.prefix(100))...): \(error)")
                }
            }
        }
    }

    /// Sets up a fallback observer using distributed notifications
    private func setupDistributedNotificationObserver() {
        // Listen for music player changes using distributed notifications
        let center = DistributedNotificationCenter.default()

        center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleMusicNotification(notification)
        }

        center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSpotifyNotification(notification)
        }
    }

    /// Handles Music app notifications
    private func handleMusicNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let state: PlaybackState = (userInfo["Player State"] as? String == "Playing") ? .playing : .paused
        let title = userInfo["Name"] as? String ?? "Unknown Title"
        let artist = userInfo["Artist"] as? String ?? "Unknown Artist"
        let duration = userInfo["Duration"] as? Double
        let position = userInfo["Player Position"] as? Double

        let song = NowPlayingSong(
            appName: "Music",
            state: state,
            title: title,
            artist: artist,
            albumArtURL: nil, // Not available through notifications
            albumArtImage: nil, // Not available through notifications
            position: position,
            duration: duration,
            positionTimestamp: Date()
        )

        DispatchQueue.main.async { [weak self] in
            print("NowPlaying Update via Music notification: \(song.title) by \(song.artist) [\(song.state.rawValue)] from \(song.appName)")
            self?.nowPlaying = song
        }
    }

    /// Handles Spotify notifications
    private func handleSpotifyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let state: PlaybackState = (userInfo["Player State"] as? String == "Playing") ? .playing : .paused
        let title = userInfo["Track Title"] as? String ?? "Unknown Title"
        let artist = userInfo["Artist"] as? String ?? "Unknown Artist"
        let duration = userInfo["Duration"] as? Double
        let position = userInfo["Position"] as? Double

        let song = NowPlayingSong(
            appName: "Spotify",
            state: state,
            title: title,
            artist: artist,
            albumArtURL: nil, // Not available through notifications
            albumArtImage: nil, // Not available through notifications
            position: position,
            duration: duration,
            positionTimestamp: Date()
        )

        DispatchQueue.main.async { [weak self] in
            print("NowPlaying Update via Spotify notification: \(song.title) by \(song.artist) [\(song.state.rawValue)] from \(song.appName)")
            self?.nowPlaying = song
        }
    }

    /// Stops the MediaRemote Adapter stream
    private func stopMediaRemoteStreaming() {
        process?.terminate()
        process = nil
    }

    /// Executes a media control command using media-control
    private func executeMediaRemoteCommand(commandId: Int) {
        let task = Process()

        // Get the correct path for media-control
        let mediaControlPath = findMediaControlPath()

        // Map our internal command IDs to media-control commands
        let command: String
        switch commandId {
        case 2: // play/pause
            command = "\(mediaControlPath) toggle-play-pause"
        case 4: // next track
            command = "\(mediaControlPath) next-track"
        case 5: // previous track
            command = "\(mediaControlPath) previous-track"
        default:
            command = "\(mediaControlPath) toggle-play-pause" // default to play/pause
        }

        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("Failed to execute media-control command: \(error). Using fallback...")

            // Fallback to AppleScript if media-control fails
            executeAppleScriptFallback(commandId: commandId)
        }
    }

    /// Executes AppleScript as a fallback if MediaRemote Adapter is unavailable
    private func executeAppleScriptFallback(commandId: Int) {
        var script: String

        switch commandId {
        case 4: // Next track
            script = "tell application \"Spotify\" to next track\n" +
                     "tell application \"Music\" to next track"
        case 5: // Previous track
            script = "tell application \"Spotify\" to previous track\n" +
                     "tell application \"Music\" to previous track"
        case 2: // Toggle play/pause
            script = "tell application \"Spotify\" to playpause\n" +
                     "tell application \"Music\" to playpause"
        default:
            return
        }

        guard let appleScript = NSAppleScript(source: script) else {
            return
        }

        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)

        if let error = error {
            print("AppleScript Error: \(error)")
        }
    }

    /// Skips to the previous track.
    func previousTrack() {
        executeMediaRemoteCommand(commandId: 5) // Previous track command ID
    }

    /// Toggles between play and pause.
    func togglePlayPause() {
        executeMediaRemoteCommand(commandId: 2) // Toggle play/pause command ID
    }

    /// Skips to the next track.
    func nextTrack() {
        executeMediaRemoteCommand(commandId: 4) // Next track command ID
    }

    deinit {
        stopMediaRemoteStreaming()
    }
}
