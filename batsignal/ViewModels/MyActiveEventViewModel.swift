import Foundation
import Combine
import FirebaseFirestore

@MainActor
class MyActiveEventViewModel: ObservableObject {
    @Published var activeEvent: Event? = nil
    @Published var upcomingEvent: Event? = nil

    private let eventService = EventService()
    private let locationService = LocationService()
    private var listener: ListenerRegistration?
    private var expiryTimer: Timer?

    func startListening(activeEventId: String?) {
        listener?.remove()
        listener = nil
        locationService.stopLiveSharing()
        activeEvent = nil
        upcomingEvent = nil
        expiryTimer?.invalidate()
        expiryTimer = nil

        guard let eventId = activeEventId else { return }

        listener = eventService.listenToEvent(id: eventId) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if let event, event.isActive, !event.isExpired {
                    self.activeEvent = event
                    self.upcomingEvent = nil
                    if event.locationType == .live, let id = event.id {
                        self.locationService.startLiveSharing(for: id)
                    }
                } else if let event, !event.isActive, !event.isExpired {
                    self.upcomingEvent = event
                    self.activeEvent = nil
                    self.locationService.stopLiveSharing()
                } else {
                    self.locationService.stopLiveSharing()
                    self.activeEvent = nil
                    self.upcomingEvent = nil
                    if let event, event.isActive, event.isExpired, let id = event.id {
                        try? await self.eventService.endEvent(id: id)
                    }
                }
            }
        }

        // Catches expiry while the app is running
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let event = self.activeEvent,
                      event.isExpired,
                      let id = event.id else { return }
                try? await self.eventService.endEvent(id: id)
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

    var etaLabel: String? {
        guard let event = upcomingEvent else { return nil }
        let remaining = event.startTime.dateValue().timeIntervalSince(Date())
        guard remaining > 0 else { return "Starting soon..." }
        let minutes = Int(remaining) / 60
        let hours = minutes / 60
        if hours > 0 {
            let mins = minutes % 60
            return mins > 0 ? "Starts in \(hours)h \(mins)m" : "Starts in \(hours)h"
        }
        return "Starts in \(minutes)m"
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
        locationService.stopLiveSharing()
        guard let id = activeEvent?.id else { return }
        try? await eventService.endEvent(id: id)
    }

    func cancelUpcoming() async {
        locationService.stopLiveSharing()
        guard let id = upcomingEvent?.id else { return }
        try? await eventService.cancelEvent(id: id)
    }

    deinit {
        expiryTimer?.invalidate()
    }
}