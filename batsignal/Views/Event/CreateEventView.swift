import SwiftUI

struct CreateEventView: View {
    @StateObject private var viewModel = CreateEventViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you doing?") {
                    TextField("e.g. Surfing, Hiking, Coffee", text: $viewModel.activity)
                    TextField("Description (optional)", text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...)
                }

                Section("When?") {
                    DatePicker("Start time", selection: $viewModel.startTime, displayedComponents: [.date, .hourAndMinute])
                    durationPicker
                }

                Section("Where?") {
                    locationTypePicker
                    if viewModel.locationType == .text || viewModel.locationType == .fixed {
                        TextField("Location description", text: $viewModel.locationLabel)
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
            Text("Describe it").tag(LocationType.text)
            Text("Fixed place").tag(LocationType.fixed)
            Text("Live location").tag(LocationType.live)
        }
        .pickerStyle(.segmented)
    }
}
