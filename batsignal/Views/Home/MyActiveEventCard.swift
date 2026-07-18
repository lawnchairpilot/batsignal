import SwiftUI
import Combine
import FirebaseCore

struct MyActiveEventCard: View {
    @ObservedObject var viewModel: MyActiveEventViewModel
    @State private var showDetail = false
    @State private var showUpcomingDetail = false
    @State private var now = Date()

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        if let event = viewModel.upcomingEvent {
            upcomingCard(event: event)
        } else if let event = viewModel.activeEvent {
            activeCard(event: event)
        }
    }

    @ViewBuilder
    private func upcomingCard(event: Event) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.Home.comingUp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.activity)
                        .font(.headline)
                }
                Spacer()
                if let eta = viewModel.etaLabel {
                    Text(eta)
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                }
                Button(action: { showUpcomingDetail = true }) {
                    Image(systemName: "pencil.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }

            if let locationLabel = event.locationLabel {
                Label(locationLabel, systemImage: locationIcon(event))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text(!event.durationLabel.isEmpty ? event.durationLabel : Strings.Home.openEnded)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(Strings.Common.cancel, role: .destructive) {
                    Task { await viewModel.cancelUpcoming() }
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(20)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
        .opacity(0.7)
        .onReceive(timer) { _ in now = Date() }
        .sheet(isPresented: $showUpcomingDetail) {
            UpcomingEventDetailView(event: event, viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func activeCard(event: Event) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.Home.yourSignal)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.activity)
                        .font(.headline)
                }
                Spacer()
                Button(action: { showDetail = true }) {
                    Image(systemName: "pencil.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }

            if let progress = viewModel.progress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(progressColor(progress))
                    if let label = viewModel.timeRemainingLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let label = event.durationVagueLabel {
                Label(label, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                if let locationLabel = event.locationLabel {
                    Label(locationLabel, systemImage: locationIcon(event))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if event.durationMinutes != nil {
                    Button(action: {
                        Task { await viewModel.extend() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(Strings.Home.extend30Min)
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
        .onReceive(timer) { _ in now = Date() }
        .sheet(isPresented: $showDetail) {
            ActiveEventDetailView(event: event, viewModel: viewModel)
        }
    }

    private func progressColor(_ progress: Double) -> Color {
        if progress > 0.75 { return .red }
        if progress > 0.5 { return .orange }
        return .accentColor
    }

    private func locationIcon(_ event: Event) -> String {
        switch event.locationType {
        case .text: return "mappin"
        case .fixed: return "mappin.circle"
        case .live: return "location.fill"
        }
    }
}

// MARK: - Upcoming event edit sheet

struct UpcomingEventDetailView: View {
    let event: Event
    @ObservedObject var myEventViewModel: MyActiveEventViewModel
    @StateObject private var editViewModel: EditUpcomingEventViewModel
    @State private var showLocationPicker = false
    @State private var showEmojiPicker = false
    @Environment(\.dismiss) private var dismiss

    init(event: Event, viewModel: MyActiveEventViewModel) {
        self.event = event
        self.myEventViewModel = viewModel
        self._editViewModel = StateObject(wrappedValue: EditUpcomingEventViewModel(event: event))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Strings.Event.whatAreYouDoingSection) {
                    TextField(Strings.Event.activityFieldLabel, text: $editViewModel.activity)
                    TextField(Strings.Event.descriptionPlaceholder, text: $editViewModel.description, axis: .vertical)
                        .lineLimit(3...)
                    Button(action: { showEmojiPicker = true }) {
                        HStack {
                            Text(Strings.Event.emojiFieldLabel)
                                .foregroundColor(.primary)
                            Spacer()
                            if let emoji = editViewModel.emoji {
                                Text(emoji).font(.title2)
                            } else {
                                Text(Strings.Event.noneSelected)
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .sheet(isPresented: $showEmojiPicker) {
                        EmojiPickerView(selectedEmoji: $editViewModel.emoji)
                    }
                }

                Section(Strings.Event.whenSection) {
                    Picker(Strings.Event.dayPickerLabel, selection: $editViewModel.selectedDay) {
                        ForEach(DayOption.allCases, id: \.self) { day in
                            Text(day.rawValue).tag(day)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker(Strings.Event.timePickerLabel, selection: $editViewModel.selectedTime, displayedComponents: [.hourAndMinute])
                    Picker(Strings.Event.durationPickerLabel, selection: durationBinding) {
                        ForEach(Event.durationOptions, id: \.minutes) { option in
                            Text(option.label).tag(option.label)
                        }
                        ForEach(Event.vagueOptions, id: \.self) { label in
                            Text(label).tag(label)
                        }
                    }
                }

                Section(Strings.Event.whereSection) {
                    Picker(Strings.Event.locationTypePickerLabel, selection: $editViewModel.locationType) {
                        Text(Strings.Event.describeIt).tag(LocationType.text)
                        Text(Strings.Event.fixedPlace).tag(LocationType.fixed)
                        Text(Strings.Event.liveLocation).tag(LocationType.live)
                    }
                    .pickerStyle(.segmented)

                    if editViewModel.locationType == .text {
                        TextField(Strings.Event.locationDescriptionPlaceholder, text: $editViewModel.locationLabel)
                    } else if editViewModel.locationType == .fixed {
                        Button(action: { showLocationPicker = true }) {
                            HStack {
                                Image(systemName: "mappin.circle")
                                if editViewModel.locationLabel.isEmpty {
                                    Text(Strings.Event.pickLocationOnMap).foregroundColor(.secondary)
                                } else {
                                    Text(editViewModel.locationLabel).foregroundColor(.primary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .sheet(isPresented: $showLocationPicker) {
                            LocationPickerView { picked in
                                editViewModel.locationLabel = picked.name
                                editViewModel.fixedCoordinate = picked.coordinate
                            }
                        }
                    }
                }

                if let error = editViewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }

                Section {
                    Button(Strings.Event.cancelEvent, role: .destructive) {
                        Task {
                            await myEventViewModel.cancelUpcoming()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Strings.Event.editSignalTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        Task {
                            await editViewModel.save()
                            if editViewModel.didSave { dismiss() }
                        }
                    }) {
                        if editViewModel.isLoading {
                            ProgressView()
                        } else {
                            Text(Strings.Common.save)
                        }
                    }
                    .disabled(editViewModel.activity.isEmpty || editViewModel.isLoading)
                }
            }
        }
    }

    private var durationBinding: Binding<String> {
        Binding(
            get: { editViewModel.durationLabel },
            set: { label in
                if let option = Event.durationOptions.first(where: { $0.label == label }) {
                    editViewModel.selectedDurationMinutes = option.minutes
                    editViewModel.selectedVagueLabel = nil
                } else {
                    editViewModel.selectedDurationMinutes = nil
                    editViewModel.selectedVagueLabel = label
                }
            }
        )
    }
}

// MARK: - Active event detail / edit sheet

struct ActiveEventDetailView: View {
    let event: Event
    @ObservedObject var myEventViewModel: MyActiveEventViewModel
    @StateObject private var editViewModel: EditActiveEventViewModel
    @State private var showLocationPicker = false
    @State private var showEmojiPicker = false
    @Environment(\.dismiss) private var dismiss

    init(event: Event, viewModel: MyActiveEventViewModel) {
        self.event = event
        self.myEventViewModel = viewModel
        self._editViewModel = StateObject(wrappedValue: EditActiveEventViewModel(event: event))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Strings.Event.whatAreYouDoingSection) {
                    TextField(Strings.Event.activityFieldLabel, text: $editViewModel.activity)
                    TextField(Strings.Event.descriptionPlaceholder, text: $editViewModel.description, axis: .vertical)
                        .lineLimit(3...)
                    Button(action: { showEmojiPicker = true }) {
                        HStack {
                            Text(Strings.Event.emojiFieldLabel)
                                .foregroundColor(.primary)
                            Spacer()
                            if let emoji = editViewModel.emoji {
                                Text(emoji).font(.title2)
                            } else {
                                Text(Strings.Event.noneSelected)
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .sheet(isPresented: $showEmojiPicker) {
                        EmojiPickerView(selectedEmoji: $editViewModel.emoji)
                    }
                }

                Section(Strings.Event.timeSection) {
                    HStack {
                        Text(Strings.Event.started)
                        Spacer()
                        Text(event.startTime.dateValue(), style: .time)
                            .foregroundColor(.secondary)
                    }
                    Picker(Strings.Event.durationPickerLabel, selection: durationBinding) {
                        ForEach(Event.durationOptions, id: \.minutes) { option in
                            Text(option.label).tag(option.label)
                        }
                        ForEach(Event.vagueOptions, id: \.self) { label in
                            Text(label).tag(label)
                        }
                    }
                    if editViewModel.selectedDurationMinutes != nil {
                        Button(action: { Task { await myEventViewModel.extend() } }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text(Strings.Event.add30Minutes)
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                }

                Section(Strings.Event.whereSection) {
                    Picker(Strings.Event.locationTypePickerLabel, selection: $editViewModel.locationType) {
                        Text(Strings.Event.describeIt).tag(LocationType.text)
                        Text(Strings.Event.fixedPlace).tag(LocationType.fixed)
                        Text(Strings.Event.liveLocation).tag(LocationType.live)
                    }
                    .pickerStyle(.segmented)

                    if editViewModel.locationType == .text {
                        TextField(Strings.Event.locationDescriptionPlaceholder, text: $editViewModel.locationLabel)
                    } else if editViewModel.locationType == .fixed {
                        Button(action: { showLocationPicker = true }) {
                            HStack {
                                Image(systemName: "mappin.circle")
                                if editViewModel.locationLabel.isEmpty {
                                    Text(Strings.Event.pickLocationOnMap).foregroundColor(.secondary)
                                } else {
                                    Text(editViewModel.locationLabel).foregroundColor(.primary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .sheet(isPresented: $showLocationPicker) {
                            LocationPickerView { picked in
                                editViewModel.locationLabel = picked.name
                                editViewModel.fixedCoordinate = picked.coordinate
                            }
                        }
                    }
                }

                if let error = editViewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }

                Section {
                    Button(Strings.Event.endSignal, role: .destructive) {
                        Task {
                            await myEventViewModel.end()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Strings.Event.yourSignalTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        Task {
                            await editViewModel.save()
                            if editViewModel.didSave { dismiss() }
                        }
                    }) {
                        if editViewModel.isLoading {
                            ProgressView()
                        } else {
                            Text(Strings.Common.save)
                        }
                    }
                    .disabled(editViewModel.activity.isEmpty || editViewModel.isLoading)
                }
            }
        }
    }

    private var durationBinding: Binding<String> {
        Binding(
            get: { editViewModel.durationLabel },
            set: { label in
                if let option = Event.durationOptions.first(where: { $0.label == label }) {
                    editViewModel.selectedDurationMinutes = option.minutes
                    editViewModel.selectedVagueLabel = nil
                } else {
                    editViewModel.selectedDurationMinutes = nil
                    editViewModel.selectedVagueLabel = label
                }
            }
        )
    }
}
