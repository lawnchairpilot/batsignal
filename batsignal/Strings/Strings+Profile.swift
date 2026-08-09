import Foundation

extension Strings {
    enum Profile {
        static let title = "Profile"
        static let eventRadiusFilter = "Bool radius"
        static let signOut = "Sign Out"
        static let settingsTitle = "Settings"
        static let displayNameSection = "Display Name"
        static let displayNamePlaceholder = "Display name"
        static let radiusTitle = "Bool Radius"
        static let noLimit = "No limit"

        static func photoUploadFailed(_ message: String) -> String {
            "Photo upload failed: \(message)"
        }

        static func milesLabel(_ n: Int) -> String {
            "\(n) miles"
        }
    }
}
