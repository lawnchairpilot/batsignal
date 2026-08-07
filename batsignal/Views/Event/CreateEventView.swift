import SwiftUI

struct CreateEventView: View {
    @StateObject private var viewModel = CreateEventViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isPulsing = false
    @State private var isDragging = false
    @State private var dragProgress: CGFloat = 0

    private let swipeToSendThreshold: CGFloat = -70

    private var canSubmit: Bool {
        !viewModel.activity.isEmpty && !viewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            cardContent
        }
        .task {
            await viewModel.loadGroups()
        }
    }

    private var cardContent: some View {
        ZStack(alignment: .bottom) {
            Form {
                Section {
                    EventSymbolHeader(
                        selectedImage: $viewModel.selectedImage,
                        emoji: $viewModel.emoji,
                        imageURL: .constant(nil)
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    VStack(alignment: .leading, spacing: 14) {
                        TextField(Strings.Event.activityPlaceholder, text: $viewModel.activity)
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    whoPicker

                    EventDurationWheel(
                        durationMinutes: $viewModel.selectedDurationMinutes,
                        vagueLabel: $viewModel.selectedVagueLabel
                    )
                    .listRowBackground(Color.clear)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 200)
            }

            swipeToSendIndicator
        }
        .overlay(alignment: .topLeading) {
            cancelButton
                .padding(.leading, 24)
                .padding(.top, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var cancelButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.red)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var swipeToSendIndicator: some View {
        VStack(spacing: 2) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(.bottom, 4)
            } else if isDragging {
                dragTrackingChevrons
            } else {
                ambientChevrons
            }

            Text(isDragging && dragProgress >= 1 ? Strings.Event.releaseToSend : Strings.Event.swipeUpToSend)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .opacity(canSubmit ? 1 : 0.35)
        .padding(.vertical, 16)
        .frame(width: 280)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard canSubmit else { return }
                    isDragging = true
                    let upwardTranslation = min(0, value.translation.height)
                    dragProgress = min(1, -upwardTranslation / -swipeToSendThreshold)
                }
                .onEnded { value in
                    guard canSubmit else { return }
                    let shouldSend = value.translation.height < swipeToSendThreshold
                    withAnimation(.easeOut(duration: 0.15)) {
                        isDragging = false
                        dragProgress = 0
                    }
                    if shouldSend {
                        submitEvent()
                    }
                }
        )
    }

    private var ambientChevrons: some View {
        ForEach(0..<3, id: \.self) { index in
            chevron(for: index)
                .opacity(isPulsing ? 1 : 0.25)
                .animation(
                    .easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                    value: isPulsing
                )
        }
        .onAppear {
            isPulsing = false
            DispatchQueue.main.async { isPulsing = true }
        }
    }

    private var dragTrackingChevrons: some View {
        ForEach(0..<3, id: \.self) { index in
            chevron(for: index)
                .opacity(chevronOpacity(for: index))
        }
    }

    private func chevron(for index: Int) -> some View {
        let width = chevronWidth(for: index)
        return ChevronShape()
            .stroke(
                Color.accentColor,
                style: StrokeStyle(lineWidth: chevronStrokeWidth(for: index), lineCap: .round, lineJoin: .round)
            )
            .frame(width: width, height: chevronHeight(for: width))
    }

    private func chevronWidth(for index: Int) -> CGFloat {
        // Index 0 is the topmost chevron, index 2 sits closest to the label,
        // so the pyramid tapers up toward the top: bottom is biggest (ratio 3),
        // top is smallest (ratio 1). The biggest arrow is sized to roughly match
        // the duration wheel's selection highlight bar.
        let ratio = CGFloat(index + 1)
        return ratio * 85
    }

    private func chevronHeight(for width: CGFloat) -> CGFloat {
        // Height grows much more slowly than width, so wider arrows read as
        // a flatter, more obtuse angle instead of just scaling up uniformly.
        20 + width * 0.15
    }

    private func chevronStrokeWidth(for index: Int) -> CGFloat {
        // A subtle ramp: the biggest (bottom) arrow reads slightly bolder than
        // the smallest (top) one, without a jarring difference between them.
        5 + CGFloat(index)
    }

    private func chevronOpacity(for index: Int) -> Double {
        // Index 0 is the topmost chevron, index 2 sits closest to the label,
        // so the bottom chevron lights up first as the finger moves up.
        let order = Double(2 - index)
        let segmentStart = order / 3
        let local = (Double(dragProgress) - segmentStart) / (1.0 / 3)
        return 0.25 + 0.75 * min(max(local, 0), 1)
    }

    private func submitEvent() {
        Task {
            await viewModel.submit()
            if viewModel.didCreate { dismiss() }
        }
    }

    private var whoPicker: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    AudienceCard(
                        title: Strings.Event.allFriendsLabel,
                        emoji: nil,
                        systemImage: "person.3.fill",
                        isSelected: viewModel.selectedGroupIds.isEmpty
                    ) {
                        viewModel.selectedGroupIds.removeAll()
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 12) {
                        ForEach(viewModel.groups) { group in
                            AudienceCard(
                                title: group.name,
                                emoji: group.emoji,
                                systemImage: "person.2.fill",
                                isSelected: group.id.map { viewModel.selectedGroupIds.contains($0) } ?? false
                            ) {
                                toggleGroup(group)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .frame(minWidth: geo.size.width)
            }
        }
        .frame(height: 100)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func toggleGroup(_ group: FriendGroup) {
        guard let id = group.id else { return }
        if viewModel.selectedGroupIds.contains(id) {
            viewModel.selectedGroupIds.remove(id)
        } else {
            viewModel.selectedGroupIds.insert(id)
        }
    }
}

private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.maxY)
        let peak = CGPoint(x: rect.midX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)

        // A single control point at each leg's true midpoint, pushed straight
        // down, bows the curve symmetrically — like a parenthesis — so the
        // deepest point sits in the middle of the leg rather than near
        // either end.
        let depth = rect.height * 0.18
        let leftControl = CGPoint(x: (start.x + peak.x) / 2, y: (start.y + peak.y) / 2 + depth)
        let rightControl = CGPoint(x: (peak.x + end.x) / 2, y: (peak.y + end.y) / 2 + depth)

        path.move(to: start)
        path.addQuadCurve(to: peak, control: leftControl)
        path.addQuadCurve(to: end, control: rightControl)
        return path
    }
}

private struct AudienceCard: View {
    let title: String
    let emoji: String?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    private let circleSize: CGFloat = 56

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(.secondarySystemBackground))

                    if let emoji {
                        Text(emoji).font(.title2)
                    } else {
                        Image(systemName: systemImage)
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(width: circleSize, height: circleSize)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color(.separator), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }
}
