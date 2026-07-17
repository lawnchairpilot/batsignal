import Contacts
import FirebaseFirestore

struct ContactMatch: Identifiable {
    var id: String { user.id ?? user.phoneNumber }
    let contactName: String
    let user: User
}

final class ContactsService {
    private let db = Firestore.firestore()

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

        // Firestore `in` supports up to 30 values per query
        var users: [User] = []
        for chunk in stride(from: 0, to: allPhones.count, by: 30).map({ Array(allPhones[$0 ..< min($0 + 30, allPhones.count)]) }) {
            let snapshot = try await db.collection("users")
                .whereField("phoneNumber", in: chunk)
                .getDocuments()
            users.append(contentsOf: snapshot.documents.compactMap { try? $0.data(as: User.self) })
        }

        return users
            .filter { $0.id != currentUserId }
            .compactMap { user in
                guard let name = phoneToName[user.phoneNumber] else { return nil }
                return ContactMatch(contactName: name, user: user)
            }
            .sorted { $0.contactName < $1.contactName }
    }
}
