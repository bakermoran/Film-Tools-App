//
//  Film.swift
//  Reciprocity Failure Calculator
//

import Foundation

enum FilmType: String, Codable, CaseIterable, Identifiable {
    case blackAndWhite = "bw"
    case colorNegative = "color"
    case slide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blackAndWhite: String(localized: "Black & White")
        case .colorNegative: String(localized: "Color Negative")
        case .slide: String(localized: "Slide")
        }
    }
}

/// A manufacturer data point: a metered exposure and the exposure it should become.
/// Times are in seconds.
struct TablePoint: Codable, Hashable {
    var metered: Double
    var corrected: Double
}

/// How a film's reciprocity failure is described.
enum ReciprocityModel: Hashable {
    /// `corrected = metered ^ exponent` for metered times above `threshold` seconds (Ilford style).
    case power(exponent: Double, threshold: Double)
    /// Interpolated in log-log space between published points (Kodak / Fujifilm style).
    /// Metered times below the first point get no correction, so the first point should be the
    /// longest time the manufacturer says needs no compensation.
    case table([TablePoint])
}

struct Film: Identifiable, Hashable {
    var brand: String
    var stock: String
    var iso: Int?
    var type: FilmType?
    var model: ReciprocityModel
    var notes: String?
    var source: URL?
    /// True for films the user added. Not stored in JSON; set by `FilmStore`.
    var isCustom = false

    var id: String { "\(brand)|\(stock)" }
    var name: String { "\(brand) \(stock)" }
}

// The JSON keeps the original flat shape (`factor` / `starts_at`) so existing data still loads.
// A film has either `factor` or `table`.
extension Film: Codable {
    private enum CodingKeys: String, CodingKey {
        case brand, stock, iso, type, factor, table, notes, source
        case startsAt = "starts_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brand = try c.decode(String.self, forKey: .brand)
        stock = try c.decode(String.self, forKey: .stock)
        iso = try c.decodeIfPresent(Int.self, forKey: .iso)
        type = try c.decodeIfPresent(FilmType.self, forKey: .type)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        source = try c.decodeIfPresent(URL.self, forKey: .source)

        if let points = try c.decodeIfPresent([TablePoint].self, forKey: .table) {
            guard !points.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .table, in: c, debugDescription: "\(brand) \(stock): table is empty")
            }
            model = .table(points.sorted { $0.metered < $1.metered })
        } else if let factor = try c.decodeIfPresent(Double.self, forKey: .factor) {
            let threshold = try c.decodeIfPresent(Double.self, forKey: .startsAt) ?? 1
            model = .power(exponent: factor, threshold: threshold)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .factor, in: c,
                debugDescription: "\(brand) \(stock): needs either `factor` or `table`")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(brand, forKey: .brand)
        try c.encode(stock, forKey: .stock)
        try c.encodeIfPresent(iso, forKey: .iso)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(source, forKey: .source)
        switch model {
        case let .power(exponent, threshold):
            try c.encode(exponent, forKey: .factor)
            try c.encode(threshold, forKey: .startsAt)
        case let .table(points):
            try c.encode(points, forKey: .table)
        }
    }
}
