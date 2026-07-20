import Foundation

extension Strings {
    enum Event {
        // Section headers
        static let whatAreYouDoingSection = "What are you doing?"
        static let whenSection = "When?"
        static let whereSection = "Where?"
        static let timeSection = "Time"

        // Fields
        static let activityPlaceholder = "e.g. Surfing, Hiking, Coffee"
        static let activityFieldLabel = "Activity"
        static let descriptionPlaceholder = "Description (optional)"
        static let emojiFieldLabel = "Emoji"
        static let noneSelected = "None"
        static let dayPickerLabel = "Day"
        static let timePickerLabel = "Time"
        static let durationPickerLabel = "Duration"
        static let whenPickerLabel = "When"
        static let locationTypePickerLabel = "Location type"
        static let liveLocation = "Share Location"
        static let fixedPlace = "Drop a Pin"
        static let describeIt = "Describe it"
        static let locationDescriptionPlaceholder = "Describe the location"
        static let pickLocationOnMap = "Pick a location on the map"

        // Titles & actions
        static let newSignalTitle = "New Signal"
        static let send = "Send"
        static let editSignalTitle = "Edit Signal"
        static let yourSignalTitle = "Your Signal"
        static let cancelEvent = "Cancel Event"
        static let endSignal = "End Signal"
        static let started = "Started"
        static let add30Minutes = "Add 30 minutes"

        // Detail view
        static let timeLabel = "Time"
        static let locationLabel = "Location"
        static let waitingForLocation = "Waiting for location…"
        static let live = "LIVE"
        static let openInMaps = "Open in Maps"

        // Location picker
        static let pickLocationTitle = "Pick a Location"
        static let selectedPlace = "Selected place"
        static let searchPlaceholder = "Search for a place..."
        static let unknownPlaceName = "Unknown"
        static let droppedPin = "Dropped Pin"
        static let nameLocationPlaceholder = "Name this location (optional)"

        // Emoji picker
        static let chooseEmojiTitle = "Choose Emoji"
        static let remove = "Remove"

        // Errors
        static let startTimeInPast = "Start time cannot be in the past."

        static func tomorrowAt(_ time: String) -> String {
            "Tomorrow · \(time)"
        }
    }
}
