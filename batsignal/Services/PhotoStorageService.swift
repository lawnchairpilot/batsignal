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
        guard let uid = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }
        // Filed under the uploader so the upload is attributable: it's what lets
        // enforceUploadQuota count per account and cleanupOnUserDelete sweep by
        // prefix. The filename stays a UUID — the folder identifies who, not
        // which signal.
        return try await upload(image, to: "event-photos/\(uid)/\(UUID().uuidString).jpg")
    }

    // MARK: - Private

    // Longest edge worth storing. A photo appears in a card and a detail sheet,
    // so past this is resolution nobody ever sees — while a full 12MP frame at
    // 0.8 quality runs to several megabytes, which is most of what the storage
    // bill and the upload quota are defending against.
    private static let maxDimension: CGFloat = 2048

    private func downscaled(_ image: UIImage) -> UIImage {
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > Self.maxDimension else { return image }

        let ratio = Self.maxDimension / longestEdge
        let target = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)

        // scale = 1 so the result is `target` in pixels rather than in points
        // multiplied by whatever the screen happens to be.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func upload(_ image: UIImage, to path: String) async throws -> String {
        guard let data = downscaled(image).jpegData(compressionQuality: 0.8) else {
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
