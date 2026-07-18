import Foundation

extension Strings {
    enum Profile {
        static let title = "Profile"
        static let preferencesSection = "Preferences"
        static let eventRadiusFilter = "Event radius filter"
        static let signOut = "Sign Out"
        static let edit = "Edit"
        static let editProfileTitle = "Edit Profile"
        static let displayNameSection = "Display Name"
        static let displayNamePlaceholder = "Display name"
        static let radiusTitle = "Event Radius"
        static let noLimit = "No limit"

        static func photoUploadFailed(_ message: String) -> String {
            "Photo upload failed: \(message)"
        }

        static func milesLabel(_ n: Int) -> String {
            "\(n) miles"
        }
    }
}
