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
                .font(.blipperUI(.headline, weight: 600))
                .fixedSize(horizontal: true, vertical: false)
            Text(text)
                .font(.blipperUI(.headline, weight: 600))
                .lineLimit(1)
                .fadingTrailingEdge(background: background)
        }
    }
}

struct EventCardView: View {
    let event: Event
    @Binding var isExpanded: Bool
    var creatorName: String?
    var isSelected: Bool = false
    // Ceiling on the expanded card, for hosts with only so much room to give it
    // (the carousel sits over a fixed-height map). nil lets it size naturally.
    var expandedMaxContentHeight: CGFloat?
    // Answers whether a tap on the collapsed card should expand it. The
    // upcoming-events list spends the first tap pointing the map at the event
    // instead, so it says no until the card is already the focused one.
    var onCompactTap: () -> Bool

    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(
        event: Event,
        isExpanded: Binding<Bool>,
        creatorName: String? = nil,
        isSelected: Bool = false,
        expandedMaxContentHeight: CGFloat? = nil,
        onCompactTap: @escaping () -> Bool = { true }
    ) {
        self.event = event
        self._isExpanded = isExpanded
        self.creatorName = creatorName
        self.isSelected = isSelected
        self.expandedMaxContentHeight = expandedMaxContentHeight
        self.onCompactTap = onCompactTap
    }

    var body: some View {
        if isExpanded {
            ExpandedEventCardView(
                event: event,
                creatorName: creatorName,
                maxContentHeight: expandedMaxContentHeight,
                onCollapse: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false } }
            )
        } else {
            compactCard
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if event.isActive, let remaining = event.remainingFraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Blipper.track)
                        Rectangle()
                            .fill(Blipper.amber)
                            .frame(width: geometry.size.width * remaining)
                    }
                }
                .frame(height: 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let name = creatorName {
                    Text(name)
                        .font(.blipperUI(.caption1, weight: 600))
                        .foregroundColor(.accentColor)
                }
                FadingHeadline(text: event.activity, background: Blipper.surface)

                if !event.isActive {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(startTimeLabel)
                        if !event.durationLabel.isEmpty {
                            Text(Strings.Home.durationSuffix(event.durationLabel))
                        }
                    }
                    .font(.blipperUI(.subheadline))
                    .foregroundColor(Blipper.textMuted)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Blipper.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.accentColor : Color.accentColor.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .onReceive(timer) { _ in now = Date() }
        .contentShape(Rectangle())
        .onTapGesture {
            guard onCompactTap() else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
        }
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

// How loudly an icon should announce itself. The two differ only in color, so
// the fill and whatever sits on top of it stay in step — an amber fill needs
// dark content on it, a swell blue fill needs light.
struct EventIconStyle {
    let fill: Color
    let content: Color

    /// A person: list avatars, the joined stack, the profile photo. Amber on
    /// the ring alone, so it doesn't compete with an actual signal.
    static let avatar = EventIconStyle(fill: Blipper.swellBlue, content: Blipper.textPrimary)
    /// A signal: the map pin, and the icon being built in the create/edit
    /// flow. Filled amber so it carries across a map at a glance.
    static let signal = EventIconStyle(fill: Blipper.amber, content: Blipper.onAmber)
}

// Reusable circle icon: profile photo → emoji/initials label → person placeholder
struct EventIconView: View {
    var photoURL: String? = nil
    var label: String? = nil
    var size: CGFloat = 44
    var style: EventIconStyle = .avatar

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
        .background(style.fill)
        .clipShape(Circle())
        // strokeBorder rather than stroke so the ring sits fully inside the
        // circle and leaves the boundary free for the separator ring the avatar
        // stack draws over the top of it. On the signal style it lands amber on
        // amber and simply reads as a clean edge.
        .overlay(Circle().strokeBorder(Blipper.amber, lineWidth: ringWidth))
    }

    // Scaled off the icon so a 26pt avatar isn't ringed like a 140pt one, but
    // capped at both ends: any thinner disappears, any thicker eats the photo.
    private var ringWidth: CGFloat {
        min(max(size * 0.05, 1.5), 3)
    }

    @ViewBuilder
    private var fallbackContent: some View {
        if let label {
            Text(label)
                .font(isEmoji
                    ? .system(size: size * 0.45)
                    : .system(size: size * 0.3, weight: .bold))
                .foregroundStyle(style.content)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(style.content.opacity(0.8))
        }
    }
}