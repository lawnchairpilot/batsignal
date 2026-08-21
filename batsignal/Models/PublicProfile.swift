import Foundation

// The part of a profile anyone is allowed to see: enough to put a name and a
// face on screen, and nothing more. These arrive from the getProfiles and
// findUsersByPhoneNumbers callables rather than from a direct read, because a
// `users` document is readable only by its owner and that owner's friends.
struct PublicProfile: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let profilePhotoURL: String?
    // Only the phone-number lookup fills this in, and only by echoing back a
    // number the caller supplied in the first place.
    let phoneNumber: String?

    init(
        id: String,
        displayName: String,
        profilePhotoURL: String? = nil,
        phoneNumber: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.profilePhotoURL = profilePhotoURL
        self.phoneNumber = phoneNumber
    }

    var initials: String? { Self.initials(from: displayName) }

    // Up to two letters, for avatars with no photo to show.
    static func initials(from displayName: String) -> String? {
        guard !displayName.isEmpty else { return nil }
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? nil : letters.uppercased()
    }
}

extension User {
    // For the screens that show friends and strangers side by side and only
    // need the public half of either.
    var publicProfile: PublicProfile {
        PublicProfile(
            id: id ?? "",
            displayName: displayName,
            profilePhotoURL: profilePhotoURL,
            phoneNumber: phoneNumber
        )
    }
}
