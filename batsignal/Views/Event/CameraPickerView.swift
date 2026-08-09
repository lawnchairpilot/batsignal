import SwiftUI
import UIKit

// The guide circle's diameter as a fraction of the camera preview's width.
// Shared by the overlay that draws the circle and the crop that's applied to
// the captured photo, so the guide can't drift out of sync with the result.
private let guideDiameterFraction: CGFloat = 0.8

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
            // Crop here rather than handing back the whole frame: everything
            // downstream (the preview circle, the map pin, the event card)
            // scaledToFill()s into a circle, which center-crops. Keeping the
            // full frame meant the guide circle was decorative and the visible
            // result was whatever happened to be in the middle of the shot.
            parent.image = (info[.originalImage] as? UIImage).map(croppedToGuide)
            parent.dismiss()
        }

        // Cuts the square the guide circle is inscribed in. The circle is
        // centered on the preview and sized off its width, and a camera preview
        // is width-matched to the screen whether it fills or letterboxes, so the
        // same fraction of the image's shorter side is the matching region.
        private func croppedToGuide(_ image: UIImage) -> UIImage {
            // cropping(to:) works on the raw sensor buffer, which is sideways
            // for a photo taken in portrait — redraw first so the pixels are
            // laid out the way the image is actually displayed.
            let upright = image.uprightCopy()
            guard let cgImage = upright.cgImage else { return upright }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let side = min(width, height) * guideDiameterFraction
            let cropRect = CGRect(
                x: (width - side) / 2,
                y: (height - side) / 2,
                width: side,
                height: side
            ).integral

            guard let cropped = cgImage.cropping(to: cropRect) else { return upright }
            return UIImage(cgImage: cropped, scale: upright.scale, orientation: .up)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private extension UIImage {
    // Bakes imageOrientation into the pixels so the CGImage matches what the
    // user saw, leaving crop rects in the same coordinate space as the preview.
    func uprightCopy() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
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
        // Centered on the preview, because the crop is taken from the middle of
        // the frame. Sitting higher up made the guide point at a region the
        // captured photo never kept.
        let radius = bounds.width * guideDiameterFraction / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
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
