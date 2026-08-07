import SwiftUI

struct CreateEventView: View {
    @StateObject private var viewModel = CreateEventViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isPulsing = false

    private let swipeToSendThreshold: CGFloat = -70

    private var canSubmit: Bool {
        !viewModel.activity.isEmpty && !viewModel.isLoading
    }

    var body: some View {
        NavigationStack {
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
                    Color.clear.frame(height: 110)
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
        .task {
            await viewModel.loadGroups()
        }
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
            } else {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "chevron.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.accentColor)
                        .opacity(isPulsing ? 1 : 0.25)
                        .animation(
                            .easeInOut(duration: 0.9)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: isPulsing
                        )
                }
            }
            Text(Strings.Event.swipeUpToSend)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .opacity(canSubmit ? 1 : 0.35)
        .padding(.vertical, 16)
        .frame(width: 160)
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard canSubmit else { return }
                    dragOffset = min(0, value.translation.height)
                }
                .onEnded { value in
                    guard canSubmit else { return }
                    if value.translation.height < swipeToSendThreshold {
                        submitEvent()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                }
        )
        .onAppear { isPulsing = true }
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
