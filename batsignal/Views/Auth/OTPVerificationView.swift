import SwiftUI

struct OTPVerificationView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Enter the code")
                .font(.title2).bold()
            Text("Sent to \(viewModel.phoneNumber)")
                .foregroundColor(.secondary)

            TextField("000000", text: $viewModel.otpCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red).font(.caption)
            }

            Button(action: {
                Task { await viewModel.verifyCode() }
            }) {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Verify")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.otpCode.count < 6 || viewModel.isLoading)
        }
        .padding()
    }
}
