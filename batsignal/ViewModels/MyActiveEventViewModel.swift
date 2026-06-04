import Foundation
import Combine
import FirebaseFirestore

@MainActor
class MyActiveEventViewModel: ObservableObject {
    @Published var activeEvent: Event? = nil

    private let eventService = EventService()
    private var listener: ListenerRegistration?

    /// Called whenever authService.currentUser changes — looks up the specific event document.
    func startListening(activeEventId: String?) {
        listener?.remove()
        listener = nil
        activeEvent = nil

        guard let eventId = activeEventId else { return }

        listener = eventService.listenToEvent(id: eventId) { [weak self] event in
            Task { @MainActor in
                // Treat expired or inactive events as nil
                if let event, event.isActive, !event.isExpired {
                    self?.activeEvent = event
                } else {
                    self?.activeEvent = nil
                }
            }
        }
    }

    // MARK: - Progress

    var progress: Double? {
        guard let event = activeEvent,
              let durationMinutes = event.durationMinutes,
              let endTime = event.endTime else { return nil }
        let total = Double(durationMinutes) * 60
        let elapsed = Date().timeIntervalSince(event.startTime.dateValue())
        return min(max(elapsed / total, 0), 1)
    }

    var timeRemainingLabel: String? {
        guard let endTime = activeEvent?.endTime else { return nil }
        let remaining = endTime.dateValue().timeIntervalSince(Date())
        guard remaining > 0 else { return "Ending..." }
        let minutes = Int(remaining) / 60
        let hours = minutes / 60
        if hours > 0 {
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m left" : "\(hours)h left"
        }
        return "\(minutes)m left"
    }

    // MARK: - Actions

    func extend() async {
        guard let event = activeEvent,
              let id = event.id,
              let durationMinutes = event.durationMinutes,
              let endTime = event.endTime else { return }
        try? await eventService.extendEvent(
            id: id,
            currentEndTime: endTime.dateValue(),
            currentDurationMinutes: durationMinutes
        )
    }

    func end() async {
        guard let id = activeEvent?.id else { return }
        try? await eventService.endEvent(id: id)
    }
}
