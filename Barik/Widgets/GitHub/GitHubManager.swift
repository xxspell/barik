import Foundation
import SwiftUI
import Security
import AppKit
import OSLog

// MARK: - Auth State

enum GitHubAuthState: Equatable {
    case signedOut
    case deviceFlowPending(userCode: String, verificationURI: String)
    case signedIn(login: String)
}

// MARK: - Data Models

struct GitHubContributionDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

struct GitHubData {
    var login: String = ""
    var streakDays: Int = 0
    var commitsToday: Int = 0
    var contributionDays: [GitHubContributionDay] = []
    var openIssues: Int = 0
    var openPRs: Int = 0
    var unreadNotifications: Int = 0
    var totalStars: Int = 0
    var lastUpdated: Date = Date()
    var isAvailable: Bool = false
}

// MARK: - Streak Calculator

enum GitHubStreakCalculator {
    /// Computes the current commit streak from a list of per-day contribution counts.
    /// The most recent day ("today") is never treated as a break by itself — it may
    /// simply not be over yet. If today already has commits, it counts toward the streak.
    static func calculate(days: [GitHubContributionDay]) -> (streakDays: Int, commitsToday: Int) {
        let sorted = days.sorted { $0.date < $1.date }
        guard let today = sorted.last else { return (0, 0) }

        let commitsToday = today.count
        var streak = 0
        var index = sorted.count - 1

        if sorted[index].count == 0 {
            index -= 1
        }

        while index >= 0, sorted[index].count > 0 {
            streak += 1
            index -= 1
        }

        return (streak, commitsToday)
    }
}
