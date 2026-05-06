import Foundation
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var phoneNumber = ""
    @Published var otpCode = ""
    @Published var displayName = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var verificationID: String?

    private let authService = AuthService.shared

    func sendCode() async {
        isLoading = true
        errorMessage = nil
        do {
            verificationID = try await authService.sendVerificationCode(phoneNumber: phoneNumber)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func verifyCode() async {
        guard let verificationID else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await authService.verifyCode(otpCode, verificationID: verificationID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createProfile() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.createUserDocument(displayName: displayName)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
