import Foundation

/// The Free plan's monthly allowance of automatic trips (KTD2).
///
/// Counts automatic trips that exist in the calendar month of their start, in
/// the device's calendar and time zone, from local trips (synced or not), so it
/// works offline. A merge lowers the count, a deleted trip gives its slot back,
/// and overruns from offline use or a second device are tolerated.
struct AllowanceState: Equatable {
    let used: Int
    let limit: Int

    var remaining: Int { max(0, limit - used) }
    /// New automatic trips are refused; manual recording and resuming a trip are not.
    var isPaused: Bool { used >= limit }
}

enum Allowance {
    /// Used until the server's `app_config` value has been fetched once.
    nonisolated static let builtInLimit = 15
    /// Shorter drives are discarded by the detector and never count.
    nonisolated static let minimumCountedKm = 0.2

    nonisolated static func state(trips: [Trip], now: Date, calendar: Calendar = .current, limit: Int) -> AllowanceState {
        AllowanceState(used: autoTripCount(trips: trips, inMonthOf: now, calendar: calendar), limit: limit)
    }

    /// Automatic trips that count toward the allowance (and the usage figure) in `date`'s month.
    nonisolated static func autoTripCount(trips: [Trip], inMonthOf date: Date, calendar: Calendar = .current) -> Int {
        trips.filter {
            $0.source == .auto
                && $0.distanceKm >= minimumCountedKm
                && calendar.isDate($0.startedAt, equalTo: date, toGranularity: .month)
        }.count
    }

    /// Heads-up points after a saved automatic trip: the limit minus 3, minus 1, and
    /// the limit itself (the pause). Each fires once per month.
    nonisolated static func notice(for state: AllowanceState) -> Notice? {
        switch state.used {
        case state.limit: return .paused
        case state.limit - 1: return .oneLeft
        case state.limit - 3: return .threeLeft
        default: return nil
        }
    }

    enum Notice: String {
        case threeLeft, oneLeft, paused
    }

    /// UserDefaults key recording that a notice went out for a month.
    nonisolated static func noticeKey(_ notice: Notice, now: Date, calendar: Calendar = .current) -> String {
        "MileLog.allowance.\(MonthLocking.monthKey(now, calendar: calendar)).\(notice.rawValue)"
    }
}
