import Contacts

struct ContactMatch: Identifiable {
    var id: String { user.id }
    let contactName: String
    let user: PublicProfile
}

final class ContactsService {

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async -> Bool {
        do {
            return try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    func fetchMatchedUsers(excludingId currentUserId: String?) async throws -> [ContactMatch] {
        let keysToFetch = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey
        ] as [CNKeyDescriptor]

        var phoneToName: [String: String] = [:]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            for phone in contact.phoneNumbers {
                if let normalized = PhoneNumber.normalize(phone.value.stringValue) {
                    phoneToName[normalized] = name
                }
            }
        }

        let allPhones = Array(phoneToName.keys)
        guard !allPhones.isEmpty else { return [] }

        // The matching happens server-side (findUsersByPhoneNumbers in
        // functions/src/index.ts). The numbers still leave the device, but what
        // comes back is a name and a photo rather than whole user documents,
        // and the query can't be pointed at anything else.
        let profiles = try await ProfileLookup.profiles(phoneNumbers: allPhones)

        return profiles
            .filter { $0.id != currentUserId }
            .compactMap { profile in
                guard let phoneNumber = profile.phoneNumber,
                      let name = phoneToName[phoneNumber] else { return nil }
                return ContactMatch(contactName: name, user: profile)
            }
            .sorted { $0.contactName < $1.contactName }
    }
}
