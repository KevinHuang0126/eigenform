import AVFoundation
import Combine

/// Owns the capture session. All session configuration and start/stop happens on a
/// private serial queue so the main thread never blocks on camera hardware; frames
/// are delivered on a separate output queue via `sampleHandler`.
final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    /// Called on `videoOutputQueue` for every captured frame.
    var sampleHandler: ((CMSampleBuffer) -> Void)?

    @Published private(set) var permissionDenied = false
    @Published private(set) var position: AVCaptureDevice.Position = .front

    private let sessionQueue = DispatchQueue(label: "eigenform.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "eigenform.camera.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var configured = false

    // Rotation tracking. `RotationCoordinator` (iOS 17+) watches the physical device
    // orientation and publishes the angles that keep both the Vision buffers and the
    // on-screen preview gravity-upright — so the pipeline behaves identically in
    // portrait and landscape, and buffers arrive wide when the phone is held sideways.
    // These properties are only touched on the main queue.
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var captureAngleObservation: NSKeyValueObservation?
    private var previewAngleObservation: NSKeyValueObservation?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startConfigured()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.startConfigured()
                } else {
                    DispatchQueue.main.async { self.permissionDenied = true }
                }
            }
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func flipCamera() {
        let newPosition: AVCaptureDevice.Position = position == .front ? .back : .front
        sessionQueue.async { [self] in
            configure(position: newPosition)
        }
        position = newPosition
    }

    /// Called from the SwiftUI preview view (main queue) once its backing layer exists,
    /// so the rotation coordinator can compute the preview angle against it.
    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        rebuildRotationCoordinator()
    }

    private func startConfigured() {
        sessionQueue.async { [self] in
            if !configured {
                configure(position: .front)
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    /// Must be called on `sessionQueue`.
    private func configure(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
            configured = true
        }

        session.sessionPreset = .hd1280x720

        for input in session.inputs { session.removeInput(input) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        if !session.outputs.contains(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            guard session.canAddOutput(videoOutput) else { return }
            session.addOutput(videoOutput)
        }

        // Hand the new device to the main queue so the rotation coordinator can track
        // it. The coordinator (not a fixed angle) now drives buffer/preview rotation.
        DispatchQueue.main.async { [self] in
            videoDevice = device
            rebuildRotationCoordinator()
        }
    }

    /// Main queue only. Rebuilds the coordinator whenever the device or preview layer
    /// changes; reassigning the observations invalidates the previous ones.
    private func rebuildRotationCoordinator() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let device = videoDevice, let previewLayer else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        captureAngleObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            self?.applyCaptureRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        }
        previewAngleObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            self?.applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        }
    }

    private func applyCaptureRotation(_ angle: CGFloat) {
        sessionQueue.async { [self] in
            guard let connection = videoOutput.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        sampleHandler?(sampleBuffer)
    }
}
