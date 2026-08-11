import Foundation
import Combine
import UIKit
import FirebaseAuth
import FirebaseFirestore

// Explicit AuthUIDelegate conformance — UIViewController's conformance is implicit
// in the Firebase SDK and the Swift compiler can't coerce UIViewController? to
// (any AuthUIDelegate)? across an optional chain without this bridge.
private final class PhoneAuthUIDelegate: NSObject, AuthUIDelegate {
    private weak var presenter: UIViewController?

    init(presenter: UIViewController) {
        self.presenter = presenter
    }

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        presenter?.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    func dismiss(animated flag: Bool, completion: (() -> Void)?) {
        presenter?.dismiss(animated: flag, completion: completion)
    }
}

class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var needsProfileSetup = false
    @Published var isLoadingUser = true

    static let shared = AuthService()
    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?

    private init() {
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            if let firebaseUser {
                self.isAuthenticated = true
                self.isLoadingUser = true
                self.fetchUser(id: firebaseUser.uid)
            } else {
                self.isAuthenticated = false
                self.currentUser = nil
                self.needsProfileSetup = false
                self.isLoadingUser = false
                self.userListener?.remove()
                self.userListener = nil
            }
        }
    }

    // MARK: - Phone Auth

    @MainActor
    func sendVerificationCode(to phoneNumber: String) async throws -> String {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let rootVC = windowScene?.keyWindow?.rootViewController
        let uiDelegate = rootVC.map { PhoneAuthUIDelegate(presenter: $0) }

        return try await withCheckedThrowingContinuation { continuation in
            PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: uiDelegate) { verificationID, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let verificationID {
                    continuation.resume(returning: verificationID)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "batsignal.auth", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No verification ID returned."]
                    ))
                }
            }
        }
    }

    func verifyCode(_ code: String, verificationID: String) async throws {
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        try await Auth.auth().signIn(with: credential)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // Deleting the user document is the whole trigger: the onUserDocumentDeleted
    // function (functions/src/index.ts) tears down everything the account leaves
    // behind — the events, groups, requests, photos, other people's friend lists
    // — and deletes the Firebase Auth user itself.
    //
    // The auth user is deleted server-side rather than here on purpose. A
    // client-side Auth.currentUser.delete() only works within a few minutes of
    // signing in, so a normal user would hit requiresRecentLogin and have to
    // re-verify their phone number just to leave.
    func deleteAccount() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "batsignal.auth", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "You're not signed in."]
            )
        }
        // Dropped first so the deletion doesn't momentarily read as a signed-in
        // user with no profile, which is what sends people to profile setup.
        userListener?.remove()
        userListener = nil
        try await db.collection("users").document(uid).delete()
        try Auth.auth().signOut()
    }

    // MARK: - User Document

    func createUserDocument(displayName: String) async throws {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let phoneNumber = firebaseUser.phoneNumber ?? ""
        let user = User(
            phoneNumber: phoneNumber,
            displayName: displayName,
            friends: [],
            createdAt: .init()
        )
        try db.collection("users").document(firebaseUser.uid).setData(from: user)
    }

    // MARK: - Private

    private func fetchUser(id: String) {
        userListener?.remove()
        userListener = db.collection("users").document(id).addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            if let user = try? snapshot?.data(as: User.self) {
                self.currentUser = user
                self.needsProfileSetup = false
            } else {
                self.currentUser = nil
                self.needsProfileSetup = true
            }
            self.isLoadingUser = false
        }
    }
}
