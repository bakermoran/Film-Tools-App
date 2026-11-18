//
//  FlashView.swift
//  Reciprocity Failure Calculator
//

import SwiftUI

enum FlashMode: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case fill = "Fill flash"
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .manual: "Manual"
        case .fill: "Fill flash"
        }
    }
}

enum FlashSolve: String, CaseIterable, Identifiable {
    case distance = "Distance"
    case aperture = "Aperture"
    case power = "Power"
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .distance: "Distance"
        case .aperture: "Aperture"
        case .power: "Power"
        }
    }
}

struct FlashView: View {
    @AppStorage("flash.gn") private var gnInput = ""
    @AppStorage("flash.ratedISO") private var ratedISO = 100
    @AppStorage("flash.unit") private var unit = DistanceUnit.meters
    @AppStorage("flash.lowest") private var lowestThirds = -21
    @AppStorage("flash.thirdSteps") private var thirdSteps = true
    @AppStorage("flash.iso") private var isoInput = "400"
    @AppStorage("flash.mode") private var mode = FlashMode.manual
    @AppStorage("flash.solve") private var solve = FlashSolve.distance
    @AppStorage("flash.power") private var powerThirds = -6
    @AppStorage("flash.aperture") private var apertureThirds = 18
    @AppStorage("flash.distance") private var distanceInput = "3"
    @AppStorage("flash.sync") private var syncDenominator = 125
    @AppStorage("flash.fill") private var fill = FillLevel.natural
    @AppStorage("flash.metered") private var meteredThirds = 21
    @FocusState private var focused: Bool

    private var setup: FlashSetup? {
        FlashFormat.parse(gnInput).map {
            FlashSetup(guideNumber: $0, ratedISO: Double(ratedISO), lowestThirds: lowestThirds, thirdSteps: thirdSteps)
        }
    }
    private var iso: Double? { FlashFormat.parse(isoInput) }
    private var distance: Double? { FlashFormat.parse(distanceInput) }
    private var powerLevels: [Int] { FlashPower.levels(lowest: lowestThirds, thirdSteps: thirdSteps) }

