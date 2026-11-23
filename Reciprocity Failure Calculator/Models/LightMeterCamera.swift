//
//  LightMeterCamera.swift
//  Reciprocity Failure Calculator
//
//  Reads scene brightness from the camera's auto exposure. The camera picks a shutter
//  time and ISO that render the metered area as a mid-tone; with the lens aperture that
//  gives the EV. When the camera runs out of range, `exposureTargetOffset` says how many
//  stops off the image is, which extends the reading a few stops into the dark.
//

@preconcurrency import AVFoundation
import Observation

struct MeterReading: Equatable {
    enum Quality {
        case good
        /// At the edge of the camera's range. Usable but less reliable.
        case estimate
        /// Darker than the camera can measure. The light is at most `ev100`.
        case tooDark
        /// Brighter than the camera can measure. The light is at least `ev100`.
        case tooBright
    }

    var ev100: Double
    var quality: Quality
}

extension MeterMode {
    var cameraPosition: AVCaptureDevice.Position { self == .spot ? .back : .front }
}

@MainActor
@Observable
final class LightMeterCamera {
    enum Status { case idle, starting, running, denied, unavailable }

    private(set) var status = Status.idle
    private(set) var reading: MeterReading?
    private(set) var device: AVCaptureDevice?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "LightMeterCamera.session")
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var smoothed: Double?
    @ObservationIgnored private var wanted: AVCaptureDevice.Position?

    static let zoomLevels: [Double] = [1, 2, 4]

    func start(_ position: AVCaptureDevice.Position) async {
        wanted = position
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { status = .denied; return }
        default:
            status = .denied
            return
        }
        // Stopped or switched cameras while waiting for permission.
        guard wanted == position else { return }

        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: newDevice)
        else {
            status = .unavailable
            return
        }

        status = .starting
        pollTask?.cancel()
        let session = session
        await withCheckedContinuation { continuation in
            queue.async {
                session.beginConfiguration()
                session.inputs.forEach(session.removeInput)
                if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                if session.canAddInput(input) { session.addInput(input) }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        guard wanted == position else { return }

        // Adding the input resets the format, so configure exposure afterwards.
        configure(newDevice)
        device = newDevice
        smoothed = nil
        reading = nil
        status = .running
        startPolling()
    }

    func stop() {
        wanted = nil
        pollTask?.cancel()
        pollTask = nil
        let session = session
        queue.async { session.stopRunning() }
        if status == .running || status == .starting { status = .idle }
    }

    /// Meters around `point`, in device coordinates (0–1, unrotated sensor).
    func meter(at point: CGPoint) {
        guard let device else { return }
        withLock(device) {
            if $0.isExposurePointOfInterestSupported { $0.exposurePointOfInterest = point }
            // Setting the mode again makes the new point take effect.
            if $0.isExposureModeSupported(.continuousAutoExposure) { $0.exposureMode = .continuousAutoExposure }
        }
    }

    func setZoom(_ factor: Double) {
        guard let device else { return }
        withLock(device) {
            $0.videoZoomFactor = min(max(1, factor), $0.activeFormat.videoMaxZoomFactor)
        }
    }

    // MARK: Private

    private func configure(_ device: AVCaptureDevice) {
        withLock(device) { device in
            device.videoZoomFactor = 1
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.setExposureTargetBias(0)
            // Let auto exposure use the longest shutter the format allows, so the meter reaches
            // further into the dark. The preview's frame rate drops in low light as a result.
            device.activeMaxExposureDuration = device.activeFormat.maxExposureDuration
            // Both of these brighten the image without showing up in the exposure settings.
            if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = false }
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = false
            }
        }
    }

    private func withLock(_ device: AVCaptureDevice, _ body: (AVCaptureDevice) -> Void) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        body(device)
        device.unlockForConfiguration()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func sample() {
        guard let device else { return }
        let seconds = device.exposureDuration.seconds
        let iso = Double(device.iso)
        let aperture = Double(device.lensAperture)
        let offset = Double(device.exposureTargetOffset)
        guard seconds > 0, iso > 0, aperture > 0, offset.isFinite else { return }

        // A negative offset means the image is darker than the camera wanted, so the scene is
        // that many stops darker than the settings alone suggest.
        let raw = LightMeter.ev100(fNumber: aperture, seconds: seconds, iso: iso) + offset

        // Smooth out frame-to-frame jitter, but jump straight to big changes.
        if let previous = smoothed, abs(raw - previous) < 1 {
            smoothed = previous + (raw - previous) * 0.25
        } else {
            smoothed = raw
        }

        let format = device.activeFormat
        let maxSeconds = device.activeMaxExposureDuration.isValid
            ? device.activeMaxExposureDuration.seconds : format.maxExposureDuration.seconds
        let atLongest = seconds >= maxSeconds * 0.9 && iso >= Double(format.maxISO) * 0.9
        let atShortest = seconds <= format.minExposureDuration.seconds * 1.1 && iso <= Double(format.minISO) * 1.1

        let quality: MeterReading.Quality
        if atLongest, offset < -3 {
            quality = .tooDark
        } else if atShortest, offset > 3 {
            quality = .tooBright
        } else if (atLongest && offset < -0.5) || (atShortest && offset > 0.5) {
            quality = .estimate
        } else {
            quality = .good
        }

        reading = MeterReading(ev100: smoothed ?? raw, quality: quality)
    }
}
