import SwiftUI

struct CreateEventView: View {
    @StateObject private var viewModel = CreateEventViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEmojiPicker = false
    @State private var showCamera = false
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
                        symbolHeader
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)

                        TextField(Strings.Event.activityPlaceholder, text: $viewModel.activity)
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        durationPicker
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        whoPicker
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

                cancelButton
                    .padding(.leading, 24)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                swipeToSendIndicator
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
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
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

    private var durationPicker: some View {
        Picker(Strings.Event.durationPickerLabel, selection: durationBinding) {
            ForEach(Event.durationOptions, id: \.minutes) { option in
                Text(option.label).tag(option.label)
            }
            ForEach(Event.vagueOptions, id: \.self) { label in
                Text(label).tag(label)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 100)
        .clipped()
    }

    // Maps picker selection (a label string) back to the viewModel's two fields
    private var durationBinding: Binding<String> {
        Binding(
            get: { viewModel.durationLabel },
            set: { label in
                if let option = Event.durationOptions.first(where: { $0.label == label }) {
                    viewModel.selectedDurationMinutes = option.minutes
                    viewModel.selectedVagueLabel = nil
                } else {
                    viewModel.selectedDurationMinutes = nil
                    viewModel.selectedVagueLabel = label
                }
            }
        )
    }

    private let symbolPreviewSize: CGFloat = 220
    private let symbolButtonSize: CGFloat = 44

    // Large preview of how the event's icon will appear on the map.
    private var symbolHeader: some View {
        HStack(alignment: .bottom, spacing: 28) {
            symbolImageButton
            symbolPreviewCircle
            symbolEmojiButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerView(selectedEmoji: $viewModel.emoji)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView(image: $viewModel.selectedImage)
                .ignoresSafeArea()
        }
        .onChange(of: viewModel.selectedImage) { _, newImage in
            if newImage != nil { viewModel.emoji = nil }
        }
        .onChange(of: viewModel.emoji) { _, newEmoji in
            if newEmoji != nil { viewModel.selectedImage = nil }
        }
    }

    private var symbolPreviewCircle: some View {
        ZStack {
            Circle().fill(Color.accentColor)

            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let emoji = viewModel.emoji {
                Text(emoji)
                    .font(.system(size: symbolPreviewSize * 0.45))
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: symbolPreviewSize * 0.3))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .frame(width: symbolPreviewSize, height: symbolPreviewSize)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
    }

    private var symbolImageThumbnail: some View {
        Image(systemName: "camera.fill")
            .font(.title3)
            .foregroundColor(.accentColor)
            .frame(width: symbolButtonSize, height: symbolButtonSize)
            .background(Color(.secondarySystemBackground))
            .clipShape(Circle())
    }

    private var symbolImageButton: some View {
        Group {
            if viewModel.selectedImage != nil {
                Menu {
                    Button(action: { showCamera = true }) {
                        Label(Strings.Event.changeImage, systemImage: "camera")
                    }
                    Button(role: .destructive, action: { viewModel.selectedImage = nil }) {
                        Label(Strings.Event.removeImage, systemImage: "trash")
                    }
                } label: {
                    symbolImageThumbnail
                }
            } else {
                Button(action: { showCamera = true }) {
                    symbolImageThumbnail
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var symbolEmojiButton: some View {
        Button(action: { showEmojiPicker = true }) {
            Image(systemName: "face.smiling")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: symbolButtonSize, height: symbolButtonSize)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct AudienceCard: View {
    let title: String
    let emoji: String?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if let emoji {
                    Text(emoji).font(.title2)
                } else {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(width: 96, height: 84)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
