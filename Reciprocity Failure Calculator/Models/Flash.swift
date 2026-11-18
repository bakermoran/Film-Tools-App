//
//  Flash.swift
//  Reciprocity Failure Calculator
//
//  Guide number math for manual flash: GN = distance × f-number.
//  Doubling ISO or flash power multiplies GN by √2.
//

import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable {
    case meters = "m"
    case feet = "ft"

    var id: String { rawValue }
}

// MARK: - Stops

/// Apertures counted in thirds of a stop from f/1, so 18 is f/8 and 24 is f/16.
enum Aperture {
    /// Lens markings for each third stop, indexed by thirds from f/1.
    private static let nominal: [Double] = [
        1, 1.1, 1.2, 1.4, 1.6, 1.8, 2, 2.2, 2.5, 2.8, 3.2, 3.5, 4, 4.5, 5, 5.6, 6.3, 7.1,
        8, 9, 10, 11, 13, 14, 16, 18, 20, 22, 25, 29, 32, 36, 40, 45, 51, 57, 64,
    ]

    /// The choices offered in pickers: f/1.4 to f/45.
    static let choices = Array(3...33)
    /// f/22, the smallest aperture most lenses have.
    static let smallestCommon = 27

    /// The precise f-number (f/5.6 is really 5.657).
    static func fNumber(_ thirds: Int) -> Double { pow(2, Double(thirds) / 6) }

    static func nearest(to fNumber: Double) -> Int { Int((6 * log2(fNumber)).rounded()) }

    static func label(_ thirds: Int) -> String {
        let value = nominal.indices.contains(thirds) ? nominal[thirds] : (fNumber(thirds) * 10).rounded() / 10
        return "f/" + String(format: "%g", value)
    }
}

/// Flash power counted in thirds of a stop below full, so 0 is 1/1 and -6 is 1/4.
enum FlashPower {
    /// `1/1`, `1/4`, `1/8 +⅔` (the way most flashes show third steps).
    static func label(_ thirds: Int) -> String {
        let full = Int((Double(thirds) / 3).rounded(.down))
        let extra = thirds - full * 3
        let base = full >= 0 ? "1/1" : "1/\(1 << -full)"
        return base + ["", " +⅓", " +⅔"][extra]
    }

    /// Settings from full power down to `lowest`.
    static func levels(lowest: Int, thirdSteps: Bool) -> [Int] {
        Array(stride(from: 0, through: lowest, by: thirdSteps ? -1 : -3))
    }

    /// Lowest-power options a flash might have, in thirds.
    static let lowestChoices = [-12, -15, -18, -21, -24]
}

// MARK: - Flash

enum PowerResult: Equatable {
    /// `offBy` is how far the setting is from the exact answer, in stops. Positive means brighter.
    case setting(thirds: Int, offBy: Double)
    /// Needs this many stops more than full power.
    case beyondFull(stops: Double)
    /// Needs this many stops less than the lowest setting.
    case belowLowest(stops: Double)
}

struct FlashSetup: Equatable {
    /// Full-power guide number at `ratedISO`, in the same unit as distances.
    var guideNumber: Double
    var ratedISO: Double = 100
    var lowestThirds: Int = -21
    var thirdSteps: Bool = true

    func guideNumber(iso: Double, powerStops: Double = 0) -> Double {
        guideNumber * (iso / ratedISO).squareRoot() * pow(2, powerStops / 2)
    }

    func guideNumber(iso: Double, powerThirds: Int) -> Double {
        guideNumber(iso: iso, powerStops: Double(powerThirds) / 3)
    }

    func distance(iso: Double, powerThirds: Int, fNumber: Double) -> Double {
        guideNumber(iso: iso, powerThirds: powerThirds) / fNumber
    }

    func fNumber(iso: Double, powerThirds: Int, distance: Double) -> Double {
        guideNumber(iso: iso, powerThirds: powerThirds) / distance
    }

    /// Exact power in stops below full (0 = full) to light a subject at `distance`.
    /// `exposure` offsets the result in stops, e.g. -1.7 for fill flash.
    func exactPower(iso: Double, fNumber: Double, distance: Double, exposure: Double = 0) -> Double {
        let needed = distance * fNumber * pow(2, exposure / 2)
        return 2 * log2(needed / guideNumber(iso: iso))
    }

