import Foundation
import Combine

enum AuthStep {
    case phoneEntry
    case codeVerification
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var phoneNumber = ""
    @Published var verificationCode = ""
    @Published var step: AuthStep = .phoneEntry
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var verificationID: String?
    private let authService = AuthService.shared

    func sendCode() async {
        let digits = phoneNumber.filter(\.isNumber)
        guard digits.count == 10 else {
            errorMessage = "Please enter a valid 10-digit US phone number."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            verificationID = try await authService.sendVerificationCode(to: "+1\(digits)")
            step = .codeVerification
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func verifyCode() async {
        guard let verificationID else { return }
        let code = verificationCode.filter(\.isNumber)
        guard code.count == 6 else {
            errorMessage = "Please enter the 6-digit code."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            try await authService.verifyCode(code, verificationID: verificationID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func editPhoneNumber() {
        step = .phoneEntry
        verificationCode = ""
        errorMessage = nil
        verificationID = nil
    }
}
