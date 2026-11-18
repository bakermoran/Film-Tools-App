//
//  AddFilmView.swift
//  Reciprocity Failure Calculator
//

import SwiftUI

/// Form for adding a film that isn't in the bundled database.
struct AddFilmView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case power = "Formula"
        case table = "Table"
        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .power: "Formula"
            case .table: "Table"
            }
        }
    }

    struct PointInput: Identifiable {
        let id = UUID()
        var metered = ""
        var corrected = ""
    }

    @Environment(FilmStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSave: (Film) -> Void

    @State private var brand = ""
    @State private var stock = ""
    @State private var iso = ""
    @State private var type: FilmType = .blackAndWhite
    @State private var kind: Kind = .power
    @State private var exponent = ""
    @State private var threshold = "1"
    @State private var points = [PointInput(), PointInput()]
    @State private var notes = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Film") {
                    TextField("Brand", text: $brand)
                    TextField("Stock", text: $stock)
                    TextField("ISO (optional)", text: $iso).keyboardType(.numberPad)
                    Picker("Type", selection: $type) {
                        ForEach(FilmType.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Picker("Data", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch kind {
                    case .power:
                        LabeledContent("Exponent") {
                            TextField("1.31", text: $exponent).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Applies above (s)") {
                            TextField("1", text: $threshold).multilineTextAlignment(.trailing)
                        }
                    case .table:
                        ForEach($points) { $point in
                            HStack {
                                TextField("Metered s", text: $point.metered)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                TextField("Corrected s", text: $point.corrected)
                            }
                        }
                        .onDelete { points.remove(atOffsets: $0) }
                        Button("Add row", systemImage: "plus") { points.append(PointInput()) }
                    }
                } header: {
                    Text("Reciprocity data")
                } footer: {
                    Text(kind == .power
                         ? "Corrected = metered ^ exponent, the form Ilford publishes."
                         : "Times in seconds; 1/2 and 2m30s also work. Start with the longest time that needs no correction (same time on both sides), then add the manufacturer's rows.")
                }
                .keyboardType(.numbersAndPunctuation)

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }

                if let message = validationMessage {
                    Section { Text(message).foregroundStyle(.secondary).font(.footnote) }
                }
            }
            .navigationTitle("Add Film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(builtFilm == nil)
                }
            }
            .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var trimmedBrand: String { brand.trimmingCharacters(in: .whitespaces) }
    private var trimmedStock: String { stock.trimmingCharacters(in: .whitespaces) }

    private var model: ReciprocityModel? {
        switch kind {
        case .power:
            guard let e = Double(exponent.replacingOccurrences(of: ",", with: ".")), e >= 1, e < 3,
                  let t = ExposureFormat.parse(threshold)
            else { return nil }
            return .power(exponent: e, threshold: t)
        case .table:
            let parsed = points
                .filter { !$0.metered.isEmpty || !$0.corrected.isEmpty }
                .map { (ExposureFormat.parse($0.metered), ExposureFormat.parse($0.corrected)) }
            guard !parsed.isEmpty else { return nil }
            var result: [TablePoint] = []
            for case let (m?, c?) in parsed where c >= m { result.append(TablePoint(metered: m, corrected: c)) }
            guard result.count == parsed.count else { return nil }
            result.sort { $0.metered < $1.metered }
            // Metered times must be distinct, and corrected times must not go down.
            for (a, b) in zip(result, result.dropFirst()) where a.metered == b.metered || b.corrected < a.corrected {
                return nil
            }
            return .table(result)
        }
    }

    private var builtFilm: Film? {
        guard !trimmedBrand.isEmpty, !trimmedStock.isEmpty, let model,
              !store.contains(brand: trimmedBrand, stock: trimmedStock)
        else { return nil }
        let isoValue = Int(iso)
        guard iso.isEmpty || isoValue != nil else { return nil }
        let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return Film(brand: trimmedBrand, stock: trimmedStock, iso: isoValue, type: type,
                    model: model, notes: note.isEmpty ? nil : note, isCustom: true)
    }

    private var validationMessage: String? {
        if !trimmedBrand.isEmpty, !trimmedStock.isEmpty, store.contains(brand: trimmedBrand, stock: trimmedStock) {
            return String(localized: "\(trimmedBrand) \(trimmedStock) is already in the list.")
        }
        if !iso.isEmpty, Int(iso) == nil { return String(localized: "ISO should be a whole number.") }
        switch kind {
        case .power where !exponent.isEmpty && model == nil:
            return String(localized: "Exponent should be between 1 and 3, e.g. 1.31.")
        case .table where points.contains(where: { !$0.metered.isEmpty || !$0.corrected.isEmpty }) && model == nil:
            return String(localized: "Each row needs a metered and corrected time, corrected at least as long as metered, with no repeated metered times.")
        default:
            return nil
        }
    }

    private func save() {
        guard let film = builtFilm else { return }
        do {
            try store.addCustom(film)
            onSave(film)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    AddFilmView { _ in }
        .environment(FilmStore())
}
