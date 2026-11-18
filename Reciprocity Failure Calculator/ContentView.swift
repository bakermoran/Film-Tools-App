//
//  ContentView.swift
//  Reciprocity Failure Calculator
//
//  Created by Baker Moran on 2/10/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(FilmStore.self) private var store
    @AppStorage("selectedFilmID") private var selectedFilmID = ""
    @AppStorage("meteredInput") private var meteredInput = ""
    @State private var timerSeconds: TimerDuration?
    @FocusState private var inputFocused: Bool

    private var film: Film? { store.film(id: selectedFilmID) ?? store.all.first }
    private var metered: Double? { ExposureFormat.parse(meteredInput) }

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.loadError {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }

                Section("Film") {
                    NavigationLink {
                        FilmPickerView(selectedFilmID: $selectedFilmID)
                    } label: {
                        if let film {
                            FilmRow(film: film)
                        } else {
                            Text("Choose a film").foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    TextField("e.g. 30, 1/2, 2m30s, 4:00", text: $meteredInput)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($inputFocused)
                        .submitLabel(.done)
                        .font(.title3.monospacedDigit())
                    presetRow
                } header: {
                    Text("Metered exposure")
                } footer: {
                    if !meteredInput.isEmpty, metered == nil {
                        Text("Couldn't read that time. Try 30, 1/2, 2m30s or 4:00.")
                            .foregroundStyle(.red)
                    }
                }

                if let film, let metered {
                    ResultSection(film: film, result: film.model.result(forMetered: metered)) {
                        inputFocused = false
                        timerSeconds = TimerDuration(seconds: $0)
                    }
                }

                if let film {
                    Section("Quick reference") {
                        ReferenceTable(model: film.model)
                    }
                    FilmDetailsSection(film: film)
                }
            }
            .navigationTitle("Reciprocity")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                }
            }
            .sheet(item: $timerSeconds) { duration in
                ExposureTimerView(duration: duration.seconds, filmName: film?.name ?? "")
            }
        }
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(["1", "2", "4", "8", "15", "30", "1m", "2m", "4m", "8m"], id: \.self) { preset in
                    Button(preset.hasSuffix("m") ? preset : preset + "s") { meteredInput = preset }
                        .buttonStyle(.bordered)
                        .tint(meteredInput == preset ? .accentColor : .secondary)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

struct TimerDuration: Identifiable {
    let seconds: Double
    var id: Double { seconds }
}

// MARK: - Result

private struct ResultSection: View {
    let film: Film
    let result: ReciprocityResult
    let startTimer: (Double) -> Void

    var body: some View {
        Section("Corrected exposure") {
            VStack(alignment: .leading, spacing: 6) {
                Text(ExposureFormat.string(fromSeconds: result.corrected))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.default, value: result.corrected)
                Text(result.needsCorrection
                     ? "\(ExposureFormat.stops(result.extraStops)) over the metered \(ExposureFormat.string(fromSeconds: result.metered))"
                     : "No correction needed below \(ExposureFormat.string(fromSeconds: film.model.correctionStartsAt))")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if result.isExtrapolated {
                Label("Beyond the manufacturer's data. This is an estimate, so bracket your exposures.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if result.corrected >= 1 {
                Button {
                    startTimer(result.corrected.rounded())
                } label: {
                    Label("Start \(ExposureFormat.clock(fromSeconds: result.corrected)) timer", systemImage: "timer")
                }
            }
        }
    }
}

// MARK: - Reference table

private struct ReferenceTable: View {
    let model: ReciprocityModel
    private let times: [Double] = [1, 2, 4, 8, 15, 30, 60, 120, 240, 480]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Metered"); Text("Corrected"); Text("Extra")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(times, id: \.self) { t in
                let r = model.result(forMetered: t)
                GridRow {
                    Text(ExposureFormat.string(fromSeconds: t))
                    Text(ExposureFormat.string(fromSeconds: r.corrected))
                        .foregroundStyle(r.isExtrapolated ? .orange : .primary)
                    Text(r.needsCorrection ? ExposureFormat.stops(r.extraStops) : "—")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Film details

private struct FilmDetailsSection: View {
    let film: Film

    var body: some View {
        Section("About \(film.name)") {
            if let type = film.type {
                LabeledContent("Type", value: type.label)
            }
            if let iso = film.iso {
                LabeledContent("ISO", value: "\(iso)")
            }
            switch film.model {
            case let .power(exponent, threshold):
                LabeledContent("Formula", value: "t^\(exponent.formatted())")
                LabeledContent("Applies above", value: ExposureFormat.string(fromSeconds: threshold))
            case let .table(points):
                LabeledContent("Data", value: String(localized: "\(points.count)-point table"))
                LabeledContent("Correction from", value: ExposureFormat.string(fromSeconds: points.first?.metered ?? 0))
            }
            if let notes = film.notes {
                Text(notes).font(.footnote).foregroundStyle(.secondary)
            }
            if let source = film.source {
                Link(destination: source) {
                    Label("Manufacturer data sheet", systemImage: "doc.text")
                }
            }
        }
    }
}

struct FilmRow: View {
    let film: Film

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(film.name)
            HStack(spacing: 6) {
                if let iso = film.iso { Text("ISO \(iso)") }
                if let type = film.type { Text(type.label) }
                if film.isCustom { Text("Custom") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environment(FilmStore())
}
