//
//  MileLogTests.swift
//  MileLogTests
//
//  Created by Robert LIPIC on 13. 6. 2026.
//

import XCTest
@testable import MileLog

final class MileLogTests: XCTestCase {

    // MARK: - GPS jitter (readings from the 19 Oct 2026 detection log)

    func testParkedJitterIsNotTravel() {
        // Parked after Bluetooth dropped: 0 km/h at 11–23 m accuracy. Jumps
        // of 15–30 m used to count as movement and kept the trip open.
        let radius = TripDetector.jitterRadius(accuracy: 15, movingBySpeed: false, engineOff: false)
        XCTAssertEqual(radius, 22.5, accuracy: 0.001)
        XCTAssertFalse(20 > radius)
    }

    func testEngineOffNeedsAClearJump() {
        XCTAssertEqual(TripDetector.jitterRadius(accuracy: 5, movingBySpeed: false, engineOff: true), 30)
        XCTAssertEqual(TripDetector.jitterRadius(accuracy: 47, movingBySpeed: false, engineOff: true), 94)
    }

    func testDrivingKeepsTheTenMetreStep() {
        // A real speed reading counts regardless of accuracy.
        XCTAssertEqual(TripDetector.jitterRadius(accuracy: 47, movingBySpeed: true, engineOff: true), 10)
        // Good accuracy without a speed reading: stop-and-go traffic still counts at 10 m.
        XCTAssertEqual(TripDetector.jitterRadius(accuracy: 2, movingBySpeed: false, engineOff: false), 10)
    }

    func testInvalidAccuracyFallsBackToMinimumStep() {
        XCTAssertEqual(TripDetector.jitterRadius(accuracy: -1, movingBySpeed: false, engineOff: false), 10)
    }

    // MARK: - Bluetooth device matching

    func testSameCarAcrossBluetoothProfiles() {
        // One head unit: music (A2DP) and calls (HFP) report different UIDs.
        XCTAssertTrue(AudioRoute.sameDevice("A1:B2:C3:D4:E5:F6-tacl", "A1:B2:C3:D4:E5:F6-tsco"))
        XCTAssertTrue(AudioRoute.sameDevice("A1:B2:C3:D4:E5:F6-tacl", "A1:B2:C3:D4:E5:F6-tacl"))
    }

    func testDifferentCarsDoNotMatch() {
        XCTAssertFalse(AudioRoute.sameDevice("A1:B2:C3:D4:E5:F6-tacl", "00:11:22:33:44:55-tacl"))
        XCTAssertFalse(AudioRoute.sameDevice("", ""))
        XCTAssertFalse(AudioRoute.sameDevice("A1:B2:C3:D4:E5:F6-tacl", ""))
    }

    // MARK: - Input and formatting

    func testDecimalInputAllowsOneSeparator() {
        XCTAssertEqual(DecimalInput.sanitize("0,180,2", fractionDigits: 3), "0,180")
        XCTAssertEqual(DecimalInput.sanitize("12.345", fractionDigits: 2), "12.34")
        XCTAssertEqual(DecimalInput.sanitize("1a2€", fractionDigits: 2), "12")
        XCTAssertEqual(DecimalInput.parse("0,43"), 0.43)
    }

    func testPlateIsTidied() {
        XCTAssertEqual(Vehicle.tidyPlate("mb ab-123 !!"), "MB AB-123")
        XCTAssertEqual(Vehicle.tidyPlate("  lj   zz-999 "), "LJ ZZ-999")
        XCTAssertEqual(Vehicle.tidyPlate("ce čž-12"), "CE ČŽ-12")
    }

    func testDistancesRoundToTenths() {
        XCTAssertEqual(3.430579.roundedToTenthKm, 3.4, accuracy: 1e-9)
        XCTAssertEqual(3.45.roundedToTenthKm + 12.5, 16.0, accuracy: 1e-9)
    }

    func testFormatFollowsLanguage() {
        let saved = Format.locale
        defer { Format.locale = saved }
        Format.locale = Locale(identifier: "sl_SI")
        XCTAssertEqual(Format.km(12.5), "12,5 km")
        XCTAssertEqual(Format.km(16), "16,0 km")
        Format.locale = Locale(identifier: "en_US")
        XCTAssertEqual(Format.km(3.43), "3.4 km")
    }

