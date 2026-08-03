import UIKit
import FirebaseStorage
import FirebaseAuth

struct PhotoStorageService {

    func uploadProfilePhoto(_ image: UIImage) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }
        return try await upload(image, to: "profile-photos/\(uid)/profile.jpg")
    }

    func uploadEventImage(_ image: UIImage) async throws -> String {
        guard Auth.auth().currentUser != nil else {
            throw URLError(.userAuthenticationRequired)
        }
        return try await upload(image, to: "event-photos/\(UUID().uuidString).jpg")
    }

    // MARK: - Private

    private func upload(_ image: UIImage, to path: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotCreateFile)
        }

        let ref = Storage.storage().reference().child(path)
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
