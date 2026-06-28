import UIKit
import FirebaseStorage
import FirebaseAuth

struct PhotoStorageService {

    func uploadProfilePhoto(_ image: UIImage) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotCreateFile)
        }

        let ref = Storage.storage().reference().child("profile-photos/\(uid)/profile.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        // Callback API wrapped in a continuation — reliably surfaces rule violations
        // and upload failures that putDataAsync can swallow in some SDK versions.
        return try await withCheckedThrowingContinuation { continuation in
            ref.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                ref.downloadURL { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
            }
        }
    }
}
