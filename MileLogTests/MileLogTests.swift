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

    /// Same samples as the SQL rule in 20261021100000_add_trip_source.sql:
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
}
