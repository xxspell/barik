import AppKit
import Combine
import Foundation

// MARK: - Playback State

/// Represents the current playback state.
enum PlaybackState: String {
    case playing, paused, stopped
}

// MARK: - Now Playing Song Model

/// A model representing the currently playing song.
struct NowPlayingSong: Equatable, Identifiable {
    var id: String { title + artist }
    let appName: String
    let state: PlaybackState
    let title: String
    let artist: String
    let albumArtURL: URL?
    let position: Double?
    let duration: Double?  // Duration in seconds

    /// Initializes a song model with all parameters.
    init(appName: String, state: PlaybackState, title: String, artist: String, albumArtURL: URL?, position: Double?, duration: Double?) {
        self.appName = appName
        self.state = state
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.position = position
        self.duration = duration
    }
}

// MARK: - Now Playing Manager

/// An observable manager that updates the now playing song using MediaRemote Adapter.
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published private(set) var nowPlaying: NowPlayingSong?
    private var process: Process?
    private var cancellables = Set<AnyCancellable>()
    private let decoder = JSONDecoder()
    private var outputBuffer = ""

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
            "\(mediaControlPath) stream"
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

    /// Parses the JSON output from the MediaRemote Adapter
    private func parseMediaRemoteOutput(_ rawJsonLine: String) {
        // Split by newlines in case multiple JSON objects came in one chunk
        let lines = rawJsonLine.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let jsonLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !jsonLine.isEmpty else { continue }

            // The MediaRemote Adapter outputs JSON lines in the format:
            // {"type": "data", "diff": true/false, "payload": {...}}
            guard let data = jsonLine.data(using: .utf8) else { continue }

            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let payload = jsonObject["payload"] as? [String: Any],
                   let bundleId = payload["bundleIdentifier"] as? String {

                    // Check if playing state exists
                    let isPlaying = payload["playing"] as? Bool ?? false

                    // Only update if we have at least a title (some payloads might be just metadata updates)
                    let title = payload["title"] as? String ?? ""
                    if title.isEmpty {
                        // If no title, check if this is a stop event
                        if !isPlaying && payload.keys.contains("title") {
                            // Explicitly stopped - clear the now playing info
                            DispatchQueue.main.async { [weak self] in
                                self?.nowPlaying = nil
                            }
                        }
                        continue
                    }

                    // Only update if we have a valid playing state
                    DispatchQueue.main.async { [weak self] in
                        let state: PlaybackState = isPlaying ? .playing : .paused

                        // Extract other metadata
                        let title = payload["title"] as? String ?? "Unknown Title"
                        let artist = payload["artist"] as? String ?? "Unknown Artist"

                        // Handle artwork data (base64 encoded)
                        var albumArtURL: URL?
                        if let artworkData = payload["artworkData"] as? String {
                            // Convert base64 to data and save temporarily
                            if let imageData = Data(base64Encoded: artworkData) {
                                let fileName = "\(bundleId)_\(title.replacingOccurrences(of: " ", with: "_")).jpg"
                                let tempDir = FileManager.default.temporaryDirectory
                                let fileURL = tempDir.appendingPathComponent(fileName)

                                do {
                                    try imageData.write(to: fileURL)
                                    albumArtURL = fileURL
                                } catch {
                                    print("Could not save artwork: \(error)")
                                }
                            }
                        }

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

                        // Create the song object
                        let song = NowPlayingSong(
                            appName: bundleId,
                            state: state,
                            title: title,
                            artist: artist,
                            albumArtURL: albumArtURL,
                            position: position,
                            duration: duration
                        )

                        self?.nowPlaying = song
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
            position: position,
            duration: duration
        )

        DispatchQueue.main.async { [weak self] in
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
            position: position,
            duration: duration
        )

        DispatchQueue.main.async { [weak self] in
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
