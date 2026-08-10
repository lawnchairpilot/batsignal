import UIKit

extension UIImage {
    // Bakes imageOrientation into the pixels so the CGImage matches what the
    // user saw, leaving crop rects in the same coordinate space as the preview.
    // Anything that hands a rect to CGImage.cropping(to:) needs this first — a
    // photo taken in portrait is stored sideways.
    func uprightCopy() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