    var body: some View {
        NavigationStack {
            Form {
                flashSection
                isoSection

                Picker("Mode", selection: $mode) {
                    ForEach(FlashMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let setup, let iso {
                    switch mode {
                    case .manual: ManualFlashSections(
                        setup: setup, iso: iso, unit: unit, distance: distance, levels: powerLevels, solve: $solve,
                        powerThirds: $powerThirds, apertureThirds: $apertureThirds, distanceField: distanceField)
                    case .fill: FillFlashSections(
                        setup: setup, iso: iso, unit: unit, distance: distance, fill: $fill,
                        syncDenominator: $syncDenominator, meteredThirds: $meteredThirds, distanceField: distanceField)
                    }
                } else {
                    Section {
                        Text(setup == nil ? "Enter your flash's guide number to get started." : "Enter a film ISO.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Flash")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
            .onChange(of: thirdSteps) { snapPower() }
            .onChange(of: lowestThirds) { snapPower() }
        }
    }

    // MARK: Inputs

    private var flashSection: some View {
        Section {
            HStack {
                Text("Guide number")
                TextField("e.g. 36", text: $gnInput)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .font(.body.monospacedDigit())
                Picker("Unit", selection: $unit) {
                    ForEach(DistanceUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Picker("Rated at", selection: $ratedISO) {
                ForEach([25, 50, 100, 200, 400], id: \.self) { Text("ISO \($0)").tag($0) }
            }
        } header: {
            Text("Your flash")
        } footer: {
            Text("The full-power guide number from your flash's specs, for the zoom setting you use. Most are rated at ISO 100.")
        }
    }

    private var isoSection: some View {
        Section("Film ISO") {
            TextField("ISO", text: $isoInput)
                .keyboardType(.numberPad)
                .focused($focused)
                .font(.title3.monospacedDigit())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(["50", "100", "160", "200", "400", "800", "1600", "3200"], id: \.self) { preset in
                        Button(preset) { isoInput = preset }
                            .buttonStyle(.bordered)
                            .tint(isoInput == preset ? .accentColor : .secondary)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func distanceField(_ label: LocalizedStringKey) -> some View {
        HStack {
            Text(label)
            TextField("Distance", text: $distanceInput)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .font(.body.monospacedDigit())
            Text(unit.rawValue).foregroundStyle(.secondary)
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Power steps", selection: $thirdSteps) {
                Text("Thirds of a stop").tag(true)
                Text("Whole stops").tag(false)
            }
            .pickerStyle(.menu)
            Picker("Lowest power", selection: $lowestThirds) {
                ForEach(FlashPower.lowestChoices, id: \.self) { Text(FlashPower.label($0)).tag($0) }
            }
            .pickerStyle(.menu)
        } label: {
            Label("Flash options", systemImage: "slider.horizontal.3")
        }
    }

    /// Keeps the chosen power on a setting the flash has.
    private func snapPower() {
        let step = thirdSteps ? 1 : 3
        powerThirds = max(lowestThirds, min(0, Int((Double(powerThirds) / Double(step)).rounded()) * step))
    }
}

// MARK: - Manual

private struct ManualFlashSections<DistanceField: View>: View {
    let setup: FlashSetup
    let iso: Double
    let unit: DistanceUnit
    let distance: Double?
    let levels: [Int]
    @Binding var solve: FlashSolve
    @Binding var powerThirds: Int
    @Binding var apertureThirds: Int
    let distanceField: (LocalizedStringKey) -> DistanceField

    private var fNumber: Double { Aperture.fNumber(apertureThirds) }

    var body: some View {
        Section {
            Picker("Solve for", selection: $solve) {
                ForEach(FlashSolve.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if solve != .power {
                Picker("Flash power", selection: $powerThirds) {
                    ForEach(levels, id: \.self) { Text(FlashPower.label($0)).tag($0) }
                }
            }
            if solve != .aperture {
                Picker("Aperture", selection: $apertureThirds) {
                    ForEach(Aperture.choices, id: \.self) { Text(Aperture.label($0)).tag($0) }
                }
            }
            if solve != .distance {
                distanceField("Subject distance")
            }
        }

        result

        Section {
            referenceTable
        } header: {
            Text(solve == .aperture
                 ? "Every power at \(distance.map { FlashFormat.distance($0, unit) } ?? "—")"
                 : "Every power at \(Aperture.label(apertureThirds))")
        }
    }

    @ViewBuilder private var result: some View {
        Section("Result") {
            switch solve {
            case .distance:
                ResultText(FlashFormat.distance(setup.distance(iso: iso, powerThirds: powerThirds, fNumber: fNumber), unit),
                           detail: "Subject distance at \(FlashPower.label(powerThirds)) power and \(Aperture.label(apertureThirds))")
            case .aperture:
                if let distance {
                    let exact = setup.fNumber(iso: iso, powerThirds: powerThirds, distance: distance)
                    let thirds = Aperture.nearest(to: exact)
                    ResultText(Aperture.label(thirds),
                               detail: "Exactly f/\(FlashFormat.number(exact)) at \(FlashPower.label(powerThirds)) power")
                    if thirds < Aperture.choices.first! || thirds > Aperture.choices.last! {
                        warning(thirds < Aperture.choices.first!
                                ? "Wider than your lens will open. Raise the power or move closer."
                                : "Smaller than your lens will stop down. Lower the power or move back.")
                    }
                } else {
                    Text("Enter a subject distance.").foregroundStyle(.secondary)
                }
            case .power:
                if let distance {
                    PowerResultView(result: setup.power(iso: iso, fNumber: fNumber, distance: distance),
                                    reach: setup.reach(iso: iso, fNumber: fNumber), unit: unit)
                } else {
                    Text("Enter a subject distance.").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Guide number at ISO \(FlashFormat.number(iso))",
                           value: FlashFormat.number(setup.guideNumber(iso: iso)) + " " + unit.rawValue)
                .font(.footnote)
        }
    }

    private var referenceTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Power"); Text(solve == .aperture ? "Aperture" : "Distance")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(levels.filter { $0 % 3 == 0 }, id: \.self) { level in
                GridRow {
                    Text(FlashPower.label(level))
                    if solve == .aperture {
                        Text(distance.map { Aperture.label(Aperture.nearest(to: setup.fNumber(iso: iso, powerThirds: level, distance: $0))) } ?? "—")
                    } else {
                        Text(FlashFormat.distance(setup.distance(iso: iso, powerThirds: level, fNumber: fNumber), unit))
                    }
                }
                .font(.subheadline.monospacedDigit())
                .fontWeight(level == powerThirds && solve != .power ? .semibold : .regular)
                .foregroundStyle(level == powerThirds && solve != .power ? Color.accentColor : .primary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Fill flash

private struct FillFlashSections<DistanceField: View>: View {
    let setup: FlashSetup
    let iso: Double
    let unit: DistanceUnit
    let distance: Double?
    @Binding var fill: FillLevel
    @Binding var syncDenominator: Int
    @Binding var meteredThirds: Int
    let distanceField: (LocalizedStringKey) -> DistanceField

    var body: some View {
        Section {
            distanceField("Subject distance")
            Picker("Flash sync speed", selection: $syncDenominator) {
                ForEach(DaylightCondition.syncSpeeds, id: \.self) { Text(verbatim: "1/\($0)").tag($0) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Flash vs. daylight (stops)")
                Picker("Fill amount", selection: $fill) {
                    ForEach(FillLevel.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Setup")
        } footer: {
            Text(fill.explanation)
        }

        if let distance {
            let exposures = DaylightCondition.all.map { $0.exposure(iso: iso, syncDenominator: syncDenominator) }
            Section {
                ForEach(DaylightCondition.all) { condition in
                    let exposure = condition.exposure(iso: iso, syncDenominator: syncDenominator)
                    FillRow(name: condition.name, symbol: condition.symbol, exposure: exposure,
                            result: power(exposure.apertureThirds, distance: distance),
                            reach: setup.reach(iso: iso, fNumber: Aperture.fNumber(exposure.apertureThirds), exposure: fill.stops),
                            unit: unit)
                }
            } header: {
                Text("Daylight · Sunny 16")
            } footer: {
                if exposures.contains(where: { $0.apertureThirds > Aperture.smallestCommon }) {
                    Text("Apertures past f/22 are smaller than most lenses go. Use an ND filter and open up one stop per stop of ND. The flash power stays the same.")
                }
            }

            Section {
                Picker("Metered at 1/\(syncDenominator)", selection: $meteredThirds) {
                    ForEach(Aperture.choices, id: \.self) { Text(Aperture.label($0)).tag($0) }
                }
                FillRow(name: "Flash power", symbol: "bolt", exposure: nil,
                        result: power(meteredThirds, distance: distance),
                        reach: setup.reach(iso: iso, fNumber: Aperture.fNumber(meteredThirds), exposure: fill.stops),
                        unit: unit)
            } header: {
                Text("From your meter")
            } footer: {
                Text("Meter the background at your sync speed, then set this aperture.")
            }
        } else {
            Section { Text("Enter a subject distance.").foregroundStyle(.secondary) }
        }
    }

    private func power(_ apertureThirds: Int, distance: Double) -> PowerResult {
        setup.power(iso: iso, fNumber: Aperture.fNumber(apertureThirds), distance: distance, exposure: fill.stops)
    }
}

private struct FillRow: View {
    let name: LocalizedStringResource
    let symbol: String
    let exposure: AmbientExposure?
    let result: PowerResult
    let reach: (near: Double, far: Double)
    let unit: DistanceUnit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let exposure {
                    HStack(spacing: 4) {
                        Text(Aperture.label(exposure.apertureThirds))
                            .foregroundStyle(exposure.apertureThirds > Aperture.smallestCommon ? .orange : .secondary)
                        Text("at \(exposure.shutterLabel)").foregroundStyle(.secondary)
                    }
                    .font(.subheadline.monospacedDigit())
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                switch result {
                case let .setting(thirds, _):
                    Text(FlashPower.label(thirds))
                        .font(.title3.weight(.semibold).monospacedDigit())
                case .beyondFull:
                    Text("Too far").font(.headline).foregroundStyle(.orange)
                    Text("Within \(FlashFormat.distance(reach.far, unit))").font(.caption).foregroundStyle(.secondary)
                case .belowLowest:
                    Text("Too close").font(.headline).foregroundStyle(.orange)
                    Text("Back to \(FlashFormat.distance(reach.near, unit))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Shared

private struct ResultText: View {
    let value: String
    let detail: LocalizedStringKey?

    init(_ value: String, detail: LocalizedStringKey? = nil) {
        self.value = value
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.default, value: value)
            if let detail {
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PowerResultView: View {
    let result: PowerResult
    let reach: (near: Double, far: Double)
    let unit: DistanceUnit

    var body: some View {
        switch result {
        case let .setting(thirds, offBy):
            ResultText(FlashPower.label(thirds), detail: abs(offBy) < 0.05
                       ? "Exact"
                       : offBy > 0
                       ? "\(FlashFormat.stops(offBy)) over, the nearest setting"
                       : "\(FlashFormat.stops(offBy)) under, the nearest setting")
        case let .beyondFull(stops):
            ResultText(String(localized: "Full power"))
            warning("Needs \(FlashFormat.stops(stops)) more than full power. Move within \(FlashFormat.distance(reach.far, unit)), open the aperture, or use faster film.")
        case let .belowLowest(stops):
            ResultText(String(localized: "Lowest power"))
            warning("Needs \(FlashFormat.stops(stops)) less than your lowest setting. Move back to \(FlashFormat.distance(reach.near, unit)) or stop down.")
        }
    }
}

private func warning(_ text: LocalizedStringKey) -> some View {
    Label(text, systemImage: "exclamationmark.triangle")
        .font(.footnote)
        .foregroundStyle(.orange)
}

#Preview {
    FlashView()
}
