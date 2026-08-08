import Foundation
import Combine
import FirebaseFirestore
import CoreLocation
import UIKit

@MainActor
class EditActiveEventViewModel: ObservableObject {
    let eventId: String
    private let originalStartTime: Timestamp
    private let originalEndTime: Timestamp?
    private let originalDurationMinutes: Int?
    private let originalVagueLabel: String?

    @Published var activity: String
    @Published var emoji: String?
    @Published var description: String
    @Published var selectedDurationMinutes: Int?
    @Published var selectedVagueLabel: String?
    @Published var locationType: LocationType
    @Published var locationLabel: String
    @Published var fixedCoordinate: CLLocationCoordinate2D?
    @Published var commentsEnabled: Bool
    @Published var imageURL: String?
    @Published var selectedImage: UIImage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var didSave = false

    private let eventService = EventService()

    init(event: Event) {
        self.eventId = event.id ?? ""
        self.originalStartTime = event.startTime
        self.originalEndTime = event.endTime
        self.originalDurationMinutes = event.durationMinutes
        self.originalVagueLabel = event.durationVagueLabel
        self.activity = event.activity
        self.emoji = event.emoji
        self.description = event.description ?? ""
        self.locationType = event.locationType
        self.locationLabel = event.locationLabel ?? ""
        self.commentsEnabled = event.commentsAllowed
        self.imageURL = event.imageURL

        if let minutes = event.durationMinutes {
            self.selectedDurationMinutes = minutes
            self.selectedVagueLabel = nil
        } else {
            self.selectedDurationMinutes = nil
            self.selectedVagueLabel = event.durationVagueLabel
        }

        if let coord = event.locationCoordinate {
            self.fixedCoordinate = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }
    }

    var durationLabel: String {
        if let minutes = selectedDurationMinutes {
            return Event.durationOptions.first { $0.minutes == minutes }?.label ?? ""
        }
        return selectedVagueLabel ?? ""
    }

    func save() async {
        guard !eventId.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        // Only recompute endTime when the duration selection actually changed —
        // recomputing unconditionally on every save re-pins vague durations ("til
        // dark") to 9 PM on the start date, which can already be in the past by
        // the time an unrelated field (photo, description, ...) gets edited later
        // in the evening, instantly "expiring" a still-active event on save.
        let durationChanged = selectedDurationMinutes != originalDurationMinutes
            || selectedVagueLabel != originalVagueLabel
        let endTime = durationChanged
            ? Event.computeEndTime(
                startTime: originalStartTime.dateValue(),
                durationMinutes: selectedDurationMinutes,
                vagueLabel: selectedVagueLabel
            )
            : originalEndTime

        let coordinate: EventService.CoordinateUpdate
        switch locationType {
        case .fixed:
            if let fixed = fixedCoordinate {
                coordinate = .set(GeoPoint(latitude: fixed.latitude, longitude: fixed.longitude))
            } else {
                coordinate = .clear
            }
        case .live:
            // LocationService owns this field while the event is live. Writing the
            // sheet's nil here deleted it, dropping the pin off friends' maps until
            // the next significant-location update landed.
            coordinate = .unchanged
        case .text:
            coordinate = .clear
        }

        var finalImageURL = imageURL
        if let selectedImage {
            do {
                finalImageURL = try await PhotoStorageService().uploadEventImage(selectedImage)
            } catch {
                errorMessage = Strings.Event.imageUploadFailed(error.localizedDescription)
                isLoading = false
                return
            }
        }

        do {
            try await eventService.updateEvent(
                id: eventId,
                activity: activity,
                emoji: emoji,
                description: description.isEmpty ? nil : description,
                startTime: originalStartTime,
                durationMinutes: selectedDurationMinutes,
                durationVagueLabel: selectedVagueLabel,
                endTime: endTime,
                // No duration wheel here — the +30/-30 buttons own the scale.
                baseDurationMinutes: nil,
                locationType: locationType,
                locationLabel: locationType == .fixed && !locationLabel.isEmpty ? locationLabel : nil,
                locationCoordinate: coordinate,
                isActive: true,
                commentsEnabled: commentsEnabled,
                imageURL: finalImageURL
            )
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}