import SwiftUI
import Combine
import FirebaseCore

// Fades text into the card's own background color at the trailing edge
// instead of truncating with "…". Only meant to be used as the fallback
// branch of a ViewThatFits, so it only ever renders when the text actually
// doesn't fit on one line.
extension View {
    func fadingTrailingEdge(background: Color) -> some View {
        overlay(alignment: .trailing) {
            LinearGradient(
                colors: [background.opacity(0), background],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }
}

// A single-line headline that renders in full when it fits, and only
// switches to the clipped/faded fallback once it genuinely overflows —
// so short titles never show a fade, and long ones never wrap or grow
// the card's height.
struct FadingHeadline: View {
    let text: String
    let background: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .font(.headline)
                .fixedSize(horizontal: true, vertical: false)
            Text(text)
                .font(.headline)
                .lineLimit(1)
                .fadingTrailingEdge(background: background)
        }
    }
}

struct EventCardView: View {
    let event: Event
    var creatorName: String?
    var isSelected: Bool = false

    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if event.isActive, let remaining = event.remainingFraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                        Rectangle()
                            .fill(remainingColor(remaining))
                            .frame(width: geometry.size.width * remaining)
                    }
                }
                .frame(height: 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let name = creatorName {
                    Text(name)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .bold()
                }
                FadingHeadline(text: event.activity, background: Color(.secondarySystemBackground))

                if !event.isActive {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(startTimeLabel)
                        if !event.durationLabel.isEmpty {
                            Text(Strings.Home.durationSuffix(event.durationLabel))
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.accentColor : Color.accentColor.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .onReceive(timer) { _ in now = Date() }
    }

    // Takes time remaining, so the thresholds run the opposite way from a
    // fill-up bar: the less that's left, the more urgent the color.
    private func remainingColor(_ remaining: Double) -> Color {
        if remaining < 0.25 { return .red }
        if remaining < 0.5 { return .orange }
        return .accentColor
    }

    private var startTimeLabel: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: event.startTime.dateValue())
        if Calendar.current.isDateInTomorrow(event.startTime.dateValue()) {
            return Strings.Home.tomorrowAt(time)
        }
        return time
    }
}

// Reusable circle icon: profile photo → emoji/initials label → person placeholder
struct EventIconView: View {
    var photoURL: String? = nil
    var label: String? = nil
    var size: CGFloat = 44

    private var isEmoji: Bool {
        label?.unicodeScalars.contains { $0.properties.isEmojiPresentation } ?? false
    }

    var body: some View {
        Group {
            if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallbackContent
                    }
                }
            } else {
                fallbackContent
            }
        }
        .frame(width: size, height: size)
        .background(Color.accentColor)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var fallbackContent: some View {
        if let label {
            Text(label)
                .font(isEmoji
                    ? .system(size: size * 0.45)
                    : .system(size: size * 0.3, weight: .bold))
                .foregroundStyle(.white)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}