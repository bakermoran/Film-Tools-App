//
//  Reciprocity_Failure_CalculatorTests.swift
//  Reciprocity Failure CalculatorTests
//
//  Created by Baker Moran on 2/10/25.
//

import Foundation
import Testing
@testable import Reciprocity_Failure_Calculator

struct PowerModelTests {
    let hp5 = ReciprocityModel.power(exponent: 1.31, threshold: 1)

    @Test func readmeExamples() {
        // HP5+ at 10s ≈ 20s, Delta 400 at 10s ≈ 26s (from the README).
        #expect(hp5.correctedTime(forMetered: 10).rounded() == 20)
        let delta400 = ReciprocityModel.power(exponent: 1.41, threshold: 1)
        #expect(delta400.correctedTime(forMetered: 10).rounded() == 26)
    }

    @Test func noCorrectionAtOrBelowThreshold() {
        #expect(hp5.correctedTime(forMetered: 0.5) == 0.5)
        #expect(hp5.correctedTime(forMetered: 1) == 1)
        #expect(!hp5.result(forMetered: 1).needsCorrection)
    }

    @Test func neverExtrapolated() {
        #expect(!hp5.isExtrapolated(10_000))
    }
}

struct TableModelTests {
    // Anchor (no correction to 0.1s), then 1s→2s, 10s→50s, 100s→1200s.
    let table = ReciprocityModel.table([
        TablePoint(metered: 0.1, corrected: 0.1),
        TablePoint(metered: 1, corrected: 2),
        TablePoint(metered: 10, corrected: 50),
        TablePoint(metered: 100, corrected: 1200),
    ])

    @Test func hitsPublishedPointsExactly() {
        #expect(abs(table.correctedTime(forMetered: 1) - 2) < 1e-9)
        #expect(abs(table.correctedTime(forMetered: 10) - 50) < 1e-9)
        #expect(abs(table.correctedTime(forMetered: 100) - 1200) < 1e-6)
    }

    @Test func noCorrectionBelowFirstPoint() {
        #expect(table.correctedTime(forMetered: 0.05) == 0.05)
        #expect(table.correctedTime(forMetered: 0.1) == 0.1)
    }

    @Test func interpolatesInLogSpace() {
        // Halfway between 1 and 10 in log space is √10; corrected should be √(2·50) = 10.
        let t = table.correctedTime(forMetered: 10.0.squareRoot())
        #expect(abs(t - 10) < 1e-9)
    }

    @Test func monotonic() {
        var last = 0.0
        for t in stride(from: 0.05, through: 500, by: 0.37) {
            let c = table.correctedTime(forMetered: t)
            #expect(c >= last)
            #expect(c >= t)
            last = c
        }
    }

    @Test func extrapolatesPastLastPoint() {
        #expect(!table.isExtrapolated(100))
        #expect(table.isExtrapolated(200))
        // Continues the last segment's slope, so it keeps growing.
        #expect(table.correctedTime(forMetered: 200) > 1200)
        #expect(table.result(forMetered: 200).isExtrapolated)
    }

    @Test func extraStops() {
        let r = table.result(forMetered: 1)
        #expect(abs(r.extraStops - 1) < 1e-9)
    }
}

struct ExposureParsingTests {
    @Test(arguments: [
        ("30", 30.0), ("0.5", 0.5), ("1/4", 0.25), ("1/2s", 0.5), ("30s", 30),
        ("2m", 120), ("2m30s", 150), ("2m30", 150), ("1h5m", 3900), ("1:30", 90),
        ("1:02:30", 3750), (" 1.5m ", 90), ("0,5", 0.5),
    ])
    func parses(input: String, expected: Double) {
        #expect(ExposureFormat.parse(input) == expected)
    }

    @Test(arguments: ["", "abc", "0", "-5", "1/0", "1:", "2m2m", "5x", "1/2/3"])
    func rejects(input: String) {
        #expect(ExposureFormat.parse(input) == nil)
    }
}

struct ExposureFormattingTests {
    @Test(arguments: [
        (0.004, "1/250 s"), (0.5, "1/2 s"), (0.7, "0.7 s"), (2, "2 s"), (2.5, "2.5 s"),
        (19.95, "20 s"), (134, "2m 14s"), (3800, "1h 03m 20s"),
    ])
    func durations(seconds: Double, expected: String) {
        #expect(ExposureFormat.string(fromSeconds: seconds) == expected)
    }

    @Test func clock() {
        #expect(ExposureFormat.clock(fromSeconds: 42) == "0:42")
        #expect(ExposureFormat.clock(fromSeconds: 41.2) == "0:42")
        #expect(ExposureFormat.clock(fromSeconds: 3729) == "1:02:09")
    }

    @Test func stops() {
        #expect(ExposureFormat.stops(0) == "no change")
        #expect(ExposureFormat.stops(1) == "+1 stop")
        #expect(ExposureFormat.stops(1.33) == "+1.3 stops")
        #expect(ExposureFormat.stops(2) == "+2 stops")
    }
}

