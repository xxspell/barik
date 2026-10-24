import Foundation
import OSLog
import AppKit

/// Printer state from Bambuddy API
enum BambuddyPrinterState: String, Codable, CaseIterable {
    case idle = "IDLE"
    case prepare = "PREPARE"
    case slicing = "SLICING"
    case running = "RUNNING"
    case pause = "PAUSE"
    case finish = "FINISH"
    case failed = "FAILED"
    
    var displayName: String {
        switch self {
        case .idle: return String(localized: "bambuddy.state.idle")
        case .prepare: return String(localized: "bambuddy.state.prepare")
        case .slicing: return String(localized: "bambuddy.state.slicing")
        case .running: return String(localized: "bambuddy.state.running")
        case .pause: return String(localized: "bambuddy.state.pause")
        case .finish: return String(localized: "bambuddy.state.finish")
        case .failed: return String(localized: "bambuddy.state.failed")
        }
    }
    
    var isActive: Bool {
        switch self {
        case .prepare, .slicing, .running, .pause:
            return true
        case .idle, .finish, .failed:
            return false
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .gray
        case .prepare, .slicing: return .blue
        case .running: return .green
        case .pause: return .orange
        case .finish: return .mint
        case .failed: return .red
        }
    }
}

/// Printer data from Bambuddy API
struct BambuddyPrinter: Codable, Identifiable {
    let id: Int
    let name: String
    let ipAddress: String
    let serialNumber: String
    let model: String
    let location: String?
    let isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, ipAddress = "ip_address", serialNumber = "serial_number", model, location, isActive = "is_active"
    }
}

/// Printer status from Bambuddy API
struct BambuddyPrinterStatus: Codable {
    let id: Int
    let name: String
    let connected: Bool
    let state: BambuddyPrinterState
    let progress: Int?
    let remainingTime: Int?
    let layerNum: Int?
    let totalLayers: Int?
    let temperatures: BambuddyTemperatures?
    let hmsErrors: [BambuddyHMSError]?
    let awaitingPlateClear: Bool?
    let currentPrint: String?
    let gcodeFile: String?
    let coverURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, connected, state, progress, remainingTime = "remaining_time", layerNum = "layer_num", totalLayers = "total_layers", temperatures, hmsErrors = "hms_errors", awaitingPlateClear = "awaiting_plate_clear", currentPrint = "current_print", gcodeFile = "gcode_file", coverURL = "cover_url"
    }
}

/// Temperature data from Bambuddy API
struct BambuddyTemperatures: Codable {
    let nozzle: Double?
    let nozzleTarget: Double?
    let bed: Double?
    let bedTarget: Double?
    let chamber: Double?
    
    enum CodingKeys: String, CodingKey {
        case nozzle, nozzleTarget = "nozzle_target", bed, bedTarget = "bed_target", chamber
    }
}

/// HMS Error from Bambuddy API
struct BambuddyHMSError: Codable, Identifiable {
    let code: String
    let attr: Int?
    let module: Int?
    let severity: Int?
    let actions: [String]?
    let jobId: String?
    let fullCode: String?
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case code, attr, module, severity, actions, jobId = "job_id", fullCode = "full_code", description
    }
    
    var id: String { fullCode ?? code }
}

/// Printer with combined info and status for UI
struct BambuddyPrinterWithStatus: Identifiable {
    let printer: BambuddyPrinter
    let status: BambuddyPrinterStatus?
    let lastUpdated: Date
    
    var id: Int { printer.id }
    
    var isOnline: Bool {
        status?.connected == true
    }
    
    var displayState: BambuddyPrinterState {
        status?.state ?? .idle
    }
    
    var progress: Int? {
        status?.progress
    }
    
    var remainingTime: Int? {
        status?.remainingTime
    }
    
    var temperatures: BambuddyTemperatures? {
        status?.temperatures
    }
    
    var hmsErrors: [BambuddyHMSError] {
        status?.hmsErrors ?? []
    }
    
    var hasErrors: Bool {
        !hmsErrors.isEmpty
    }
    
