import Foundation

extension Strings {
    enum Event {
        // Fields
        static let activityPlaceholder = "Answer the call"
        static let durationPickerLabel = "Duration"
        static let locationTypePickerLabel = "Location type"
        static let liveLocation = "Share Location"
        static let fixedPlace = "Drop a Pin"
        static let allFriendsLabel = "All Friends"
        static let sentToLabel = "Sent to"
        static let pickLocationOnMap = "Pick a location on the map"
        static let addImage = "Add Image"
        static let changeImage = "Change Image"
        static let removeImage = "Remove Image"

        static func imageUploadFailed(_ message: String) -> String {
            "Image upload failed: \(message)"
        }

        // Titles & actions
        static let sendSignal = "Send Signal"
        static let editSignalTitle = "Edit Signal"
        static let yourSignalTitle = "Your Signal"
        static let cancelEvent = "Cancel Event"
        static let endSignal = "End Signal"

        // Detail view
        static let timeLabel = "Time"
        static let locationLabel = "Location"
        static let waitingForLocation = "Waiting for location…"
        static let liveLocationLabel = "Live location"
        static let live = "LIVE"
        static let openInMaps = "Open in Maps"
        static let eventEnded = "Event ended"

        static let timeLeftCaption = "left to bool"
        static let join = "Join the Bool"
        static let joined = "Bool Joined"

        static func goingCount(_ count: Int) -> String {
            count == 1 ? "1 additional booler" : "\(count) additional boolers"
        }

        // Comments
        static let commentsSection = "Comments"
        static let commentsToggleLabel = "Enable Comments"
        static let commentPlaceholder = "Add a comment..."
        static let noComments = "No comments yet"

        // Location picker
        static let pickLocationTitle = "Pick a Location"
        static let selectedPlace = "Selected place"
        static let searchPlaceholder = "Search for a place..."
        static let unknownPlaceName = "Unknown"
        static let droppedPin = "Dropped Pin"
        static let nameLocationPlaceholder = "Name this location (optional)"
        static let currentLocation = "Current Location"

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
