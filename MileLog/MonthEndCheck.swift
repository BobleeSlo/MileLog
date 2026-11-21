import Foundation

/// Everything in a month that needs fixing before its report (R15, R16, F2).
struct MonthEndCheck: Equatable {
    /// Trips nobody has classified or confirmed yet.
    var unreviewed: [Trip] = []
    /// Business trips with neither a customer nor a purpose.
    var missingDetails: [Trip] = []
    /// Adjacent fragments that look like one drive split in two.
    var likelySplits: [Store.MergeCandidate] = []
    /// Trips still missing a start or end address (an hour after they ended).
    var missingAddresses: [Trip] = []
    /// Locked trips that would otherwise be listed above. Shown for information;
    /// they can't be changed and don't count as open items (KTD10).
    var locked: [Trip] = []

    var openCount: Int { unreviewed.count + missingDetails.count + likelySplits.count + missingAddresses.count }
    var isClean: Bool { openCount == 0 && locked.isEmpty }

    /// Addresses resolve in the background after a trip ends; younger trips are skipped.
    static let addressGrace: TimeInterval = 3600

    static func build(trips: [Trip], candidates: [Store.MergeCandidate], month: Date,
                      calendar: Calendar = .current, now: Date = Date()) -> MonthEndCheck {
        let inMonth = { (t: Trip) in calendar.isDate(t.startedAt, equalTo: month, toGranularity: .month) }
        var check = MonthEndCheck()
        for trip in trips.filter(inMonth).sorted(by: { $0.startedAt < $1.startedAt }) {
            let unreviewed = trip.reviewedAt == nil
            let missingDetails = trip.type == .business
                && trip.customerName.trimmingCharacters(in: .whitespaces).isEmpty
                && trip.purpose.trimmingCharacters(in: .whitespaces).isEmpty
            let missingAddress = (trip.startAddress.isEmpty || trip.endAddress.isEmpty)
                && now.timeIntervalSince(trip.endedAt) >= addressGrace
            guard unreviewed || missingDetails || missingAddress else { continue }
            if trip.isLocked {
                check.locked.append(trip)
                continue
            }
            if unreviewed { check.unreviewed.append(trip) }
            if missingDetails { check.missingDetails.append(trip) }
            if missingAddress { check.missingAddresses.append(trip) }
        }
        // Merge candidates already exclude locked trips.
        check.likelySplits = candidates.filter { inMonth($0.first) }
        return check
    }
}
