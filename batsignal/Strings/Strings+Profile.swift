import Foundation

extension Strings {
    enum Profile {
        static let title = "Profile"
        static let eventRadiusFilter = "Bool radius"
        static let signOut = "Sign Out"
        static let settingsTitle = "Settings"
        static let cropTitle = "Move and Scale"
        static let choosePhoto = "Choose"
        static let displayNameSection = "Display Name"
        static let displayNamePlaceholder = "Display name"
        static let radiusTitle = "Bool Radius"
        static let noLimit = "No limit"

        static let deleteAccount = "Delete Account"
        static let deleteAccountTitle = "Delete Account?"
        static let deleteAccountMessage = """
            This permanently deletes your account, your profile, your signals, and \
            your friend connections. This can't be undone.
            """
        static let deleteAccountConfirm = "Delete"

        static func photoUploadFailed(_ message: String) -> String {
            "Photo upload failed: \(message)"
        }

        static func accountDeletionFailed(_ message: String) -> String {
            "Couldn't delete your account: \(message)"
        }

        static func milesLabel(_ n: Int) -> String {
            "\(n) miles"
        }
    }
}
