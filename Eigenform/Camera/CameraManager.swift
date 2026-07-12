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

        // Rotate buffers to upright portrait so Vision can be handed .up frames and
        // every downstream coordinate assumption holds regardless of sensor mounting.
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        sampleHandler?(sampleBuffer)
    }
}
