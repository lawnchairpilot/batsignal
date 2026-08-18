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
                Text(Strings.Common.appName)
                    .font(.blipperDisplay(.largeTitle, weight: 800))
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
        .blipperBackground()
        .animation(.easeInOut(duration: 0.2), value: viewModel.step)
    }

    // MARK: - Phone Entry

    private var phoneEntrySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.Auth.phoneEntryHeadline)
                    .font(.blipperUI(.title2, weight: 600))
                Text(Strings.Auth.phoneEntrySubtitle)
                    .font(.blipperUI(.subheadline))
                    .foregroundColor(Blipper.textMuted)
            }

            HStack(spacing: 0) {
                Text(Strings.Auth.countryCode)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Blipper.surfaceRaised)
                    .foregroundColor(Blipper.textPrimary)

                Rectangle()
                    .frame(width: 1, height: 24)
                    .foregroundColor(Blipper.hairline)

                TextField(Strings.Auth.phoneNumberPlaceholder, text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .onChange(of: viewModel.phoneNumber) { _, newValue in
                        viewModel.phoneNumber = formatPhoneInput(newValue)
                    }
            }
            .background(Blipper.surface)
            .cornerRadius(12)

            errorText

            Button(action: { Task { await viewModel.sendCode() } }) {
                primaryButtonContent(label: Strings.Auth.sendCode)
            }
            .disabled(viewModel.isLoading || viewModel.phoneNumber.filter(\.isNumber).count < 10)
        }
    }

    // MARK: - Code Verification

    private var codeVerificationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.Auth.codeVerificationHeadline)
                    .font(.blipperUI(.title2, weight: 600))
                Text(Strings.Auth.sentToCode(viewModel.phoneNumber))
                    .font(.blipperUI(.subheadline))
                    .foregroundColor(Blipper.textMuted)
            }

            TextField(Strings.Auth.codePlaceholder, text: $viewModel.verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.blipperUI(.title2, weight: 500, monospacedDigits: true))
                .multilineTextAlignment(.center)
                .padding()
                .background(Blipper.surface)
                .cornerRadius(12)
                .onChange(of: viewModel.verificationCode) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    viewModel.verificationCode = String(digits.prefix(6))
                }

            errorText

            Button(action: { Task { await viewModel.verifyCode() } }) {
                primaryButtonContent(label: Strings.Auth.verify)
            }
            .disabled(viewModel.isLoading || viewModel.verificationCode.count < 6)

            Button(Strings.Auth.useDifferentNumber) {
                viewModel.editPhoneNumber()
            }
            .font(.blipperUI(.subheadline))
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared components

    @ViewBuilder
    private var errorText: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .foregroundColor(Blipper.roseBright)
                .font(.blipperUI(.caption1))
        }
    }

    private func primaryButtonContent(label: String) -> some View {
        Group {
            if viewModel.isLoading {
                ProgressView().tint(Blipper.onMoonlight)
            } else {
                Text(label).fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.accentColor)
        .foregroundColor(Blipper.onMoonlight)
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
