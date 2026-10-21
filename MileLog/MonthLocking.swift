import Foundation

/// A month whose report was generated after it ended, for one vehicle (KTD10).
struct ClosedMonth: Codable, Hashable {
    var vehicleID: UUID
    /// "yyyy-MM" in the device calendar when it was closed.
    var month: String
    /// "own_car" or "company_logbook".
    var reportKind: String
    var closedAt: Date
}

/// Month-aware locking (KTD10): a trip locks when its month is closed or the
/// configured number of days into the following month has passed, whichever
/// comes first. Locks only tighten.
enum MonthLocking {
    nonisolated static let maxDaysIntoNextMonth = 28

    nonisolated static func clampDays(_ days: Int) -> Int {
        min(max(days, 1), maxDaysIntoNextMonth)
    }

    nonisolated static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// Whether `date`'s month has fully ended by `now`.
    nonisolated static func monthHasEnded(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard let end = calendar.dateInterval(of: .month, for: date)?.end else { return false }
        return now >= end
    }

    nonisolated static func shouldLock(_ trip: Trip, closed: Set<ClosedMonthKey>, daysIntoNextMonth: Int,
                                       now: Date, calendar: Calendar = .current) -> Bool {
        if isInClosedMonth(trip, closed: closed, calendar: calendar) { return true }
        guard let nextMonth = calendar.dateInterval(of: .month, for: trip.startedAt)?.end,
              let lockAt = calendar.date(byAdding: .day, value: clampDays(daysIntoNextMonth), to: nextMonth)
        else { return false }
        return now >= lockAt
    }

    nonisolated static func isInClosedMonth(_ trip: Trip, closed: Set<ClosedMonthKey>, calendar: Calendar = .current) -> Bool {
        closed.contains(ClosedMonthKey(vehicleID: trip.vehicleID, month: monthKey(trip.startedAt, calendar: calendar)))
    }
}

struct ClosedMonthKey: Hashable {
    var vehicleID: UUID
    var month: String
}

extension ClosedMonth {
    var key: ClosedMonthKey { ClosedMonthKey(vehicleID: vehicleID, month: month) }
}
