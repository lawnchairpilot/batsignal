import SwiftUI

// A segmented control built out of plain SwiftUI buttons rather than a Picker
// with `.pickerStyle(.segmented)`.
//
// The stock segmented picker writes its selection on touch-up, and drops that
// write if the view re-evaluates between touch-down and touch-up. Inside a List
// row that happens routinely — an onAppear listener delivering its first
// snapshot, or an AsyncImage elsewhere in the list resolving, is enough — and
// the tap is silently lost. Buttons go through SwiftUI's own gesture handling
// and survive the same invalidation, which is why the add button sitting beside
// the picker on the profile screen never had the problem.
struct BlipperSegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }

    init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }
}

struct BlipperSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [BlipperSegment<Value>]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Blipper.track)
        )
    }

    private func segmentButton(_ segment: BlipperSegment<Value>) -> some View {
        let isSelected = segment.value == selection

        // Moonlight rather than amber: this is interactive chrome, and amber is
        // reserved for signals.
        return Button {
            guard !isSelected else { return }
            withAnimation(.easeInOut(duration: 0.18)) { selection = segment.value }
        } label: {
            Text(segment.title)
                .font(.blipperUI(.subheadline, weight: isSelected ? 600 : 500))
                .foregroundStyle(isSelected ? Blipper.onMoonlight : Blipper.moonlight)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Blipper.moonlight : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        // Each segment has to take its own tap. Left on the automatic style,
        // buttons sharing a list row fire together.
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
