//
//  CameraPreview.swift
//  Reciprocity Failure Calculator
//

import AVFoundation
import SwiftUI

/// The live camera image. Taps report the point in both view and device coordinates.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    var onTap: ((_ viewPoint: CGPoint, _ devicePoint: CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onTap = onTap
        view.attach(device)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onTap: ((CGPoint, CGPoint) -> Void)?

    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        onTap?(point, previewLayer.captureDevicePointConverted(fromLayerPoint: point))
    }

    /// Keeps the preview upright for `device` as the phone rotates.
    func attach(_ device: AVCaptureDevice?) {
        guard rotation?.device != device else { return }
        observation = nil
        rotation = nil
        guard let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        apply(coordinator.videoRotationAngleForHorizonLevelPreview)
        observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async { self?.apply(angle) }
        }
    }

    private func apply(_ angle: CGFloat) {
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