    var hasCriticalErrors: Bool {
        hmsErrors.contains { $0.severity == 1 }
    }
    
    var currentPrint: String? {
        status?.currentPrint
    }
}

/// Manager for Bambuddy API communication
@MainActor
final class BambuddyManager: ObservableObject {
    static let shared = BambuddyManager()
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "BambuddyManager"
    )
    
    @Published private(set) var printers: [BambuddyPrinterWithStatus] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?
    
    // Configuration (internal for access from widget/popup)
    private(set) var baseURL: String?
    private(set) var apiKey: String?
    private var refreshTimer: Timer?
    private var refreshInterval: TimeInterval = 30 // default 30 seconds
    
    private init() {}
    
    /// Configure the manager with Bambuddy server details
    func updateConfiguration(baseURL: String?, apiKey: String?, refreshInterval: TimeInterval?) {
        let oldBaseURL = self.baseURL
        let oldAPIKey = self.apiKey
        
        self.baseURL = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let interval = refreshInterval, interval >= 10 {
            self.refreshInterval = interval
        }
        
        // Restart if configuration changed
        if oldBaseURL != self.baseURL || oldAPIKey != self.apiKey {
            logger.info("Configuration changed, restarting updates")
            restartUpdates()
        }
    }
    
    /// Start periodic updates
    func startUpdating() {
        logger.debug("Starting Bambuddy updates with interval: \(self.refreshInterval)s")
        
        // Immediate fetch
        Task { await fetchPrinters() }
        
        // Schedule periodic updates
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchPrinters()
            }
        }
    }
    
    /// Stop periodic updates
    func stopUpdating() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    /// Manually trigger a refresh
    func refresh() async {
        await fetchPrinters()
    }
    
    /// Fetch printer list and status from Bambuddy
    private func fetchPrinters() async {
        guard let baseURL = baseURL,
              let apiKey = apiKey,
              !baseURL.isEmpty,
              !apiKey.isEmpty else {
            logger.debug("Bambuddy not configured, skipping fetch")
            return
        }
        
        isLoading = true
        lastError = nil
        
        do {
            // First, get the list of printers
            let printersURL = URL(string: "\(baseURL)/api/v1/printers/")!
            var printersRequest = URLRequest(url: printersURL)
            printersRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            
            let (printersData, printersResponse) = try await URLSession.shared.data(for: printersRequest)
            
            guard let httpResponse = printersResponse as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw BambuddyError.apiError("Failed to fetch printers")
            }
            
            let printers = try JSONDecoder().decode([BambuddyPrinter].self, from: printersData)
            
            // Fetch status for each printer in parallel
            var printerStatuses: [BambuddyPrinterWithStatus] = []
            
            await withTaskGroup(of: BambuddyPrinterWithStatus?.self) { group in
                for printer in printers {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return await self.fetchPrinterStatus(printer: printer)
                    }
                }
                
                for await result in group {
                    if let result {
                        printerStatuses.append(result)
                    }
                }
            }
            
            // Sort by printer ID for consistent ordering
            printerStatuses.sort { $0.id < $1.id }
            
            self.printers = printerStatuses
            self.lastRefresh = Date()
            self.lastError = nil
            
            logger.info("Successfully fetched \(printerStatuses.count) printers")
            
        } catch {
            self.lastError = error.localizedDescription
            logger.error("Failed to fetch Bambuddy printers: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    /// Fetch status for a single printer
    private func fetchPrinterStatus(printer: BambuddyPrinter) async -> BambuddyPrinterWithStatus? {
        guard let baseURL = baseURL,
              let apiKey = apiKey else { return nil }
        
        let statusURL = URL(string: "\(baseURL)/api/v1/printers/\(printer.id)/status")!
        var request = URLRequest(url: statusURL)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.debug("Printer \(printer.name) status unavailable: invalid response")
                return BambuddyPrinterWithStatus(
                    printer: printer,
                    status: nil,
                    lastUpdated: Date()
                )
            }
            
            guard httpResponse.statusCode == 200 else {
                // Printer might be offline - return with nil status
                logger.debug("Printer \(printer.name) status unavailable: \(httpResponse.statusCode)")
                return BambuddyPrinterWithStatus(
                    printer: printer,
                    status: nil,
                    lastUpdated: Date()
                )
            }
            
            let status = try JSONDecoder().decode(BambuddyPrinterStatus.self, from: data)
            return BambuddyPrinterWithStatus(
                printer: printer,
                status: status,
                lastUpdated: Date()
            )
            
        } catch {
            logger.error("Failed to fetch status for \(printer.name): \(error.localizedDescription)")
            return BambuddyPrinterWithStatus(
                printer: printer,
                status: nil,
                lastUpdated: Date()
            )
        }
    }
    
    /// Restart updates with new configuration
    private func restartUpdates() {
        stopUpdating()
        if baseURL != nil && apiKey != nil {
            startUpdating()
        } else {
            printers = []
        }
    }
    
    /// Get a printer by ID
    func printer(id: Int) -> BambuddyPrinterWithStatus? {
        printers.first { $0.id == id }
    }
    
    /// Get all online printers
    var onlinePrinters: [BambuddyPrinterWithStatus] {
        printers.filter { $0.isOnline }
    }
    
    /// Get all active (printing) printers
    var activePrinters: [BambuddyPrinterWithStatus] {
        printers.filter { $0.displayState.isActive }
    }
    
    /// Check if any printer has errors
    var anyPrinterHasErrors: Bool {
        printers.contains { $0.hasErrors }
    }
    
    /// Check if any printer has critical errors
    var anyPrinterHasCriticalErrors: Bool {
        printers.contains { $0.hasCriticalErrors }
    }

    /// Single color for the glyph icon: red = error, orange = preparing/slicing,
    /// green = actively printing, primary (white/black, theme-adaptive) = idle or offline.
    var overallStatusColor: Color {
        if anyPrinterHasCriticalErrors || anyPrinterHasErrors {
            return .red
        }
        if printers.contains(where: { $0.displayState == .prepare || $0.displayState == .slicing }) {
            return .orange
        }
        if printers.contains(where: { $0.displayState == .running || $0.displayState == .pause }) {
            return .green
        }
        return .primary
    }

    /// Get summary for menu bar display
    var summary: String {
        guard !printers.isEmpty else { return "—" }
        
        let onlineCount = onlinePrinters.count
        let activeCount = activePrinters.count
        
        if activeCount > 0 {
            // Show progress of first active printer
            if let firstActive = activePrinters.first,
               let progress = firstActive.progress {
                return "\(progress)%"
            }
            return "\(activeCount) \(String(localized: "bambuddy.printing"))"
        }
        
        if onlineCount > 0 {
            return "\(onlineCount) \(String(localized: "bambuddy.online"))"
        }
        
        return "\(printers.count) \(String(localized: "bambuddy.offline"))"
    }
    
    /// Check if Bambuddy is configured with a server URL
    var isConfigured: Bool {
        baseURL != nil && !baseURL!.isEmpty
    }
}

