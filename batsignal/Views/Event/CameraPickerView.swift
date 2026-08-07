import SwiftUI
import UIKit

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator

        // Circular guide showing how the shot will be cropped inside the
        // event preview circle. Non-interactive so the camera controls still work.
        let overlay = CameraCircleOverlayView(frame: UIScreen.main.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.contentMode = .redraw
        picker.cameraOverlayView = overlay

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// Dims the camera preview outside a centered circle and draws a white ring,
// previewing the crop used by the event's circular icon.
private final class CameraCircleOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        // Circle sits in the upper live-preview area, clear of the bottom controls.
        let radius = bounds.width * 0.4
        let center = CGPoint(x: bounds.midX, y: bounds.height * 0.38)
        // Only dim the preview region so the camera control bar stays legible.
        let dimRect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.78)

        let circlePath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )

        // Dim everything in the preview region except the circle.
        let maskPath = UIBezierPath(rect: dimRect)
        maskPath.append(circlePath)
        maskPath.usesEvenOddFillRule = true
        UIColor.black.withAlphaComponent(0.5).setFill()
        maskPath.fill()

        // White ring around the crop circle.
        circlePath.lineWidth = 3
        UIColor.white.setStroke()
        circlePath.stroke()
    }
}
