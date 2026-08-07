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
    private var recoveryListener: ListenerRegistration?
    private var expiryTimer: Timer?

    func startListening(activeEventId: String?) {
        listener?.remove()
        listener = nil
        recoveryListener?.remove()
        recoveryListener = nil
        locationService.stopLiveSharing()
        activeEvent = nil
        upcomingEvent = nil
        expiryTimer?.invalidate()
        expiryTimer = nil

        guard let eventId = activeEventId else {
            startRecoveryListening()
            return
        }

        listener = eventService.listenToEventSnapshot(id: eventId) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                switch snapshot {
                case .unavailable:
                    // We don't know the event's state, so don't touch anything. Treating
                    // an unreadable snapshot as "terminal" is what orphaned live events:
                    // it detached activeEventId on this device while the event stayed
                    // active for everyone else, with no code path left to reconcile them.
                    return

                case .missing:
                    // Server-confirmed deletion, so the pointer is genuinely dangling.
                    self.locationService.stopLiveSharing()
                    self.activeEvent = nil
                    self.upcomingEvent = nil
                    try? await self.eventService.clearActiveEventId()

                case .value(let event):
                    if event.isActive, !event.isExpired {
                        self.activeEvent = event
                        self.upcomingEvent = nil
                        if event.locationType == .live, let id = event.id {
                            self.locationService.startLiveSharing(for: id)
                        }
                    } else if !event.isActive, !event.isExpired {
                        self.upcomingEvent = event
                        self.activeEvent = nil
                        self.locationService.stopLiveSharing()
                    } else {
                        self.locationService.stopLiveSharing()
                        self.activeEvent = nil
                        self.upcomingEvent = nil
                        if event.isActive, event.isExpired, let id = event.id {
                            do {
                                try await self.eventService.endEvent(id: id)
                            } catch {
                                // Must not stay silent: activeEvent is cleared above either way,
                                // so neither the card nor the 60s expiryTimer (which only runs
                                // while activeEvent is set) can retry this write.
                                print("MyActiveEventViewModel: failed to end expired event \(id): \(error.localizedDescription)")
                            }
                        } else {
                            // Already inactive and past its endTime — detach the stale pointer
                            // so it can't keep blocking creation.
                            try? await self.eventService.clearActiveEventId()
                        }
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

    // Having no activeEventId doesn't prove the user has no event: earlier builds could
    // detach the pointer while leaving the event active, and only the creator's device
    // ever ends an event — so the orphan stayed live on every friend's feed forever.
    // Re-adopt it so it shows up again, can be ended, and blocks duplicate creation.
    private func startRecoveryListening() {
        recoveryListener = eventService.listenToMyActiveEvent { [weak self] event in
            Task { @MainActor in
                guard let self, let event, let id = event.id else { return }
                if event.isExpired {
                    // Nobody can see it anymore; just retire it so it stops being found.
                    try? await self.eventService.endEvent(id: id)
                } else {
                    // Re-pointing the user doc re-runs startListening with the real id,
                    // which tears this recovery listener down.
                    try? await self.eventService.adoptActiveEvent(id: id)
                }
            }
        }
    }

    // MARK: - Progress

    var progress: Double? {
        activeEvent?.progress
    }

    var timeRemainingLabel: String? {
        activeEvent?.timeRemainingLabel
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

    // Never lets the event end via this button — only usable while at least
    // 30 minutes remain, so ending is still a deliberate, separate action.
    var canReduceByThirtyMinutes: Bool {
        guard let event = activeEvent,
              event.durationMinutes != nil,
              let endTime = event.endTime else { return false }
        return endTime.dateValue().timeIntervalSince(Date()) >= 30 * 60
    }

    func reduce() async {
        guard canReduceByThirtyMinutes,
              let event = activeEvent,
              let id = event.id,
              let durationMinutes = event.durationMinutes,
              let endTime = event.endTime else { return }
        try? await eventService.reduceEvent(
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