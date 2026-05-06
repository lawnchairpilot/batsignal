import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false

    static let shared = AuthService()
    private let db = Firestore.firestore()

    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            if let firebaseUser {
                self.isAuthenticated = true
                self.fetchUser(id: firebaseUser.uid)
            } else {
                self.isAuthenticated = false
                self.currentUser = nil
            }
        }
    }

    // MARK: - Phone Auth

    func sendVerificationCode(phoneNumber: String) async throws -> String {
        let verificationID = try await PhoneAuthProvider.provider()
            .verifyPhoneNumber(phoneNumber, uiDelegate: nil)
        return verificationID
    }

    func verifyCode(_ code: String, verificationID: String) async throws {
        let credential = PhoneAuthProvider.provider()
            .credential(withVerificationID: verificationID, verificationCode: code)
        try await Auth.auth().signIn(with: credential)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - User Document

    func createUserDocument(displayName: String) async throws {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let user = User(
            phoneNumber: firebaseUser.phoneNumber ?? "",
            displayName: displayName,
            friends: [],
            createdAt: .init()
        )
        try db.collection("users").document(firebaseUser.uid).setData(from: user)
    }

    private func fetchUser(id: String) {
        db.collection("users").document(id).addSnapshotListener { [weak self] snapshot, _ in
            self?.currentUser = try? snapshot?.data(as: User.self)
        }
    }
}