    // MARK: - Language

    func testNativeLanguageNames() {
        XCTAssertEqual(AppLanguage.nativeName(for: "sl"), "Slovenščina")
        XCTAssertEqual(AppLanguage.nativeName(for: "en"), "English")
    }

    @MainActor
    func testAppShipsSlovenian() {
        XCTAssertTrue(AppLanguage().available.contains("sl"))
    }

    @MainActor
    func testLanguageListHasOnlyShippedTranslationsOnce() {
        // Info.plist once declared "de", which put an untranslated
        // "Deutsch" and a second "English" in the picker.
        let available = AppLanguage().available
        XCTAssertEqual(available.count, Set(available).count)
        XCTAssertEqual(Set(available), ["en", "sl"])
    }

    // MARK: - Trip source

    private func storedTripJSON(notes: String, source: String? = nil) throws -> Data {
        var trip = Trip(vehicleID: UUID(), type: .business, purpose: "", customerName: "",
                        startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60),
                        startAddress: "", endAddress: "", distanceKm: 1, notes: notes, isLocked: false)
        trip.source = .manual
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(trip)) as! [String: Any]
        object["source"] = source
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testStoredTripWithoutSourceFollowsNotes() throws {
        let auto = try JSONDecoder().decode(Trip.self, from: storedTripJSON(notes: "Auto-detected"))
        XCTAssertEqual(auto.source, .auto)
        let manual = try JSONDecoder().decode(Trip.self, from: storedTripJSON(notes: ""))
        XCTAssertEqual(manual.source, .manual)
    }

    func testStoredSourceWinsOverNotes() throws {
        let trip = try JSONDecoder().decode(Trip.self, from: storedTripJSON(notes: "", source: "auto"))
        XCTAssertEqual(trip.source, .auto)
        let future = try JSONDecoder().decode(Trip.self, from: storedTripJSON(notes: "", source: "imported"))
        XCTAssertEqual(future.source, .manual)
    }

    /// Same samples as the SQL rule in 20261021203109_add_trip_source.sql:
    /// position('Auto-detected' in notes) > 0.
    func testNotesRuleMatchesTheDatabase() {
        XCTAssertEqual(TripSource.derived(fromNotes: "Auto-detected"), .auto)
        XCTAssertEqual(TripSource.derived(fromNotes: "Auto-detected\nAuto-detected"), .auto)
        XCTAssertEqual(TripSource.derived(fromNotes: "Client visit\nAuto-detected"), .auto)
        XCTAssertEqual(TripSource.derived(fromNotes: "auto-detected"), .manual)
        XCTAssertEqual(TripSource.derived(fromNotes: "Client visit"), .manual)
        XCTAssertEqual(TripSource.derived(fromNotes: ""), .manual)
    }

    func testSyncCarriesSource() {
        var trip = Trip(vehicleID: UUID(), type: .business, purpose: "", customerName: "",
                        startedAt: Date(), endedAt: Date(), startAddress: "", endAddress: "",
                        distanceKm: 1, notes: "", isLocked: false, source: .auto)
        let dto = TripDTO(from: trip, userId: UUID())
        XCTAssertEqual(dto.source, "auto")
        XCTAssertEqual(dto.toTrip().source, .auto)
        // A row from an older build has no source: the notes decide.
        trip.notes = "Auto-detected"
        var old = TripDTO(from: trip, userId: UUID())
        old.source = nil
        XCTAssertEqual(old.toTrip().source, .auto)
    }

    func testResumedTripKeepsItsSource() throws {
        let state = ActiveTripState(id: UUID(), vehicleID: UUID(), startedAt: Date(), startLat: 0, startLng: 0,
                                    lastLat: 0, lastLng: 0, distanceKm: 0, lastMovementAt: Date(),
                                    resumedSource: .manual)
        let decoded = try JSONDecoder().decode(ActiveTripState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.resumedSource, .manual)
    }

    // MARK: - Plan status

    private let me = UUID()
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func row(_ status: String, expires: TimeInterval? = 86_400, id: String? = "1000", source: String = "apple") -> ServerEntitlement {
        ServerEntitlement(source: source, originalTransactionID: id, status: status, expiresAt: expires.map { now.addingTimeInterval($0) })
    }

    func testServerRowGivesPaidWithoutLocalTransactions() {
        // AE5: new iPhone or reinstall.
        XCTAssertTrue(PlanResolver.resolve(server: [row("active")], local: [], cache: nil, userID: me, now: now).isPaid)
    }

    func testComplimentaryRowGivesPaid() {
        let grant = row("active", expires: 365 * 86_400, id: nil, source: "complimentary")
        XCTAssertTrue(PlanResolver.resolve(server: [grant], local: [], cache: nil, userID: me, now: now).isPaid)
        let ended = row("active", expires: -60, id: nil, source: "complimentary")
        XCTAssertEqual(PlanResolver.resolve(server: [ended], local: [], cache: nil, userID: me, now: now), .free)
    }

    func testLocalTransactionWithMyTokenGivesPaid() {
        let local = LocalEntitlement(originalTransactionID: "1000", appAccountToken: me, expiresAt: now.addingTimeInterval(3600), isRevoked: false)
        XCTAssertTrue(PlanResolver.resolve(server: [], local: [local], cache: nil, userID: me, now: now).isPaid)
    }

    func testAnotherAccountsTransactionGivesFreeWithReason() {
        // AE8
        let local = LocalEntitlement(originalTransactionID: "1000", appAccountToken: UUID(), expiresAt: now.addingTimeInterval(3600), isRevoked: false)
        XCTAssertEqual(PlanResolver.resolve(server: [], local: [local], cache: nil, userID: me, now: now), .freeOtherAccount)
        // An active row on the server still wins.
        XCTAssertTrue(PlanResolver.resolve(server: [row("active")], local: [local], cache: nil, userID: me, now: now).isPaid)
    }

    func testCacheIsHonouredOfflineUntilItsLimit() {
        let cache = CachedPlan(userID: me, isPaid: true, expiresAt: now.addingTimeInterval(30 * 86_400), checkedAt: now.addingTimeInterval(-86_400))
        XCTAssertTrue(PlanResolver.resolve(server: nil, local: [], cache: cache, userID: me, now: now).isPaid)
        // Seven days after the last check, even before the expiry.
        let old = CachedPlan(userID: me, isPaid: true, expiresAt: now.addingTimeInterval(30 * 86_400), checkedAt: now.addingTimeInterval(-8 * 86_400))
        XCTAssertEqual(PlanResolver.resolve(server: nil, local: [], cache: old, userID: me, now: now), .free)
        let expired = CachedPlan(userID: me, isPaid: true, expiresAt: now.addingTimeInterval(-60), checkedAt: now)
        XCTAssertEqual(PlanResolver.resolve(server: nil, local: [], cache: expired, userID: me, now: now), .free)
        // Another account's cache never applies.
        XCTAssertEqual(PlanResolver.resolve(server: nil, local: [], cache: cache, userID: UUID(), now: now), .free)
    }

    func testRevokedRowGivesFreeEvenWithCacheAndDevice() {
        let cache = CachedPlan(userID: me, isPaid: true, expiresAt: nil, checkedAt: now)
        let local = LocalEntitlement(originalTransactionID: "1000", appAccountToken: me, expiresAt: now.addingTimeInterval(3600), isRevoked: false)
        XCTAssertEqual(PlanResolver.resolve(server: [row("revoked")], local: [local], cache: cache, userID: me, now: now), .free)
    }

    func testBillingRetryIsFreeAndGraceIsPaid() {
        XCTAssertEqual(PlanResolver.resolve(server: [row("billing_retry")], local: [], cache: nil, userID: me, now: now), .free)
        XCTAssertTrue(PlanResolver.resolve(server: [row("grace")], local: [], cache: nil, userID: me, now: now).isPaid)
    }

    @MainActor
    func testSwitchingAccountClearsThePreviousAccountsCache() async {
        let defaults = UserDefaults(suiteName: "MileLogTests.plan")!
        defaults.removePersistentDomain(forName: "MileLogTests.plan")
        let cache = PlanCache(defaults: defaults)
        cache.save(CachedPlan(userID: me, isPaid: true, expiresAt: nil, checkedAt: now))
        let store = SubscriptionStore(defaults: defaults)
        await store.accountChanged(to: me)
        await store.accountChanged(to: nil)
        XCTAssertNil(cache.load(for: me))
        let plan = store.plan
        XCTAssertEqual(plan, .free)
    }

    // MARK: - Allowance

    private var ljubljana: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Ljubljana")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Ljubljana")!
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f.date(from: s)!
    }

    private func trips(_ count: Int, on day: String, source: TripSource = .auto, km: Double = 5) -> [Trip] {
        (0..<count).map { _ in
            Trip(vehicleID: UUID(), type: .business, purpose: "", customerName: "", startedAt: date(day), endedAt: date(day),
                 startAddress: "", endAddress: "", distanceKm: km, notes: "", isLocked: false, source: source)
        }
    }

    func testFifteenthTripIsSavedAndTheNextStartIsRefused() {
        // AE1: 14 used → the 15th may start; once it is saved the month is paused.
        let before = Allowance.state(trips: trips(14, on: "2026-10-20T08:00:00"), now: date("2026-10-21T08:00:00"), calendar: ljubljana, limit: 15)
        XCTAssertFalse(before.isPaused)
        XCTAssertEqual(before.remaining, 1)
        let after = Allowance.state(trips: trips(15, on: "2026-10-20T08:00:00"), now: date("2026-10-21T08:00:00"), calendar: ljubljana, limit: 15)
        XCTAssertTrue(after.isPaused)
    }

    func testNewMonthResumes() {
        // AE2
        let state = Allowance.state(trips: trips(15, on: "2026-10-20T08:00:00"), now: date("2026-11-01T07:00:00"), calendar: ljubljana, limit: 15)
        XCTAssertEqual(state.used, 0)
        XCTAssertFalse(state.isPaused)
    }

    func testManualTripsAndDiscardedDrivesDontCount() {
        // AE3
        let all = trips(15, on: "2026-10-20T08:00:00", source: .manual) + trips(3, on: "2026-10-20T08:00:00", km: 0.1)
        XCTAssertEqual(Allowance.state(trips: all, now: date("2026-10-21T08:00:00"), calendar: ljubljana, limit: 15).used, 0)
    }

    func testLateEveningTripCountsForItsStartMonth() {
        let state = Allowance.state(trips: trips(1, on: "2026-10-31T23:50:00"), now: date("2026-10-31T23:59:00"), calendar: ljubljana, limit: 15)
        XCTAssertEqual(state.used, 1)
        XCTAssertEqual(Allowance.state(trips: trips(1, on: "2026-10-31T23:50:00"), now: date("2026-11-01T00:10:00"), calendar: ljubljana, limit: 15).used, 0)
    }

    func testChangingTheLimit() {
        let twelve = trips(12, on: "2026-10-20T08:00:00")
        XCTAssertTrue(Allowance.state(trips: twelve, now: date("2026-10-21T08:00:00"), calendar: ljubljana, limit: 10).isPaused)
        XCTAssertFalse(Allowance.state(trips: twelve, now: date("2026-10-21T08:00:00"), calendar: ljubljana, limit: 20).isPaused)
    }

    func testNoticesFollowTheLimit() {
        XCTAssertEqual(Allowance.notice(for: AllowanceState(used: 12, limit: 15)), .threeLeft)
        XCTAssertEqual(Allowance.notice(for: AllowanceState(used: 14, limit: 15)), .oneLeft)
        XCTAssertEqual(Allowance.notice(for: AllowanceState(used: 15, limit: 15)), .paused)
        XCTAssertNil(Allowance.notice(for: AllowanceState(used: 13, limit: 15)))
        XCTAssertEqual(Allowance.notice(for: AllowanceState(used: 7, limit: 10)), .threeLeft)
        XCTAssertEqual(Allowance.notice(for: AllowanceState(used: 9, limit: 10)), .oneLeft)
        XCTAssertNotEqual(Allowance.noticeKey(.oneLeft, now: date("2026-10-21T08:00:00"), calendar: ljubljana),
                          Allowance.noticeKey(.oneLeft, now: date("2026-11-21T08:00:00"), calendar: ljubljana))
    }

    @MainActor
    func testBuiltInLimitWithoutConfig() {
        let defaults = UserDefaults(suiteName: "MileLogTests.config")!
        defaults.removePersistentDomain(forName: "MileLogTests.config")
        XCTAssertEqual(AppConfig(defaults: defaults).freeAutoTripsPerMonth, 15)
        AppConfig(defaults: defaults).apply(limit: 10, fetchedAt: Date())
        XCTAssertEqual(AppConfig(defaults: defaults).freeAutoTripsPerMonth, 10)
    }


    // MARK: - Paid gates and the recording vehicle

    func testFreeGatesPaidFeatures() {
        // AE4: reports and receipts are gated; CSV export has no gate at all.
        XCTAssertFalse(PlanStatus.free.allows(.reports))
        XCTAssertFalse(PlanStatus.free.allows(.receipts))
        XCTAssertFalse(PlanStatus.freeOtherAccount.allows(.monthEndCheck))
        XCTAssertTrue(PlanStatus.paid(until: nil).allows(.reports))
        XCTAssertTrue(PlanStatus.paid(until: nil).allows(.extraVehicle, activeVehicleCount: 3))
    }

    func testFreeAccountsKeepOneActiveVehicle() {
        XCTAssertTrue(PlanStatus.free.allows(.extraVehicle, activeVehicleCount: 0))  // e.g. one archived
        XCTAssertFalse(PlanStatus.free.allows(.extraVehicle, activeVehicleCount: 1))
    }

    private func vehicle(_ name: String) -> Vehicle { Vehicle(name: name, licensePlate: "", type: .own) }

    private func drive(_ v: Vehicle, daysAgo: Double) -> Trip {
        Trip(vehicleID: v.id, type: .business, purpose: "", customerName: "",
             startedAt: Date().addingTimeInterval(-daysAgo * 86_400), endedAt: Date(),
             startAddress: "", endAddress: "", distanceKm: 5, notes: "", isLocked: false)
    }

    func testRecordingVehicleDefaultsToTheLastDriven() {
        let golf = vehicle("Golf"), octavia = vehicle("Octavia")
        let trips = [drive(golf, daysAgo: 3), drive(octavia, daysAgo: 1)]
        XCTAssertEqual(Store.recordingVehicle(vehicles: [golf, octavia], trips: trips, chosenID: nil, isPaid: false)?.id, octavia.id)
        // A choice wins; an archived (missing) choice falls back to the default.
        XCTAssertEqual(Store.recordingVehicle(vehicles: [golf, octavia], trips: trips, chosenID: golf.id, isPaid: false)?.id, golf.id)
        XCTAssertEqual(Store.recordingVehicle(vehicles: [golf, octavia], trips: trips, chosenID: UUID(), isPaid: false)?.id, octavia.id)
    }

    func testNoRecordingRestrictionWhenPaidOrSingleVehicle() {
        let golf = vehicle("Golf"), octavia = vehicle("Octavia")
        XCTAssertNil(Store.recordingVehicle(vehicles: [golf, octavia], trips: [], chosenID: nil, isPaid: true))
        XCTAssertNil(Store.recordingVehicle(vehicles: [golf], trips: [], chosenID: nil, isPaid: false))
    }

    // MARK: - Month-end check

    private func trip(_ day: String, type: TripType = .business, customer: String = "C", purpose: String = "",
                      reviewed: Bool = true, addresses: Bool = true, locked: Bool = false, endedMinutesAgo: Double? = nil) -> Trip {
        let start = date(day)
        var t = Trip(vehicleID: UUID(), type: type, purpose: purpose, customerName: customer,
                     startedAt: start, endedAt: endedMinutesAgo.map { Date().addingTimeInterval(-$0 * 60) } ?? start.addingTimeInterval(1800),
                     startAddress: addresses ? "A" : "", endAddress: addresses ? "B" : "",
                     distanceKm: 5, notes: "", isLocked: locked)
        t.reviewedAt = reviewed ? start : nil
        return t
    }

    @MainActor
    func testMonthEndCheckGroups() {
        let month = date("2026-10-15T12:00:00")
        let unreviewed = trip("2026-10-02T08:00:00", reviewed: false)
        let noDetails = trip("2026-10-03T08:00:00", customer: "")
        let purposeOnly = trip("2026-10-04T08:00:00", customer: "", purpose: "Delivery")
        let privateTrip = trip("2026-10-05T08:00:00", type: .privateTrip, customer: "")
        let otherMonth = trip("2026-09-30T08:00:00", reviewed: false)
        let check = MonthEndCheck.build(trips: [unreviewed, noDetails, purposeOnly, privateTrip, otherMonth], candidates: [],
                                        month: month, calendar: ljubljana, now: date("2026-11-01T08:00:00"))
        XCTAssertEqual(check.unreviewed.map(\.id), [unreviewed.id])
        XCTAssertEqual(check.missingDetails.map(\.id), [noDetails.id])
        XCTAssertEqual(check.openCount, 2)
    }

    @MainActor
    func testLockedTripsAreInformationOnly() {
        let locked = trip("2026-10-03T08:00:00", customer: "", locked: true)
        let check = MonthEndCheck.build(trips: [locked], candidates: [], month: date("2026-10-15T12:00:00"), calendar: ljubljana)
        XCTAssertEqual(check.locked.map(\.id), [locked.id])
        XCTAssertEqual(check.openCount, 0)
    }

    @MainActor
    func testRecentTripsWithoutAddressWait() {
        let now = Date()
        let fresh = trip("2026-10-03T08:00:00", addresses: false, endedMinutesAgo: 20)
        var check = MonthEndCheck.build(trips: [fresh], candidates: [], month: fresh.startedAt, now: now)
        XCTAssertTrue(check.missingAddresses.isEmpty)
        check = MonthEndCheck.build(trips: [fresh], candidates: [], month: fresh.startedAt, now: now.addingTimeInterval(7200))
        XCTAssertEqual(check.missingAddresses.count, 1)
    }

    @MainActor
    func testSplitsAppearOnceAndCleanMonthIsEmpty() {
        let a = trip("2026-10-03T08:00:00"), b = trip("2026-10-03T08:35:00")
        let check = MonthEndCheck.build(trips: [a, b], candidates: [Store.MergeCandidate(first: a, second: b)],
                                        month: a.startedAt, calendar: ljubljana)
        XCTAssertEqual(check.likelySplits.count, 1)
        XCTAssertEqual(check.openCount, 1)
        XCTAssertTrue(MonthEndCheck.build(trips: [a], candidates: [], month: a.startedAt, calendar: ljubljana).isClean)
    }

    // MARK: - Month-aware locking

    func testTripLocksSevenDaysIntoTheNextMonth() {
        // AE7
        let t = trip("2026-11-02T08:00:00")
        XCTAssertFalse(MonthLocking.shouldLock(t, closed: [], daysIntoNextMonth: 7, now: date("2026-11-30T12:00:00"), calendar: ljubljana))
        XCTAssertTrue(MonthLocking.shouldLock(t, closed: [], daysIntoNextMonth: 7, now: date("2026-12-08T12:00:00"), calendar: ljubljana))
    }

    func testClosedMonthLocksOnlyItsVehicles() {
        let own = trip("2026-10-20T08:00:00"), company = trip("2026-10-20T09:00:00")
        let closed: Set<ClosedMonthKey> = [ClosedMonthKey(vehicleID: own.vehicleID, month: "2026-10")]
        let now = date("2026-11-02T08:00:00")
        XCTAssertTrue(MonthLocking.shouldLock(own, closed: closed, daysIntoNextMonth: 7, now: now, calendar: ljubljana))
        XCTAssertFalse(MonthLocking.shouldLock(company, closed: closed, daysIntoNextMonth: 7, now: now, calendar: ljubljana))
    }

    func testCurrentMonthReportClosesNothing() {
        XCTAssertFalse(MonthLocking.monthHasEnded(date("2026-10-15T08:00:00"), now: date("2026-10-15T09:00:00"), calendar: ljubljana))
        XCTAssertTrue(MonthLocking.monthHasEnded(date("2026-10-15T08:00:00"), now: date("2026-11-01T00:00:00"), calendar: ljubljana))
    }

    func testLockSettingIsClampedToTwentyEightDays() throws {
        let json = try JSONSerialization.data(withJSONObject: ["lockAfterDays": 60])
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: json).lockAfterDays, 28)
        XCTAssertEqual(MonthLocking.clampDays(0), 1)
    }

    func testReminderIsOnTheLastDayAtSix() {
        let fire = NotificationManager.monthEndReminderDate(after: date("2026-02-10T08:00:00"), calendar: ljubljana)!
        let c = ljubljana.dateComponents([.month, .day, .hour], from: fire)
        XCTAssertEqual([c.month, c.day, c.hour], [2, 28, 18])
    }

    // MARK: - Usage figures

    func testNoUsageWithoutConsent() {
        let defaults = UserDefaults(suiteName: "MileLogTests.usage")!
        defaults.removePersistentDomain(forName: "MileLogTests.usage")
        let usage = MainActor.assumeIsolated { Usage(defaults: defaults) }
        MainActor.assumeIsolated {
            usage.consent = false
            usage.record(.reportGenerations, now: date("2026-10-10T08:00:00"))
        }
        XCTAssertEqual(defaults.integer(forKey: Usage.countKey(.reportGenerations, month: "2026-10")), 0)
        MainActor.assumeIsolated {
            usage.consent = true
            usage.record(.reportGenerations, now: date("2026-10-10T08:00:00"))
        }
        XCTAssertEqual(defaults.integer(forKey: Usage.countKey(.reportGenerations, month: "2026-10")), 1)
    }

    func testOctoberIsSentAsABucketAfterItEnds() {
        let october = trips(13, on: "2026-10-12T08:00:00")
        let sent = Usage.submissions(month: date("2026-10-15T12:00:00"), now: date("2026-11-03T09:00:00"),
                                     trips: october, counts: [.reportGenerations: 2], calendar: ljubljana)
        XCTAssertEqual(sent.first { $0.metric == .autoTrips }?.bucket, "11-15")
        XCTAssertEqual(sent.first { $0.metric == .reportGenerations }?.bucket, "1-5")
        XCTAssertEqual(sent.count, Usage.Metric.allCases.count)
    }

    func testNothingIsSentForTheRunningMonth() {
        XCTAssertTrue(Usage.submissions(month: date("2026-10-15T12:00:00"), now: date("2026-10-30T09:00:00"),
                                        trips: [], counts: [:], calendar: ljubljana).isEmpty)
    }

    func testBuckets() {
        XCTAssertEqual([0, 1, 5, 6, 15, 16, 26, 51, 101].map(Usage.bucket), ["0", "1-5", "1-5", "6-10", "11-15", "16-25", "26-50", "51-100", "101+"])
    }

    // MARK: - Developer plan override

    func testOverrideMapsToThePretendedPlan() {
        let real = PlanStatus.paid(until: nil)
        XCTAssertEqual(DeveloperPlanOverride.none.apply(to: real), real)
        XCTAssertEqual(DeveloperPlanOverride.free.apply(to: real), .free)
        XCTAssertEqual(DeveloperPlanOverride.lapsed.apply(to: real), .free)
        XCTAssertEqual(DeveloperPlanOverride.otherAccount.apply(to: real), .freeOtherAccount)
        XCTAssertTrue(DeveloperPlanOverride.paid.apply(to: .free).isPaid)
    }

    @MainActor
    func testOverrideNeverReachesThePlanCache() async {
        let defaults = UserDefaults(suiteName: "MileLogTests.override")!
        defaults.removePersistentDomain(forName: "MileLogTests.override")
        let cache = PlanCache(defaults: defaults)
        cache.save(CachedPlan(userID: me, isPaid: false, expiresAt: nil, checkedAt: now))
        cache.lastUserID = me
        let store = SubscriptionStore(defaults: defaults)
        store.developerOverride = .paid
        XCTAssertTrue(store.plan.isPaid)          // tests run as a debug build
        XCTAssertEqual(cache.load(for: me)?.isPaid, false)
        store.developerOverride = .none
        XCTAssertFalse(store.plan.isPaid)
    }
}