struct FilmDecodingTests {
    @Test func decodesLegacyPowerFormat() throws {
        let json = #"[{"brand":"Ilford","stock":"HP5+","factor":1.31,"starts_at":1}]"#
        let film = try #require(try JSONDecoder().decode([Film].self, from: Data(json.utf8)).first)
        #expect(film.model == .power(exponent: 1.31, threshold: 1))
        #expect(film.id == "Ilford|HP5+")
    }

    @Test func decodesTableAndSortsPoints() throws {
        let json = #"""
        [{"brand":"Kodak","stock":"Test","iso":400,"type":"bw",
          "table":[{"metered":10,"corrected":50},{"metered":1,"corrected":2}]}]
        """#
        let film = try #require(try JSONDecoder().decode([Film].self, from: Data(json.utf8)).first)
        #expect(film.model == .table([TablePoint(metered: 1, corrected: 2), TablePoint(metered: 10, corrected: 50)]))
        #expect(film.type == .blackAndWhite)
        #expect(film.iso == 400)
    }

    @Test func rejectsFilmWithoutData() {
        let json = #"[{"brand":"X","stock":"Y"}]"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Film].self, from: Data(json.utf8)) }
    }

    @Test func roundTrips() throws {
        let films = [
            Film(brand: "A", stock: "B", iso: 100, type: .slide, model: .power(exponent: 1.2, threshold: 2)),
            Film(brand: "C", stock: "D", model: .table([TablePoint(metered: 1, corrected: 1), TablePoint(metered: 8, corrected: 12)])),
        ]
        let decoded = try JSONDecoder().decode([Film].self, from: JSONEncoder().encode(films))
        #expect(decoded == films)
    }

    @Test func bundledDatabaseLoads() throws {
        // Unit tests are hosted in the app, so Bundle.main is the app bundle.
        let store = FilmStore(bundle: .main)
        #expect(store.loadError == nil)
        #expect(!store.bundled.isEmpty)
        #expect(Set(store.bundled.map(\.id)).count == store.bundled.count, "duplicate film IDs")
    }
}

struct FilmStoreTests {
    let tempURL = FileManager.default.temporaryDirectory.appending(path: "custom-\(UUID().uuidString).json")

    @Test func customFilmsPersist() throws {
        let store = FilmStore(bundledData: nil, customURL: tempURL)
        try store.addCustom(Film(brand: "Mine", stock: "Roll", model: .power(exponent: 1.3, threshold: 1)))
        #expect(store.contains(brand: "mine", stock: "ROLL"))

        let reloaded = FilmStore(bundledData: nil, customURL: tempURL)
        #expect(reloaded.custom.count == 1)
        #expect(reloaded.custom.first?.isCustom == true)

        try reloaded.deleteCustom(id: "Mine|Roll")
        #expect(FilmStore(bundledData: nil, customURL: tempURL).custom.isEmpty)
    }

    @Test func groupsAndSearches() throws {
        let json = #"""
        [{"brand":"Kodak","stock":"Tri-X","iso":400,"factor":1.3},
         {"brand":"Ilford","stock":"HP5+","iso":400,"factor":1.31},
         {"brand":"Ilford","stock":"FP4+","iso":125,"factor":1.26}]
        """#
        let store = FilmStore(bundledData: Data(json.utf8), customURL: tempURL)
        let groups = store.grouped()
        #expect(groups.map(\.brand) == ["Ilford", "Kodak"])
        #expect(groups[0].films.map(\.stock) == ["FP4+", "HP5+"])
        #expect(store.grouped(matching: "400").flatMap(\.films).count == 2)
        #expect(store.grouped(matching: "hp5").flatMap(\.films).map(\.stock) == ["HP5+"])
    }
}

struct FlashTests {
    // GN 36 m at ISO 100, down to 1/128 in thirds.
    let flash = FlashSetup(guideNumber: 36)

    @Test func guideNumberScalesWithISOAndPower() {
        #expect(abs(flash.guideNumber(iso: 400) - 72) < 1e-9)
        #expect(abs(flash.guideNumber(iso: 400, powerThirds: -6) - 36) < 1e-9)
        #expect(abs(FlashSetup(guideNumber: 36, ratedISO: 200).guideNumber(iso: 50) - 18) < 1e-9)
    }

    @Test func distanceAndAperture() {
        #expect(abs(flash.distance(iso: 100, powerThirds: 0, fNumber: 8) - 4.5) < 1e-9)
        #expect(abs(flash.fNumber(iso: 100, powerThirds: 0, distance: 4.5) - 8) < 1e-9)
    }

    @Test func powerSettings() {
        #expect(flash.power(iso: 100, fNumber: 8, distance: 4.5) == .setting(thirds: 0, offBy: 0))
        // Half the distance needs a quarter of the light: 1/4 power.
        guard case let .setting(thirds, offBy) = flash.power(iso: 100, fNumber: 8, distance: 2.25) else {
            Issue.record("expected a setting"); return
        }
        #expect(thirds == -6)
        #expect(abs(offBy) < 1e-9)
    }

    @Test func roundsToAvailableSteps() {
        // 1.5 stops below full: thirds rounds to -5 (1/4 +⅓), whole stops to -6 (1/4).
        let d = 4.5 * pow(2, -0.75)
        guard case let .setting(thirds, _) = flash.power(iso: 100, fNumber: 8, distance: d) else {
            Issue.record("expected a setting"); return
        }
        #expect(thirds == -5 || thirds == -4)
        var whole = flash
        whole.thirdSteps = false
        guard case let .setting(wholeThirds, _) = whole.power(iso: 100, fNumber: 8, distance: d * 0.99) else {
            Issue.record("expected a setting"); return
        }
        #expect(wholeThirds == -6)
    }

    @Test func outOfRange() {
        guard case let .beyondFull(stops) = flash.power(iso: 100, fNumber: 8, distance: 9) else {
            Issue.record("expected beyondFull"); return
        }
        #expect(abs(stops - 2) < 1e-9)
        guard case .belowLowest = flash.power(iso: 100, fNumber: 8, distance: 0.2) else {
            Issue.record("expected belowLowest"); return
        }
        let reach = flash.reach(iso: 100, fNumber: 8)
        #expect(abs(reach.far - 4.5) < 1e-9)
        #expect(abs(reach.near - 4.5 / pow(2, 3.5)) < 1e-9)
    }

    @Test func fillNeedsLessPower() {
        // Two stops of fill is a quarter of the light: same as doubling the distance.
        let full = flash.exactPower(iso: 400, fNumber: 16, distance: 2)
        let fill = flash.exactPower(iso: 400, fNumber: 16, distance: 2, exposure: -2)
        #expect(abs(full - fill - 2) < 1e-9)
        #expect(abs(flash.reach(iso: 100, fNumber: 8, exposure: -2).far - 9) < 1e-9)
    }

    @Test(arguments: [(0, "1/1"), (-1, "1/2 +⅔"), (-3, "1/2"), (-6, "1/4"), (-10, "1/16 +⅔"), (-21, "1/128")])
    func powerLabels(thirds: Int, expected: String) {
        #expect(FlashPower.label(thirds) == expected)
    }

    @Test(arguments: [(18, "f/8"), (15, "f/5.6"), (24, "f/16"), (29, "f/29"), (3, "f/1.4"), (40, "f/101.6")])
    func apertureLabels(thirds: Int, expected: String) {
        #expect(Aperture.label(thirds) == expected)
    }

    @Test func apertureRoundTrip() {
        for t in Aperture.choices {
            #expect(Aperture.nearest(to: Aperture.fNumber(t)) == t)
        }
        #expect(Aperture.nearest(to: 5.6) == 15)
    }

    @Test func powerLevels() {
        #expect(FlashPower.levels(lowest: -9, thirdSteps: false) == [0, -3, -6, -9])
        #expect(FlashPower.levels(lowest: -3, thirdSteps: true) == [0, -1, -2, -3])
    }
}

struct DaylightTests {
    let sun = DaylightCondition.all[0]
    let shade = DaylightCondition.all[4]

    @Test func sunny16AtSyncSpeed() {
        // ISO 400 in sun at 1/125 is f/16 × √3.2 ≈ f/29.
        #expect(sun.exposure(iso: 400, syncDenominator: 125) == AmbientExposure(apertureThirds: 29, shutterDenominator: 125))
        // ISO 100 at 1/125 is a third wider than f/16.
        #expect(sun.exposure(iso: 100, syncDenominator: 125).apertureThirds == 23)
        // Leaf shutter at 1/500 with ISO 400: f/16 × √0.8 ≈ f/14.
        #expect(sun.exposure(iso: 400, syncDenominator: 500).apertureThirds == 23)
    }

    @Test func slowsShutterRatherThanOpeningPastF28() {
        let e = shade.exposure(iso: 25, syncDenominator: 125)
        #expect(e.shutterDenominator == 30)
        #expect(e.apertureThirds == 11)
        // Bright enough already: stays at sync.
        #expect(shade.exposure(iso: 400, syncDenominator: 125).shutterDenominator == 125)
    }
}

struct FlashFormatTests {
    @Test func formats() {
        #expect(FlashFormat.distance(4.5, .meters) == "4.5 m")
        #expect(FlashFormat.distance(12.4, .feet) == "12 ft")
        #expect(FlashFormat.stops(0.33) == "0.3 stops")
        #expect(FlashFormat.stops(-1) == "1 stop")
        #expect(FlashFormat.parse("3,5") == 3.5)
        #expect(FlashFormat.parse("0") == nil)
    }
}
