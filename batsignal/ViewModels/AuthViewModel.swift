import Foundation
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""
    @Published var phoneNumber = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isNewUser = false  // toggle between sign up / sign in

    private let authService = AuthService.shared

    func signUp() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signUp(email: email, password: password)
            try await authService.createUserDocument(email: email, phoneNumber: phoneNumber, displayName: displayName)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signIn() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
