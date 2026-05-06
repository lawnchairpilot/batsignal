import SwiftUI

struct PhoneEntryView: View {
    @ObservedObject var viewModel: AuthViewModel
    var onCodeSent: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("What's your number?")
                .font(.title2).bold()

            TextField("+1 (555) 000-0000", text: $viewModel.phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red).font(.caption)
            }

            Button(action: {
                Task {
                    await viewModel.sendCode()
                    if viewModel.verificationID != nil { onCodeSent() }
                }
            }) {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Send Code")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.phoneNumber.isEmpty || viewModel.isLoading)
        }
        .padding()
    }
}
