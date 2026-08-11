import SwiftUI
import Combine
import FirebaseCore

struct MyActiveEventCard: View {
    @ObservedObject var viewModel: MyActiveEventViewModel
    // Owned by HomeView, which closes this card when the carousel scrolls off
    // it — the same rule the friends' cards follow.
    @Binding var isExpanded: Bool
    @State private var showDetail = false
    @State private var showUpcomingDetail = false
    @State private var now = Date()
    @State private var joinedUsers: [User] = []
    @State private var isBoolersExpanded = false

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        if let event = viewModel.upcomingEvent {
            if isExpanded {
                upcomingCard(event: event)
            } else {
                compactCard(event: event)
            }
        } else if let event = viewModel.activeEvent {
            if isExpanded {
                activeCard(event: event)
            } else {
                compactCard(event: event)
            }
        }
    }

    @ViewBuilder
    private func compactCard(event: Event) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if event.isActive, let remaining = viewModel.remainingFraction {
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
                if event.isActive {
                    Text(Strings.Home.yourSignal)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                FadingHeadline(text: event.activity, background: Color(.secondarySystemBackground))

                if !event.isActive, let eta = viewModel.etaLabel {
                    Text(eta)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true } }
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
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false } }) {
                    Image(systemName: "chevron.down.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                Button(action: { showUpcomingDetail = true }) {
                    Image(systemName: "pencil.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }

            if event.locationType == .fixed, let locationLabel = event.locationLabel {
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

            joinedBoolers(event: event)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
        .opacity(0.7)
        .task(id: event.joinedUserIds ?? []) {
            await loadJoinedUsers(ids: event.joinedUserIds ?? [])
        }
        .onReceive(timer) { _ in now = Date() }
        .sheet(isPresented: $showUpcomingDetail) {
            UpcomingEventDetailView(event: event, viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func activeCard(event: Event) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text(event.activity)
                    .font(.headline)
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false } }) {
                    Image(systemName: "chevron.down.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                Button(action: { showDetail = true }) {
                    Image(systemName: "pencil.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }

            if let remaining = viewModel.remainingFraction {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: remaining)
                        .tint(remainingColor(remaining))
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

            if event.locationType == .fixed, let locationLabel = event.locationLabel {
                Label(locationLabel, systemImage: locationIcon(event))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Button(role: .destructive, action: {
                    Task { await viewModel.end() }
                }) {
                    Text(Strings.Event.endSignal)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(20)
                }

                Spacer()

                if viewModel.canReduceByThirtyMinutes {
                    Button(action: {
                        Task { await viewModel.reduce() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "minus")
                            Text(Strings.Home.extend30Min)
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.accentColor)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )
                    }
                }

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

            joinedBoolers(event: event)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
        .task(id: event.joinedUserIds ?? []) {
            await loadJoinedUsers(ids: event.joinedUserIds ?? [])
        }
        .onReceive(timer) { _ in now = Date() }
        .sheet(isPresented: $showDetail) {
            ActiveEventDetailView(event: event)
        }
    }

    // MARK: - Who's in

    // The same faces a friend's expanded card shows, minus the join button —
    // it's your own signal, so there's nothing here to join. Collapsed it's a
    // stack of avatars; tapping opens it into names and closes it again.
    @ViewBuilder
    private func joinedBoolers(event: Event) -> some View {
        if !joinedUsers.isEmpty {
            if isBoolersExpanded {
                JoinedBoolersRow(users: joinedUsers) {
                    withAnimation(.easeInOut(duration: 0.25)) { isBoolersExpanded = false }
                }
            } else {
                HStack {
                    JoinedAvatarStack(users: joinedUsers)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { isBoolersExpanded = true }
                }
            }
        }
    }

    // Keyed on the ids so the faces follow the view model's listener as people
    // join and leave, rather than being fetched once when the card opens.
    private func loadJoinedUsers(ids: [String]) async {
        guard !ids.isEmpty else {
            joinedUsers = []
            return
        }
        guard let users = try? await FriendService().fetchFriends(ids: ids) else { return }
        joinedUsers = users
    }

    // Takes time remaining, so the thresholds run the opposite way from a
    // fill-up bar: the less that's left, the more urgent the color.
    private func remainingColor(_ remaining: Double) -> Color {
        if remaining < 0.25 { return .red }
        if remaining < 0.5 { return .orange }
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
    @State private var attemptedSubmitWithoutLocation = false
    @Environment(\.dismiss) private var dismiss

    init(event: Event, viewModel: MyActiveEventViewModel) {
        self.event = event
        self.myEventViewModel = viewModel
        self._editViewModel = StateObject(wrappedValue: EditUpcomingEventViewModel(event: event))
    }

    private var isFixedLocationMissing: Bool {
        editViewModel.locationType == .fixed && editViewModel.fixedCoordinate == nil
    }

    private var showLocationError: Bool {
        attemptedSubmitWithoutLocation && isFixedLocationMissing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EventSymbolHeader(
                        selectedImage: $editViewModel.selectedImage,
                        emoji: $editViewModel.emoji,
                        imageURL: $editViewModel.imageURL
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // Drawn the way the create form draws it, so editing a
                    // signal looks like writing one.
                    VStack(alignment: .center, spacing: 14) {
                        CenteredTextField(
                            text: $editViewModel.activity,
                            placeholder: Strings.Event.activityPlaceholder
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .onChange(of: editViewModel.activity) { _, newValue in
                            if newValue.count > Event.activityCharacterLimit {
                                editViewModel.activity = String(newValue.prefix(Event.activityCharacterLimit))
                            }
                        }
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    EventDurationWheel(
                        durationMinutes: $editViewModel.selectedDurationMinutes,
                        vagueLabel: $editViewModel.selectedVagueLabel
                    )
                    .listRowBackground(Color.clear)
                }

                Section {
                    EventLocationField(
                        locationType: $editViewModel.locationType,
                        locationLabel: $editViewModel.locationLabel,
                        fixedCoordinate: $editViewModel.fixedCoordinate,
                        showError: showLocationError
                    )
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
                        guard !isFixedLocationMissing else {
                            attemptedSubmitWithoutLocation = true
                            return
                        }
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
}

// MARK: - Active event detail / edit sheet

struct ActiveEventDetailView: View {
    let event: Event
    @StateObject private var editViewModel: EditActiveEventViewModel
    @State private var attemptedSubmitWithoutLocation = false
    @Environment(\.dismiss) private var dismiss

    init(event: Event) {
        self.event = event
        self._editViewModel = StateObject(wrappedValue: EditActiveEventViewModel(event: event))
    }

    private var isFixedLocationMissing: Bool {
        editViewModel.locationType == .fixed && editViewModel.fixedCoordinate == nil
    }

    private var showLocationError: Bool {
        attemptedSubmitWithoutLocation && isFixedLocationMissing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EventSymbolHeader(
                        selectedImage: $editViewModel.selectedImage,
                        emoji: $editViewModel.emoji,
                        imageURL: $editViewModel.imageURL
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // Drawn the way the create form draws it, so editing a
                    // signal looks like writing one.
                    VStack(alignment: .center, spacing: 14) {
                        CenteredTextField(
                            text: $editViewModel.activity,
                            placeholder: Strings.Event.activityPlaceholder
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .onChange(of: editViewModel.activity) { _, newValue in
                            if newValue.count > Event.activityCharacterLimit {
                                editViewModel.activity = String(newValue.prefix(Event.activityCharacterLimit))
                            }
                        }
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    EventLocationField(
                        locationType: $editViewModel.locationType,
                        locationLabel: $editViewModel.locationLabel,
                        fixedCoordinate: $editViewModel.fixedCoordinate,
                        showError: showLocationError
                    )
                }

                if let error = editViewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
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
                        guard !isFixedLocationMissing else {
                            attemptedSubmitWithoutLocation = true
                            return
                        }
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
}
