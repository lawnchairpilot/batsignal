import SwiftUI

struct AuthFlowView: View {
    @StateObject private var viewModel = AuthViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Branding
            VStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                Text("batsignal")
                    .font(.largeTitle).bold()
            }
            .padding(.top, 60)
            .padding(.bottom, 48)

            switch viewModel.step {
            case .phoneEntry:
                phoneEntrySection
            case .codeVerification:
                codeVerificationSection
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: viewModel.step)
    }

    // MARK: - Phone Entry

    private var phoneEntrySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What's your number?")
                    .font(.title2).bold()
                Text("We'll send a verification code to confirm it's you.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 0) {
                Text("+1")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color(.tertiarySystemBackground))
                    .foregroundColor(.primary)

                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color(.separator))
                    .padding(.vertical, 8)

                TextField("(555) 555-5555", text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .onChange(of: viewModel.phoneNumber) { _, newValue in
                        viewModel.phoneNumber = formatPhoneInput(newValue)
                    }
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            errorText

            Button(action: { Task { await viewModel.sendCode() } }) {
                primaryButtonContent(label: "Send Code")
            }
            .disabled(viewModel.isLoading || viewModel.phoneNumber.filter(\.isNumber).count < 10)
        }
    }

    // MARK: - Code Verification

    private var codeVerificationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter the code")
                    .font(.title2).bold()
                Text("Sent to +1 \(viewModel.phoneNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            TextField("6-digit code", text: $viewModel.verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .onChange(of: viewModel.verificationCode) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    viewModel.verificationCode = String(digits.prefix(6))
                }

            errorText

            Button(action: { Task { await viewModel.verifyCode() } }) {
                primaryButtonContent(label: "Verify")
            }
            .disabled(viewModel.isLoading || viewModel.verificationCode.count < 6)

            Button("Use a different number") {
                viewModel.editPhoneNumber()
            }
            .font(.subheadline)
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared components

    @ViewBuilder
    private var errorText: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
        }
    }

    private func primaryButtonContent(label: String) -> some View {
        Group {
            if viewModel.isLoading {
                ProgressView().tint(.white)
            } else {
                Text(label).fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.accentColor)
        .foregroundColor(.white)
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func formatPhoneInput(_ input: String) -> String {
        let digits = String(input.filter(\.isNumber).prefix(10))
        var result = ""
        for (i, char) in digits.enumerated() {
            if i == 0 { result.append("(") }
            if i == 3 { result.append(") ") }
            if i == 6 { result.append("-") }
            result.append(char)
        }
        return result
    }
}
