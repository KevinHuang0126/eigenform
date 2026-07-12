import AVFoundation
import SwiftUI
import UIKit

/// Pipes the live capture session into SwiftUI. Uses a UIView whose backing layer
/// is the preview layer itself, so it resizes with the view for free. Hands that
/// layer back to the `CameraManager` so its rotation coordinator can keep the
/// preview gravity-upright as the device rotates.
struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraManager

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.attach(previewLayer: view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
