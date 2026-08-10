import SwiftUI

// Pinch-and-drag crop against a circular guide, so a photo can be framed the
// way it will actually be shown — every avatar in the app is a circle. Written
// against any UIImage rather than the profile flow specifically; the event
// photo picker could use it too.
struct CircleCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    // Live gesture values. The `prior` pair is where the last gesture left
    // off, since a pinch reports its magnification relative to its own start.
    @State private var zoom: CGFloat = 1
    @State private var priorZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var priorOffset: CGSize = .zero

    private let maxZoom: CGFloat = 6

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let diameter = cropDiameter(in: proxy.size)
                let display = displaySize(for: diameter)

                // Everything hangs off a base that fills the space the reader
                // was given, so the guide circle sits in the middle of the
                // view. As a plain stack it would instead take the photo's
                // size — larger than the screen — and centre on that.
                Color.black
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: display.width, height: display.height)
                            .offset(offset)
                    }
                    // Everything outside the circle, dimmed.
                    .overlay {
                        Rectangle()
                            .fill(.black.opacity(0.55))
                            .mask {
                                Rectangle()
                                    .overlay {
                                        Circle()
                                            .frame(width: diameter, height: diameter)
                                            .blendMode(.destinationOut)
                                    }
                                    .compositingGroup()
                            }
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            .frame(width: diameter, height: diameter)
                    }
                    .clipped()
                    // Drags that start on the dimmed area count too.
                    .contentShape(Rectangle())
                    .gesture(dragGesture(diameter: diameter).simultaneously(with: magnifyGesture(diameter: diameter)))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(Strings.Common.cancel) { onCancel() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Strings.Profile.choosePhoto) { onConfirm(cropped(diameter: diameter)) }
                        }
                    }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(Strings.Profile.cropTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Layout

    private func cropDiameter(in size: CGSize) -> CGFloat {
        max(min(size.width, size.height) - 48, 120)
    }

    // How big the photo is drawn on screen: scaled up until its short side
    // covers the circle, then multiplied by whatever the pinch has added.
    private func displaySize(for diameter: CGFloat) -> CGSize {
        let fill = diameter / min(image.size.width, image.size.height)
        return CGSize(
            width: image.size.width * fill * zoom,
            height: image.size.height * fill * zoom
        )
    }

    // MARK: - Gestures

    private func dragGesture(diameter: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(
                        width: priorOffset.width + value.translation.width,
                        height: priorOffset.height + value.translation.height
                    ),
                    diameter: diameter
                )
            }
            .onEnded { _ in priorOffset = offset }
    }

    private func magnifyGesture(diameter: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(priorZoom * value.magnification, 1), maxZoom)
                // Zooming back out can leave the photo off-centre enough to
                // uncover an edge of the circle, so re-clamp as it shrinks.
                offset = clamped(offset, diameter: diameter)
            }
            .onEnded { _ in
                priorZoom = zoom
                priorOffset = offset
            }
    }

    // Keeps the circle covered: the photo can never be dragged past the point
    // where its edge crosses into the crop.
    private func clamped(_ proposed: CGSize, diameter: CGFloat) -> CGSize {
        let display = displaySize(for: diameter)
        let limitX = max((display.width - diameter) / 2, 0)
        let limitY = max((display.height - diameter) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    // MARK: - Cropping

    // Cuts the square the guide circle is inscribed in — downstream avatars all
    // scaledToFill() into a circle, so a square is what they want. The on-screen
    // geometry maps straight onto the source pixels: same centre, same offsets,
    // scaled by however much bigger the source is than its drawn size.
    private func cropped(diameter: CGFloat) -> UIImage {
        let upright = image.uprightCopy()
        guard let source = upright.cgImage else { return upright }

        let display = displaySize(for: diameter)
        let toPixels = CGFloat(source.width) / display.width
        let rect = CGRect(
            x: (display.width / 2 - offset.width - diameter / 2) * toPixels,
            y: (display.height / 2 - offset.height - diameter / 2) * toPixels,
            width: diameter * toPixels,
            height: diameter * toPixels
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))

        guard !rect.isNull, let cut = source.cropping(to: rect) else { return upright }
        return UIImage(cgImage: cut, scale: upright.scale, orientation: .up)
    }
}
