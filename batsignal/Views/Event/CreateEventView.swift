import SwiftUI
import MapKit

struct CreateEventView: View {
    @StateObject private var viewModel = CreateEventViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showLocationPicker = false
    @State private var showEmojiPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you doing?") {
                    TextField("e.g. Surfing, Hiking, Coffee", text: $viewModel.activity)
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

                Section("When?") {
                    Picker("When", selection: $viewModel.timing) {
                        ForEach(TimingOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.timing == .later {
                        Picker("Day", selection: $viewModel.selectedDay) {
                            ForEach(DayOption.allCases, id: \.self) { day in
                                Text(day.rawValue).tag(day)
                            }
                        }
                        .pickerStyle(.segmented)
                        DatePicker("Time", selection: $viewModel.selectedTime, displayedComponents: [.hourAndMinute])
                    }
                    durationPicker
                }

                Section("Where?") {
                    locationTypePicker

                    if viewModel.locationType == .text {
                        TextField("Describe the location", text: $viewModel.locationLabel)
                    } else if viewModel.locationType == .fixed {
                        Button(action: { showLocationPicker = true }) {
                            HStack {
                                Image(systemName: "mappin.circle")
                                if viewModel.locationLabel.isEmpty {
                                    Text("Pick a location on the map")
                                        .foregroundColor(.secondary)
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

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Signal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        Task {
                            await viewModel.submit()
                            if viewModel.didCreate { dismiss() }
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(viewModel.activity.isEmpty || viewModel.isLoading)
                }
            }
        }
    }

    private var durationPicker: some View {
        Picker("Duration", selection: durationBinding) {
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
        Picker("Location type", selection: $viewModel.locationType) {
            Text("Live location").tag(LocationType.live)
            Text("Fixed place").tag(LocationType.fixed)
            // Text("Describe it").tag(LocationType.text)
        }
        .pickerStyle(.segmented)
    }
}
