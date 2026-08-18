import SwiftUI
import UIKit

struct CreateEventView: View {
    @StateObject private var viewModel = CreateEventViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isPulsing = false
    @State private var isDragging = false
    @State private var dragProgress: CGFloat = 0

    private let swipeToSendThreshold: CGFloat = -70
    private let indicatorLineCount = 5

    private var canSubmit: Bool {
        !viewModel.activity.isEmpty && !viewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            cardContent
                .ignoresSafeArea(.keyboard, edges: .bottom)
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

                    VStack(alignment: .center, spacing: 14) {
                        CenteredTextField(text: $viewModel.activity, placeholder: Strings.Event.activityPlaceholder)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .onChange(of: viewModel.activity) { _, newValue in
                                if newValue.count > Event.activityCharacterLimit {
                                    viewModel.activity = String(newValue.prefix(Event.activityCharacterLimit))
                                }
                            }
                        Rectangle()
                            .fill(Blipper.hairline)
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
                        Text(error).foregroundColor(Blipper.roseBright).font(.blipperUI(.caption1))
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollDisabled(true)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 200)
            }

            swipeToSendIndicator
        }
        .blipperBackground()
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
                .foregroundColor(Blipper.roseBright)
                .frame(width: 44, height: 44)
                .background(Blipper.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Blipper.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var swipeToSendIndicator: some View {
        VStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(.bottom, 4)
            } else if isDragging {
                dragTrackingLines
            } else {
                ambientLines
            }

            Text(isDragging && dragProgress >= 1 ? Strings.Event.releaseToSend : Strings.Event.swipeUpToSend)
                .font(.blipperUI(.caption1))
                .foregroundColor(Blipper.textMuted)
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

    private var ambientLines: some View {
        ForEach(0..<indicatorLineCount, id: \.self) { index in
            line(for: index)
                .opacity(isPulsing ? 1 : 0.25)
                .animation(
                    .easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                    value: isPulsing
                )
        }
        .onAppear {
            isPulsing = false
            DispatchQueue.main.async { isPulsing = true }
        }
    }

    private var dragTrackingLines: some View {
        ForEach(0..<indicatorLineCount, id: \.self) { index in
            line(for: index)
                .opacity(lineOpacity(for: index))
        }
    }

    private func line(for index: Int) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: lineWidth(for: index), height: lineThickness(for: index))
    }

    private func lineWidth(for index: Int) -> CGFloat {
        // Index 0 is the topmost line, the last index sits closest to the
        // label, so the stack tapers up toward the top: the bottom line is
        // widest, matching the duration wheel's selection highlight bar.
        let ratio = CGFloat(index + 1)
        return ratio * (255 / CGFloat(indicatorLineCount))
    }

    private func lineThickness(for index: Int) -> CGFloat {
        // A subtle ramp: the bottom line reads slightly bolder than the top
        // one, without a jarring difference between them.
        8 + CGFloat(index)
    }

    private func lineOpacity(for index: Int) -> Double {
        // Index 0 is the topmost line, the last index sits closest to the
        // label, so the bottom line lights up first as the finger moves up.
        let order = Double(indicatorLineCount - 1 - index)
        let segmentStart = order / Double(indicatorLineCount)
        let local = (Double(dragProgress) - segmentStart) / (1.0 / Double(indicatorLineCount))
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

// A plain SwiftUI `TextField` with `.multilineTextAlignment(.center)` shows
// its caret at the leading edge of the (centered) placeholder until the
// first keystroke, when it snaps to the true center. Setting
// `textAlignment` on the underlying `UITextField` directly avoids that.
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
                    Circle().fill(Blipper.surface)

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
                        .stroke(isSelected ? Color.accentColor : Blipper.hairline, lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                Text(title)
                    .font(.blipperUI(.caption1))
                    .fontWeight(.medium)
                    .foregroundColor(Blipper.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }
}
