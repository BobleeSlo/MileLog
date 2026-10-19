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

    // MARK: - Language

    func testNativeLanguageNames() {
        XCTAssertEqual(AppLanguage.nativeName(for: "sl"), "Slovenščina")
        XCTAssertEqual(AppLanguage.nativeName(for: "en"), "English")
    }

    @MainActor
    func testAppShipsSlovenian() {
        XCTAssertTrue(AppLanguage().available.contains("sl"))
    }
}
