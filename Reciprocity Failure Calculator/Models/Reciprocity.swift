//
//  Reciprocity.swift
//  Reciprocity Failure Calculator
//

import Foundation

struct ReciprocityResult: Equatable {
    let metered: Double
    let corrected: Double
    /// True when the metered time is past the last published data point.
    let isExtrapolated: Bool

    /// Extra exposure in stops (each stop doubles the time).
    var extraStops: Double { log2(corrected / metered) }
    var needsCorrection: Bool { corrected > metered * 1.0001 }
}

extension ReciprocityModel {
    func result(forMetered metered: Double) -> ReciprocityResult {
        ReciprocityResult(
            metered: metered,
            corrected: correctedTime(forMetered: metered),
            isExtrapolated: isExtrapolated(metered))
    }

    func correctedTime(forMetered metered: Double) -> Double {
        guard metered > 0 else { return metered }

        switch self {
        case let .power(exponent, threshold):
            guard metered > threshold else { return metered }
            return pow(metered, exponent)

        case let .table(points):
            guard let first = points.first, metered > first.metered else { return metered }
            guard points.count > 1 else {
                // A single point only says when correction starts; scale by its ratio.
                return metered * first.corrected / first.metered
            }
            // Find the segment containing `metered`, or use the last one to extrapolate.
            let upper = points.firstIndex { $0.metered >= metered } ?? points.count - 1
            return interpolateLogLog(points[upper - 1], points[upper], at: metered)
        }
    }

    func isExtrapolated(_ metered: Double) -> Bool {
        switch self {
        case .power: false
        case let .table(points): points.count > 0 && metered > points[points.count - 1].metered
        }
    }

    /// The longest metered time that needs no correction.
    var correctionStartsAt: Double {
        switch self {
        case let .power(_, threshold): threshold
        case let .table(points): points.first?.metered ?? 0
        }
    }

    private func interpolateLogLog(_ a: TablePoint, _ b: TablePoint, at t: Double) -> Double {
        let x0 = log(a.metered), x1 = log(b.metered)
        let y0 = log(a.corrected), y1 = log(b.corrected)
        guard x1 != x0 else { return b.corrected }
        let y = y0 + (log(t) - x0) * (y1 - y0) / (x1 - x0)
        return exp(y)
    }
}
