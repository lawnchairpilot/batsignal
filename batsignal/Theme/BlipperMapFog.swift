import SwiftUI

// Fog rolling in off the water: the map stays clear where you're standing and
// thickens toward the edges, so what's near you reads as visible and what's far
// reads as guessed at. It also does the quiet job of pulling the eye back to
// the middle of the screen.
//
// Anchored to the screen rather than to the user's marker. The map is normally
// centred on you anyway, and a vignette that slid around under a pan would draw
// attention to itself — which is the opposite of what fog should do.
struct MapFogVignette: View {

    // Sits slightly above centre, matching where the eye naturally rests on a
    // screen whose bottom is taken up by the carousel.
    private let centerY: CGFloat = 0.46
    // The clear ellipse is wider than the map and about as tall, so the fog
    // closes in from the left and right later than it does from top and bottom.
    private let widthScale: CGFloat = 1.2
    // Tall enough that, once shifted up to centerY, the gradient still reaches
    // the bottom edge — a gradient draws nothing outside its own frame, and the
    // uncovered strip would read as a bright band under the fog.
    private let heightScale: CGFloat = 1.08

    var body: some View {
        GeometryReader { proxy in
            EllipticalGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .clear, location: 0.35),
                    .init(color: Color(hex: 0x16283A, opacity: 0.35), location: 0.65),
                    .init(color: Color(hex: 0x101C28, opacity: 0.75), location: 1.00),
                ],
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5
            )
            .frame(
                width: proxy.size.width * widthScale,
                height: proxy.size.height * heightScale
            )
            .position(
                x: proxy.size.width / 2,
                y: proxy.size.height * centerY
            )
        }
        // Decoration only — every pan, zoom and pin tap has to pass straight
        // through it to the map underneath.
        .allowsHitTesting(false)
    }
}
