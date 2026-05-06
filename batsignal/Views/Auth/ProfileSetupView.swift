import SwiftUI

struct ProfileSetupView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("What should we call you?")
                .font(.title2).bold()

            TextField("Display name", text: $viewModel.displayName)
                .textContentType(.name)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red).font(.caption)
            }

            Button(action: {
                Task { await viewModel.createProfile() }
            }) {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Get Started")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.displayName.isEmpty || viewModel.isLoading)
        }
        .padding()
    }
}
