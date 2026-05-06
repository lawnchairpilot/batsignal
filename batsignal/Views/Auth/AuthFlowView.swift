import SwiftUI

struct AuthFlowView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var step: Step = .phone

    enum Step { case phone, otp, profile }

    var body: some View {
        NavigationStack {
            switch step {
            case .phone:
                PhoneEntryView(viewModel: viewModel) { step = .otp }
            case .otp:
                OTPVerificationView(viewModel: viewModel)
                    .onChange(of: viewModel.verificationID) { _, _ in
                        // Firebase auth state listener in AuthService handles transition
                    }
            case .profile:
                ProfileSetupView(viewModel: viewModel)
            }
        }
    }
}
