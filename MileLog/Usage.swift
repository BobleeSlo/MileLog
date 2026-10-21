import Foundation
import Combine

/// Anonymous monthly usage figures, sent only with the user's consent (KTD13).
///
/// Nothing is sent for a month until it has ended: then one submission per
/// metric, as a count bucket, on a random day early in the next month so no
/// row reflects a single trip. The server stores month, metric and bucket only.
@MainActor
final class Usage: ObservableObject {

    enum Metric: String, CaseIterable {
        case autoTrips = "auto_trips"
        case reportGenerations = "report_generations"
        case receiptSaves = "receipt_saves"
        case monthEndCheckOpens = "month_end_check_opens"
    }

    /// nil until the user has answered the one-time question.
    @Published var consent: Bool? {
        didSet { defaults.set(consent.map { $0 ? "yes" : "no" }, forKey: Self.consentKey) }
    }

    private let defaults: UserDefaults
    private static let consentKey = "MileLog.usage.consent"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        consent = defaults.string(forKey: Self.consentKey).map { $0 == "yes" }
    }

    /// Counts an event for this month — only while consent is on.
    func record(_ metric: Metric, now: Date = Date()) {
        guard consent == true, metric != .autoTrips else { return }
        let key = Self.countKey(metric, month: MonthLocking.monthKey(now))
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    /// Sends last month's figures once, on or after its random send day.
    func submitIfDue(trips: [Trip], via supabase: SupabaseService, now: Date = Date(), calendar: Calendar = .current) async {
        guard consent == true,
              let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return }
        let month = MonthLocking.monthKey(lastMonth, calendar: calendar)
        let sentKey = "MileLog.usage.sent.\(month)"
        guard !defaults.bool(forKey: sentKey) else { return }

        // A random day 1–20 of the following month, fixed once chosen.
        let dayKey = "MileLog.usage.sendDay.\(month)"
        if defaults.integer(forKey: dayKey) == 0 { defaults.set(Int.random(in: 1...20), forKey: dayKey) }
        guard calendar.component(.day, from: now) >= defaults.integer(forKey: dayKey) else { return }

        let counts = Dictionary(uniqueKeysWithValues: Metric.allCases.map { ($0, defaults.integer(forKey: Self.countKey($0, month: month))) })
        let submissions = Self.submissions(month: lastMonth, now: now, trips: trips, counts: counts, calendar: calendar)
        do {
            for s in submissions {
                try await supabase.recordUsage(month: month + "-01", metric: s.metric.rawValue, bucket: s.bucket)
            }
            defaults.set(true, forKey: sentKey)
        } catch {
            // Offline: tried again at the next launch while the month is still accepted.
        }
    }

    // MARK: - Pure rules

    nonisolated static func countKey(_ metric: Metric, month: String) -> String {
        "MileLog.usage.count.\(month).\(metric.rawValue)"
    }

    nonisolated static func bucket(_ n: Int) -> String {
        switch n {
        case ..<1: "0"
        case 1...5: "1-5"
        case 6...10: "6-10"
        case 11...15: "11-15"
        case 16...25: "16-25"
        case 26...50: "26-50"
        case 51...100: "51-100"
        default: "101+"
        }
    }

    /// One submission per metric for `month`, or none while that month is still running.
    nonisolated static func submissions(month: Date, now: Date, trips: [Trip], counts: [Metric: Int],
                                        calendar: Calendar = .current) -> [(metric: Metric, bucket: String)] {
        guard MonthLocking.monthHasEnded(month, now: now, calendar: calendar) else { return [] }
        let autoTrips = trips.filter {
            $0.source == .auto && $0.distanceKm >= Allowance.minimumCountedKm
                && calendar.isDate($0.startedAt, equalTo: month, toGranularity: .month)
        }.count
        return Metric.allCases.map { metric in
            (metric, bucket(metric == .autoTrips ? autoTrips : counts[metric] ?? 0))
        }
    }
}