// MARK: - Errors

enum BambuddyError: LocalizedError {
    case notConfigured
    case apiError(String)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "bambuddy.error.not_configured")
        case .apiError(let message):
            return message
        case .decodingError(let error):
            return String(localized: "bambuddy.error.decoding \(error.localizedDescription)")
        case .networkError(let error):
            return String(localized: "bambuddy.error.network \(error.localizedDescription)")
        }
    }
}

import SwiftUI

extension Color {
    /// Bambu Lab's own brand green (#00AE42), matching the Bambuddy web app's theme color.
    static let bambuddyAccent = Color(red: 0 / 255, green: 174 / 255, blue: 66 / 255)
}

/// A stylized nozzle extruding a strand of filament — Bambuddy's icon glyph.
/// Drawn in a 100×100 unit box, vertically centered, so it scales cleanly like an SF Symbol.
/// Used at larger sizes (popup header, empty states) where the full gantry + carriage reads clearly.
struct BambuddyNozzleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 100
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()

        // Gantry bar
        path.addRoundedRect(
            in: CGRect(x: pt(8, 6).x, y: pt(8, 6).y, width: 84 * scale, height: 9 * scale),
            cornerSize: CGSize(width: 4 * scale, height: 4 * scale)
        )

        // Hot-end carriage
        path.addRoundedRect(
            in: CGRect(x: pt(36, 15).x, y: pt(36, 15).y, width: 28 * scale, height: 20 * scale),
            cornerSize: CGSize(width: 6 * scale, height: 6 * scale)
        )

        // Nozzle funnel + tip
        path.move(to: pt(38, 35))
        path.addLine(to: pt(62, 35))
        path.addLine(to: pt(53, 52))
        path.addLine(to: pt(47, 52))
        path.closeSubpath()
        path.move(to: pt(50, 52))
        path.addLine(to: pt(50, 62))

        // Extruded filament, looping then laying flat
        path.move(to: pt(50, 64))
        path.addCurve(to: pt(38, 78), control1: pt(50, 70), control2: pt(34, 68))
        path.addCurve(to: pt(58, 86), control1: pt(42, 88), control2: pt(50, 92))
        path.addLine(to: pt(92, 90))

        return path
    }
}