    /// The nearest power setting the flash can actually make.
    func power(iso: Double, fNumber: Double, distance: Double, exposure: Double = 0) -> PowerResult {
        let exact = exactPower(iso: iso, fNumber: fNumber, distance: distance, exposure: exposure)
        let step = thirdSteps ? 1 : 3
        let thirds = Int((exact * 3 / Double(step)).rounded()) * step
        if thirds > 0 { return .beyondFull(stops: exact) }
        if thirds < lowestThirds { return .belowLowest(stops: Double(lowestThirds) / 3 - exact) }
        return .setting(thirds: thirds, offBy: Double(thirds) / 3 - exact)
    }

    /// Closest (lowest power) and farthest (full power) subject distances that can be lit.
    func reach(iso: Double, fNumber: Double, exposure: Double = 0) -> (near: Double, far: Double) {
        let scale = fNumber * pow(2, exposure / 2)
        return (guideNumber(iso: iso, powerThirds: lowestThirds) / scale, guideNumber(iso: iso) / scale)
    }
}

// MARK: - Fill flash

enum FillLevel: Int, CaseIterable, Identifiable {
    case balanced = 0
    case strong = -3
    case natural = -5
    case subtle = -6

    var id: Int { rawValue }
    var stops: Double { Double(rawValue) / 3 }

    var label: String {
        switch self {
        case .balanced: "0"
        case .strong: "−1"
        case .natural: "−1⅔"
        case .subtle: "−2"
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .balanced: "Flash matches the daylight. Use for backlit subjects or a subject in shade against a sunlit background."
        case .strong: "Strong fill. Shadows on the subject are one stop darker than the highlights."
        case .natural: "Natural fill. Opens up shadows without looking flashed. A good default."
        case .subtle: "Subtle fill. Just lifts the shadows."
        }
    }
}

struct AmbientExposure: Equatable {
    var apertureThirds: Int
    var shutterDenominator: Int

    var shutterLabel: String { "1/\(shutterDenominator)" }
}

/// Sunny 16 lighting conditions. Each aperture is correct at a shutter of 1/ISO.
struct DaylightCondition: Identifiable {
    let name: LocalizedStringResource
    let symbol: String
    let sunny16Thirds: Int

    var id: String { symbol }

    static let all = [
        DaylightCondition(name: "Bright sun", symbol: "sun.max", sunny16Thirds: 24),
        DaylightCondition(name: "Hazy sun", symbol: "sun.haze", sunny16Thirds: 21),
        DaylightCondition(name: "Cloudy", symbol: "cloud.sun", sunny16Thirds: 18),
        DaylightCondition(name: "Overcast", symbol: "cloud", sunny16Thirds: 15),
        DaylightCondition(name: "Open shade", symbol: "beach.umbrella", sunny16Thirds: 12),
    ]

    static let syncSpeeds = [30, 50, 60, 90, 125, 200, 250, 500]

    /// The daylight exposure to use with flash. Shoots at the sync speed so the aperture is as wide
    /// as it can be (which needs the least flash power), but slows the shutter if that would mean
    /// opening wider than f/2.8.
    func exposure(iso: Double, syncDenominator: Int) -> AmbientExposure {
        Self.exposure(sunny16Thirds: sunny16Thirds, iso: iso, syncDenominator: syncDenominator)
    }

    static func exposure(sunny16Thirds: Int, iso: Double, syncDenominator: Int) -> AmbientExposure {
        func aperture(_ denominator: Int) -> Int {
            sunny16Thirds + Int((3 * log2(iso / Double(denominator))).rounded())
        }
        var result = AmbientExposure(apertureThirds: aperture(syncDenominator), shutterDenominator: syncDenominator)
        for slower in [250, 125, 60, 30] where slower < syncDenominator && result.apertureThirds < 9 {
            result = AmbientExposure(apertureThirds: aperture(slower), shutterDenominator: slower)
        }
        return result
    }
}

enum FlashFormat {
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    static func distance(_ value: Double, _ unit: DistanceUnit) -> String {
        "\(number(value)) \(unit.rawValue)"
    }

    /// `0.3 stops`, `1 stop`
    static func stops(_ stops: Double) -> String {
        let rounded = (abs(stops) * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return rounded == 1 ? String(localized: "\(text) stop") : String(localized: "\(text) stops")
    }

    static func parse(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite, value > 0 else { return nil }
        return value
    }
}
