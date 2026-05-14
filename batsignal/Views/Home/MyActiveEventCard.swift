import SwiftUI
import Combine
import FirebaseCore

struct MyActiveEventCard: View {
    @ObservedObject var viewModel: MyActiveEventViewModel
    @State private var showDetail = false
    @State private var now = Date()

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        guard let event = viewModel.activeEvent else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {

                // Header row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your signal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(event.activity)
                            .font(.headline)
                    }
                    Spacer()
                    // Edit button
                    Button(action: { showDetail = true }) {
                        Image(systemName: "pencil.circle")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                }

                // Progress bar (only if timed)
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
                    // Vague duration — just show the label
                    Label(label, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Bottom row: location + extend button
                HStack {
                    if let locationLabel = event.locationLabel {
                        Label(locationLabel, systemImage: locationIcon(event))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()

                    // +30 min button — only shown for timed events
                    if event.durationMinutes != nil {
                        Button(action: {
                            Task { await viewModel.extend() }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("30 min")
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
        )
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

// MARK: - Active event detail / edit sheet

struct ActiveEventDetailView: View {
    let event: Event
    @ObservedObject var viewModel: MyActiveEventViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Activity") {
                    Text(event.activity).font(.headline)
                    if let desc = event.description {
                        Text(desc).foregroundColor(.secondary)
                    }
                }

                Section("Time") {
                    HStack {
                        Text("Started")
                        Spacer()
                        Text(event.startTime.dateValue(), style: .time)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(event.durationLabel)
                            .foregroundColor(.secondary)
                    }
                    if event.durationMinutes != nil {
                        Button(action: {
                            Task { await viewModel.extend() }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add 30 minutes")
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                }

                if let label = event.locationLabel {
                    Section("Location") {
                        Label(label, systemImage: locationIcon)
                    }
                }

                Section {
                    Button("End Signal", role: .destructive) {
                        Task {
                            await viewModel.end()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Your Signal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var locationIcon: String {
        switch event.locationType {
        case .text: return "mappin"
        case .fixed: return "mappin.circle"
        case .live: return "location.fill"
        }
    }
}
