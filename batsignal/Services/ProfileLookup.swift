import Foundation
import FirebaseFunctions

// Profiles the signed-in user has no direct read access to. A `users` document
// is readable only by its owner and that owner's friends (firestore.rules), so
// the people on a friend request, the people who joined someone else's signal,
// and the contacts who turn out to have accounts all come through the callables
// in functions/src/index.ts, which decide server-side what this caller may see.
enum ProfileLookup {

    static func profiles(userIds: [String], eventId: String? = nil) async throws -> [PublicProfile] {
        guard !userIds.isEmpty else { return [] }
        var payload: [String: Any] = ["userIds": userIds]
        if let eventId { payload["eventId"] = eventId }
        return try await call("getProfiles", payload: payload)
    }

    static func profiles(phoneNumbers: [String]) async throws -> [PublicProfile] {
        guard !phoneNumbers.isEmpty else { return [] }
        return try await call("findUsersByPhoneNumbers", payload: ["phoneNumbers": phoneNumbers])
    }

    // The untyped callable API rather than the Codable one, so the decode is
    // ours and a field the server stops sending reads as nil instead of
    // failing the whole call.
    private static func call(_ name: String, payload: [String: Any]) async throws -> [PublicProfile] {
        let result = try await Functions.functions().httpsCallable(name).call(payload)
        guard let body = result.data as? [String: Any], let raw = body["profiles"] else { return [] }
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode([PublicProfile].self, from: data)
    }
}
