//
//  FilmStore.swift
//  Reciprocity Failure Calculator
//

import Foundation
import Observation

/// Bundled films from `data.json` plus films the user added, which are saved to disk.
@Observable
final class FilmStore {
    private(set) var bundled: [Film] = []
    private(set) var custom: [Film] = []
    private(set) var loadError: String?

    @ObservationIgnored private let customURL: URL

    static let defaultCustomURL = URL.documentsDirectory.appending(path: "custom-films.json")

    init(bundledData: Data?, customURL: URL = FilmStore.defaultCustomURL) {
        self.customURL = customURL
        do {
            if let bundledData {
                bundled = try JSONDecoder().decode([Film].self, from: bundledData)
            }
        } catch {
            loadError = String(localized: "Couldn't read the film database: \(error.localizedDescription)")
        }
        // A missing file just means no custom films yet.
        if let data = try? Data(contentsOf: customURL),
           let films = try? JSONDecoder().decode([Film].self, from: data) {
            custom = films.map { var f = $0; f.isCustom = true; return f }
        }
    }

    convenience init(bundle: Bundle = .main) {
        let data = bundle.url(forResource: "data", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        self.init(bundledData: data)
    }

    var all: [Film] { bundled + custom }

    func film(id: String) -> Film? { all.first { $0.id == id } }

    /// Brands with their films, both sorted alphabetically.
    func grouped(matching query: String = "") -> [(brand: String, films: [Film])] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = q.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.iso.map { String($0) == q } == true
        }
        return Dictionary(grouping: matches, by: \.brand)
            .map { (brand: $0.key, films: $0.value.sorted { $0.stock.localizedStandardCompare($1.stock) == .orderedAscending }) }
            .sorted { $0.brand.localizedCaseInsensitiveCompare($1.brand) == .orderedAscending }
    }

    func contains(brand: String, stock: String) -> Bool {
        all.contains { $0.brand.caseInsensitiveCompare(brand) == .orderedSame
            && $0.stock.caseInsensitiveCompare(stock) == .orderedSame }
    }

    func addCustom(_ film: Film) throws {
        var film = film
        film.isCustom = true
        custom.append(film)
        try saveCustom()
    }

    func deleteCustom(id: String) throws {
        custom.removeAll { $0.id == id }
        try saveCustom()
    }

    private func saveCustom() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(custom).write(to: customURL, options: .atomic)
    }
}
