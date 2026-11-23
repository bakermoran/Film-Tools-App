//
//  MeterView.swift
//  Reciprocity Failure Calculator
//

import SwiftUI

struct MeterView: View {
    @Environment(FilmStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("selectedFilmID") private var selectedFilmID = ""
    @AppStorage("meteredInput") private var reciprocityInput = ""
    @AppStorage("selectedTab") private var tab = "reciprocity"
    @AppStorage("meter.mode") private var mode = MeterMode.spot
    @AppStorage("meter.priority") private var priority = MeterPriority.aperture
    @AppStorage("meter.iso") private var iso = 400
    @AppStorage("meter.aperture") private var apertureThirds = 18
    @AppStorage("meter.shutter") private var shutterThirds = 21
    /// Calibration offsets, in thirds of a stop.
    @AppStorage("meter.calibration.spot") private var spotCalibration = 0
    @AppStorage("meter.calibration.incident") private var incidentCalibration = 0

    @State private var camera = LightMeterCamera()
    @State private var held: MeterReading?
    @State private var holdCountdown: Int?
    @State private var holdTask: Task<Void, Never>?
    @State private var spot: CGPoint?
    @State private var zoom = 1.0
    @State private var showingCalibration = false

    private var film: Film? { store.film(id: selectedFilmID) ?? store.all.first }
    private var calibration: Double { Double(mode == .spot ? spotCalibration : incidentCalibration) / 3 }
    private var reading: MeterReading? { held ?? camera.reading }
    /// Calibrated scene brightness at ISO 100.
    private var ev100: Double? { reading.map { $0.ev100 + calibration } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text(mode == .spot
                         ? "Tap to meter a different spot. The phone meters a small area around the circle. Zoom in to narrow it."
                         : "Cover the front camera with a white diffuser, like paper or half a ping-pong ball. Hold the phone at your subject with the screen facing where you'll shoot from, then tap Hold.")
                }

                notesSection
                settingsSection
                if let ev100 {
                    Section("Equivalent exposures at ISO \(iso)") {
                        PairsTable(ev: LightMeter.ev(ev100, iso: Double(iso)),
                                   highlight: priority == .aperture ? apertureThirds : nil)
                    }
                }
            }
            .navigationTitle("Meter")
            .safeAreaInset(edge: .bottom) {
                Picker("Mode", selection: $mode) {
                    ForEach(MeterMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCalibration = true } label: {
                        Label("Calibrate", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingCalibration) {
                MeterCalibrationView(mode: mode, camera: camera,
                                     spot: $spotCalibration, incident: $incidentCalibration)
            }
            .task(id: mode) {
                spot = nil
                zoom = 1
                await camera.start(mode.cameraPosition)
            }
            .onDisappear {
                cancelHoldCountdown()
                camera.stop()
            }
            .onChange(of: mode) {
                cancelHoldCountdown()
                held = nil
            }
            .sensoryFeedback(.success, trigger: held) { old, new in old == nil && new != nil }
        }
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        switch camera.status {
        case .denied:
            ContentUnavailableView {
                Label("Camera access is off", systemImage: "camera")
            } description: {
                Text("The meter reads light through the camera. Turn on camera access in Settings.")
            } actions: {
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
        case .unavailable:
            ContentUnavailableView("No camera", systemImage: "camera",
                                   description: Text("This device doesn't have a camera the meter can use."))
        case .idle, .starting, .running:
            GeometryReader { geo in
                ZStack {
                    CameraPreview(session: camera.session, device: camera.device) { viewPoint, devicePoint in
                        guard mode == .spot else { return }
                        spot = viewPoint
                        camera.meter(at: devicePoint)
                    }
                    if mode == .spot {
                        Reticle()
                            .position(spot ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                            .allowsHitTesting(false)
                    }
                    if let holdCountdown {
                        Text("\(holdCountdown)")
                            .font(.system(size: 96, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(radius: 8)
                            .allowsHitTesting(false)
                    }
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
                    // View coordinates no longer line up after a resize, so go back to the center.
                    guard spot != nil else { return }
                    spot = nil
                    camera.meter(at: CGPoint(x: 0.5, y: 0.5))
                }
            }
            .frame(height: 380)
            .background(.black)
            .overlay(alignment: .top) { readingCard }
            .overlay(alignment: .bottom) { previewControls }
            .environment(\.colorScheme, .dark)
        }
    }

    /// The answer, laid over the top of the camera image.
    private var readingCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if let result {
                    Text(result.value)
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(result.warnings.isEmpty ? Color.primary : .orange)
                        .contentTransition(.numericText())
                        .animation(.default, value: result.value)
                    Text(result.detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(camera.status == .running ? "Reading…" : "Starting the camera…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if held != nil {
                Image(systemName: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(12)
        .allowsHitTesting(false)
    }

    private var previewControls: some View {
        HStack {
            if mode == .spot {
                HStack(spacing: 4) {
                    ForEach(LightMeterCamera.zoomLevels, id: \.self) { level in
                        Button(String(format: "%g×", level)) {
                            zoom = level
                            camera.setZoom(level)
                        }
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .frame(width: 36, height: 36)
                        .background(zoom == level ? AnyShapeStyle(.yellow.opacity(0.9)) : AnyShapeStyle(.ultraThinMaterial),
                                    in: Circle())
                        .foregroundStyle(zoom == level ? .black : .primary)
                    }
                }
            }
            Spacer()
            Button(action: toggleHold) {
                Label(holdLabel, systemImage: held == nil ? "lock.open" : "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(held == nil ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.yellow.opacity(0.9)),
                                in: Capsule())
                    .foregroundStyle(held == nil ? .primary : Color.black)
            }
            .disabled(held == nil && camera.reading == nil)
        }
        .buttonStyle(.plain)
        .padding(12)
    }

    private var holdLabel: LocalizedStringKey {
        if held != nil { return "Release" }
        if holdCountdown != nil { return "Cancel" }
        return mode == .incident ? "Hold in 3 s" : "Hold"
    }

    /// Spot holds right away. Incident waits three seconds, since the screen faces away from you
    /// while you take the reading, and buzzes when it locks.
    private func toggleHold() {
        if held != nil {
            held = nil
        } else if holdCountdown != nil {
            cancelHoldCountdown()
        } else if mode == .spot {
            held = camera.reading
        } else {
            holdTask = Task {
                for second in [3, 2, 1] {
                    holdCountdown = second
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
                holdCountdown = nil
                held = camera.reading
            }
        }
    }

    private func cancelHoldCountdown() {
        holdTask?.cancel()
        holdTask = nil
        holdCountdown = nil
    }

    // MARK: Result

    private struct Result {
        var value: String
        var detail: String
        /// Set when the answer is a time of 1 s or longer, for the reciprocity handoff.
        var longExposure: Double?
        var warnings: [LocalizedStringKey]
    }

    private var result: Result? {
        guard let ev100, let reading else { return nil }
        let ev = LightMeter.ev(ev100, iso: Double(iso))
        var warnings: [LocalizedStringKey] = []
        var result: Result

        switch priority {
        case .aperture:
            let seconds = LightMeter.seconds(ev: ev, fNumber: Aperture.fNumber(apertureThirds))
            result = Result(value: MeterFormat.shutter(seconds),
                            detail: "\(Aperture.label(apertureThirds)) · ISO \(iso) · \(MeterFormat.ev(ev100))",
                            longExposure: seconds >= 1 ? seconds : nil, warnings: [])
            if seconds < Shutter.seconds(Shutter.fastest) * 0.9 {
                warnings.append("Faster than 1/8000. Stop down, use slower film, or add an ND filter.")
            }
        case .shutter:
            let thirds = Aperture.nearest(to: LightMeter.fNumber(ev: ev, seconds: Shutter.seconds(shutterThirds)))
            result = Result(value: Aperture.label(thirds),
                            detail: "\(Shutter.label(shutterThirds)) · ISO \(iso) · \(MeterFormat.ev(ev100))",
                            longExposure: nil, warnings: [])
            if thirds < Aperture.choices.first! {
                warnings.append("Wider than most lenses open. Use a slower shutter or faster film.")
            } else if thirds > Aperture.choices.last! {
                warnings.append("Smaller than most lenses stop down. Use a faster shutter or an ND filter.")
            }
        }

        switch reading.quality {
        case .good: break
        case .estimate:
            warnings.append("At the edge of what this camera can measure. Treat it as an estimate and bracket.")
        case .tooDark:
            warnings.append("Too dark for the camera to measure. The light is \(MeterFormat.ev(ev100)) or darker, so expose at least this long and bracket longer.")
        case .tooBright:
            warnings.append("Too bright for the camera to measure. The light is \(MeterFormat.ev(ev100)) or brighter.")
        }
        result.warnings = warnings
        return result
    }

    /// Warnings and the reciprocity handoff, when there are any.
    @ViewBuilder private var notesSection: some View {
        if let result, !result.warnings.isEmpty || result.longExposure != nil {
            Section {
                ForEach(result.warnings.indices, id: \.self) { warning(result.warnings[$0]) }
                if let seconds = result.longExposure {
                    Button {
                        reciprocityInput = MeterFormat.reciprocityInput(seconds)
                        tab = "reciprocity"
                    } label: {
                        Label("Correct for reciprocity failure", systemImage: "hourglass")
                    }
                }
            }
        }
    }

    // MARK: Settings

    private var isoChoices: [Int] {
        Set(LightMeter.isoChoices + [iso] + (film?.iso.map { [$0] } ?? [])).sorted()
    }

    private var settingsSection: some View {
        Section("Exposure") {
            Picker("Film ISO", selection: $iso) {
                ForEach(isoChoices, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
            if let film, let filmISO = film.iso, filmISO != iso {
                Button("Use \(film.name) at ISO \(filmISO)") { iso = filmISO }
            }
            Picker("Priority", selection: $priority) {
                ForEach(MeterPriority.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            switch priority {
            case .aperture:
                Picker("Aperture", selection: $apertureThirds) {
                    ForEach(Aperture.choices, id: \.self) { Text(Aperture.label($0)).tag($0) }
                }
            case .shutter:
                Picker("Shutter", selection: $shutterThirds) {
                    ForEach(Shutter.choices.reversed(), id: \.self) { Text(Shutter.label($0)).tag($0) }
                }
            }
        }
    }
}

// MARK: - Pieces

private struct Reticle: View {
    var body: some View {
        ZStack {
            Circle().stroke(.yellow, lineWidth: 2)
            Circle().fill(.yellow).frame(width: 4, height: 4)
        }
        .frame(width: 44, height: 44)
        .shadow(color: .black.opacity(0.5), radius: 2)
    }
}

private struct PairsTable: View {
    let ev: Double
    let highlight: Int?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Aperture"); Text("Shutter")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(LightMeter.pairApertures, id: \.self) { thirds in
                let seconds = LightMeter.seconds(ev: ev, fNumber: Aperture.fNumber(thirds))
                let tooFast = seconds < Shutter.seconds(Shutter.fastest) * 0.9
                GridRow {
                    Text(Aperture.label(thirds))
                    Text(MeterFormat.shutter(seconds))
                        .foregroundStyle(tooFast ? .orange : .primary)
                }
                .font(.subheadline.monospacedDigit())
                .fontWeight(thirds == highlight ? .semibold : .regular)
                .foregroundStyle(thirds == highlight ? Color.accentColor : .primary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Calibration

private struct MeterCalibrationView: View {
    let mode: MeterMode
    let camera: LightMeterCamera
    @Binding var spot: Int
    @Binding var incident: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let reading = camera.reading {
                        let offset = Double(mode == .spot ? spot : incident) / 3
                        LabeledContent("\(Text(mode.label)) reads now", value: MeterFormat.ev(reading.ev100 + offset))
                            .monospacedDigit()
                    }
                } footer: {
                    Text("Meter the same evenly lit surface with this phone and a handheld meter, then adjust until the readings match. EV here is at ISO 100.")
                }
                Section {
                    stepper("Spot", value: $spot)
                } footer: {
                    Text("If the phone reads EV 12 and your meter reads EV 11⅔, set −⅓.")
                }
                Section {
                    stepper("Incident", value: $incident)
                } footer: {
                    Text("Every diffuser passes a different amount of light, so calibrate with the one you use.")
                }
                Section {
                    Button("Reset", role: .destructive) {
                        spot = 0
                        incident = 0
                    }
                }
            }
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stepper(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        Stepper(value: value, in: -9...9) {
            LabeledContent(title, value: value.wrappedValue == 0
                           ? String(localized: "None")
                           : MeterFormat.thirds(Double(value.wrappedValue) / 3, signed: true) + " EV")
                .monospacedDigit()
        }
    }
}

#Preview {
    MeterView()
        .environment(FilmStore())
}
