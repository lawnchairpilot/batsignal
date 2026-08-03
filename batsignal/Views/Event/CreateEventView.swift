import SwiftUI
import MapKit

struct CreateEventView: View {
    @StateObject private var viewModel = CreateEventViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showLocationPicker = false
    @State private var showEmojiPicker = false
    @State private var attemptedSubmitWithoutLocation = false

    private var isFixedLocationMissing: Bool {
        viewModel.locationType == .fixed && viewModel.fixedCoordinate == nil
    }

    private var showLocationError: Bool {
        attemptedSubmitWithoutLocation && isFixedLocationMissing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Strings.Event.whatAreYouDoingSection) {
                    TextField(Strings.Event.activityPlaceholder, text: $viewModel.activity)
                    EventImagePickerRow(imageURL: .constant(nil), selectedImage: $viewModel.selectedImage)
                    // TextField("Description (optional)", text: $viewModel.description, axis: .vertical)
                    //     .lineLimit(3...)
                    // Button(action: { showEmojiPicker = true }) {
                    //     HStack {
                    //         Text("Symbol")
                    //             .foregroundColor(.primary)
                    //         Spacer()
                    //         if let emoji = viewModel.emoji {
                    //             Text(emoji).font(.title2)
                    //         } else {
                    //             Text("None")
                    //                 .foregroundColor(.secondary)
                    //         }
                    //         Image(systemName: "chevron.right")
                    //             .font(.caption)
                    //             .foregroundColor(.secondary)
                    //     }
                    // }
                    // .sheet(isPresented: $showEmojiPicker) {
                    //     EmojiPickerView(selectedEmoji: $viewModel.emoji)
                    // }
                }

                Section(Strings.Event.whenSection) {
                    Picker(Strings.Event.whenPickerLabel, selection: $viewModel.timing) {
                        ForEach(TimingOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.timing == .later {
                        Picker(Strings.Event.dayPickerLabel, selection: $viewModel.selectedDay) {
                            ForEach(DayOption.allCases, id: \.self) { day in
                                Text(day.rawValue).tag(day)
                            }
                        }
                        .pickerStyle(.segmented)
                        DatePicker(Strings.Event.timePickerLabel, selection: $viewModel.selectedTime, displayedComponents: [.hourAndMinute])
                    }
                    durationPicker
                }

                Section(Strings.Event.whereSection) {
                    locationTypePicker

                    if viewModel.locationType == .text {
                        TextField(Strings.Event.locationDescriptionPlaceholder, text: $viewModel.locationLabel)
                    } else if viewModel.locationType == .fixed {
                        Button(action: { showLocationPicker = true }) {
                            HStack {
                                Image(systemName: "mappin.circle")
                                    .foregroundColor(showLocationError ? .red : .accentColor)
                                if viewModel.locationLabel.isEmpty {
                                    Text(Strings.Event.pickLocationOnMap)
                                        .foregroundColor(showLocationError ? .red : .secondary)
                                } else {
                                    Text(viewModel.locationLabel)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .sheet(isPresented: $showLocationPicker) {
                            LocationPickerView { picked in
                                viewModel.locationLabel = picked.name
                                viewModel.fixedCoordinate = picked.coordinate
                            }
                        }
                    }
                }

                Section(Strings.Event.whoSection) {
                    whoPicker
                }

                Section {
                    Toggle(Strings.Event.commentsToggleLabel, isOn: $viewModel.commentsEnabled)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(Strings.Event.newSignalTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        guard !isFixedLocationMissing else {
                            attemptedSubmitWithoutLocation = true
                            return
                        }
                        Task {
                            await viewModel.submit()
                            if viewModel.didCreate { dismiss() }
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text(Strings.Event.send)
                        }
                    }
                    .disabled(viewModel.activity.isEmpty || viewModel.isLoading)
                }
            }
        }
        .task {
            await viewModel.loadGroups()
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

    private var locationTypePicker: some View {
        Picker(Strings.Event.locationTypePickerLabel, selection: $viewModel.locationType) {
            Text(Strings.Event.liveLocation).tag(LocationType.live)
            Text(Strings.Event.fixedPlace).tag(LocationType.fixed)
            // Text("Describe it").tag(LocationType.text)
        }
        .pickerStyle(.segmented)
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
