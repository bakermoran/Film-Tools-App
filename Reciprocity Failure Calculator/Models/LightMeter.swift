//
//  LightMeter.swift
//  Reciprocity Failure Calculator
//
//  Exposure value math for the camera light meter.
//  EV = log2(N² / t) at ISO 100. Each doubling of ISO adds one EV.
//

import Foundation

enum MeterMode: String, CaseIterable, Identifiable {
    case spot
    case incident
    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .spot: "Spot"
        case .incident: "Incident"
        }
    }
}

enum MeterPriority: String, CaseIterable, Identifiable {
    case aperture
    case shutter
    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .aperture: "Aperture priority"
        case .shutter: "Shutter priority"
        }
    }
}

/// Shutter speeds counted in thirds of a stop from 1 s. Positive is faster, so 3 is 1/2 and 21 is 1/125.
enum Shutter {
    /// Dial markings for 1 s and faster, indexed by thirds: 1/1.3, 1/1.6, 1/2 …
    private static let fast: [Double] = [
        1, 1.3, 1.6, 2, 2.5, 3, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30, 40, 50, 60, 80, 100, 125, 160, 200,
        250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000,
    ]
    /// Dial markings for 1 s and slower, indexed by thirds: 1.3 s, 1.6 s, 2 s …
    private static let slow: [Double] = [1, 1.3, 1.6, 2, 2.5, 3, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30]

    /// 30 s to 1/8000.
    static let choices = Array(-15...39)
    static let fastest = 39

    static func seconds(_ thirds: Int) -> Double { pow(2, -Double(thirds) / 3) }

    static func nearest(toSeconds seconds: Double) -> Int { Int((-3 * log2(seconds)).rounded()) }

    /// `1/250`, `1/2`, `1 s`, `2.5 s`
    static func label(_ thirds: Int) -> String {
        if thirds > 0 {
            let denominator = fast.indices.contains(thirds) ? fast[thirds] : (1 / seconds(thirds)).rounded()
            return "1/" + String(format: "%g", denominator)
        }
        let value = slow.indices.contains(-thirds) ? slow[-thirds] : seconds(thirds).rounded()
        return String(format: "%g s", value)
    }
}

enum LightMeter {
    /// The scene brightness at ISO 100 for an exposure the camera chose.
    static func ev100(fNumber: Double, seconds: Double, iso: Double) -> Double {
        log2(fNumber * fNumber / seconds) - log2(iso / 100)
    }

    /// The exposure value to set on a camera loaded with `iso` film.
    static func ev(_ ev100: Double, iso: Double) -> Double { ev100 + log2(iso / 100) }

    static func seconds(ev: Double, fNumber: Double) -> Double { fNumber * fNumber / pow(2, ev) }

    static func fNumber(ev: Double, seconds: Double) -> Double { (seconds * pow(2, ev)).squareRoot() }

    static let isoChoices = [
        25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000,
        2500, 3200, 6400,
    ]

    /// Whole-stop apertures for the equivalent exposures table: f/1.4 to f/22.
    static let pairApertures = Array(stride(from: 3, through: Aperture.smallestCommon, by: 3))
}

enum MeterFormat {
    /// Rounds to the nearest third of a stop: `12`, `12⅓`, `−⅔`, `+1`.
    static func thirds(_ value: Double, signed: Bool = false) -> String {
        let total = Int((value * 3).rounded())
        let sign = total < 0 ? "−" : (signed && total > 0 ? "+" : "")
        let whole = abs(total) / 3
        let fraction = ["", "⅓", "⅔"][abs(total) % 3]
        return sign + (whole == 0 && !fraction.isEmpty ? "" : String(whole)) + fraction
    }

    static func ev(_ value: Double) -> String { "EV " + thirds(value) }

    /// Dial style below a second (`1/250`), a duration above it (`2 s`, `1m 04s`).
    static func shutter(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        if seconds < 1 { return Shutter.label(Shutter.nearest(toSeconds: seconds)) }
        return ExposureFormat.string(fromSeconds: seconds)
    }

    /// Text for the Reciprocity tab's metered field: `1.3`, `12`, `2m`, `2m05s`.
    static func reciprocityInput(_ seconds: Double) -> String {
        if seconds < 10 { return String(format: "%g", (seconds * 10).rounded() / 10) }
        let total = Int(seconds.rounded())
        if total < 60 { return String(total) }
        let remainder = total % 60
        return "\(total / 60)m" + (remainder == 0 ? "" : String(format: "%02ds", remainder))
    }
}
