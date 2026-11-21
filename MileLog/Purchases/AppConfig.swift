import Foundation
import Combine

/// Server-tunable settings from the public `app_config` table (KTD9). Fetched at
/// launch and on foreground at most every few hours, cached, and falling back
/// to the built-in values when nothing has been fetched yet.
@MainActor
final class AppConfig: ObservableObject {
    @Published private(set) var freeAutoTripsPerMonth: Int

    private let defaults: UserDefaults
    private static let limitKey = "MileLog.config.freeAutoTripsPerMonth"
    private static let fetchedKey = "MileLog.config.fetchedAt"
    private static let refetchInterval: TimeInterval = 3 * 3600

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let cached = defaults.integer(forKey: Self.limitKey)
        freeAutoTripsPerMonth = cached > 0 ? cached : Allowance.builtInLimit
    }

    func refreshIfStale(via supabase: SupabaseService, now: Date = Date()) async {
        if let last = defaults.object(forKey: Self.fetchedKey) as? Date, now.timeIntervalSince(last) < Self.refetchInterval {
            return
        }
        guard let limit = try? await supabase.pullFreeAutoTripLimit(), limit > 0 else { return }
        apply(limit: limit, fetchedAt: now)
    }

    func apply(limit: Int, fetchedAt: Date) {
        if freeAutoTripsPerMonth != limit { freeAutoTripsPerMonth = limit }
        defaults.set(limit, forKey: Self.limitKey)
        defaults.set(fetchedAt, forKey: Self.fetchedKey)
    }
}
