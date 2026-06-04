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
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
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

    // MARK: - Email Auth (temporary, replace with phone auth before shipping)

    func signUp(email: String, password: String) async throws {
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - User Document

    func createUserDocument(email: String, phoneNumber: String, displayName: String) async throws {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let user = User(
            phoneNumber: phoneNumber,
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
