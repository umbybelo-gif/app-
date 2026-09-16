import AVFoundation
import SwiftUI
import UIKit

/// Ponte fra il layer di anteprima di AVFoundation e SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.backgroundColor = .black
        view.attach(controller.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}
}

final class PreviewHostView: UIView {
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        guard previewLayer !== layer else { return }
        layer.removeFromSuperlayer()
        self.layer.addSublayer(layer)
        previewLayer = layer
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Senza disattivare le animazioni implicite il layer "scivola" a ogni rotazione.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

/// Griglia dei terzi.
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...2 {
                    let x = geo.size.width / 3 * CGFloat(i)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    let y = geo.size.height / 3 * CGFloat(i)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Quadratino di messa a fuoco che appare dove tocchi.
struct FocusIndicator: View {
    let point: CGPoint

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 78, height: 78)
            .position(point)
            .allowsHitTesting(false)
    }
}