/// A reduced version of the nozzle glyph — just the funnel, tip and a short drip —
/// for contexts too small (menu bar, ~13pt) for the full gantry/carriage detail to read.
/// Coordinates are centered in the 100×100 box so it optically aligns with adjacent text.
struct BambuddyNozzleCompactShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 100
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()

        // Nozzle funnel + tip
        path.move(to: pt(26, 24))
        path.addLine(to: pt(74, 24))
        path.addLine(to: pt(58, 50))
        path.addLine(to: pt(50, 64))
        path.addLine(to: pt(42, 50))
        path.closeSubpath()

        // A single drip below the tip
        path.move(to: pt(50, 70))
        path.addLine(to: pt(50, 80))

        return path
    }
}

/// Convenience wrapper so the nozzle glyph can be dropped in wherever an SF Symbol icon would go.
struct BambuddyIcon: View {
    var size: CGFloat = 16
    var color: Color = .primary
    /// Use the reduced glyph for small (menu-bar scale) renderings so it doesn't blur into a smudge.
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                BambuddyNozzleCompactShape()
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.4, size * 0.13), lineCap: .round, lineJoin: .round))
            } else {
                BambuddyNozzleShape()
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.3, size * 0.1), lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Print Cover Thumbnail

/// In-memory cache so the same cover image isn't re-fetched on every refresh cycle.
private final class BambuddyImageCache {
    static let shared = BambuddyImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

/// Loads a printer's current-print cover thumbnail from Bambuddy, authenticating with the
/// same `X-API-Key` header used for the rest of the API (plain `AsyncImage` can't set headers).
///
/// `path` (`/printers/{id}/cover`) is stable per *printer*, not per *job* — it always returns
/// "the cover for whatever is printing right now". So `jobKey` (the current print's filename)
/// must be folded into both the task identity and the cache key, otherwise a new print on the
/// same printer keeps showing the previous job's cached thumbnail forever.
struct BambuddyCoverImage: View {
    let path: String
    let jobKey: String

    @State private var image: NSImage?

    private var identity: String { path + "#" + jobKey }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
            }
        }
        .task(id: identity) {
            image = nil
            await load()
        }
    }

    private func load() async {
        guard let baseURL = BambuddyManager.shared.baseURL,
              let apiKey = BambuddyManager.shared.apiKey,
              !baseURL.isEmpty, !apiKey.isEmpty else { return }

        let cacheKey = baseURL + identity
        if let cached = BambuddyImageCache.shared.image(for: cacheKey) {
            image = cached
            return
        }

        guard let url = URL(string: baseURL + path) else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let loaded = NSImage(data: data) else { return }

        BambuddyImageCache.shared.store(loaded, for: cacheKey)
        image = loaded
    }
}