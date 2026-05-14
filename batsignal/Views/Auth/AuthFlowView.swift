import SwiftUI

struct AuthFlowView: View {
    @StateObject private var viewModel = AuthViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(viewModel.isNewUser ? "Create Account" : "Sign In")
                    .font(.title2).bold()

                if viewModel.isNewUser {
                    TextField("Display name", text: $viewModel.displayName)
                        .textContentType(.name)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }

                TextField("Email", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                SecureField("Password", text: $viewModel.password)
                    .textContentType(viewModel.isNewUser ? .newPassword : .password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                if let error = viewModel.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption)
                }

                Button(action: {
                    Task {
                        if viewModel.isNewUser {
                            await viewModel.signUp()
                        } else {
                            await viewModel.signIn()
                        }
                    }
                }) {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text(viewModel.isNewUser ? "Sign Up" : "Sign In")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)

                Button(viewModel.isNewUser ? "Already have an account? Sign in" : "New here? Create an account") {
                    viewModel.isNewUser.toggle()
                    viewModel.errorMessage = nil
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
            .padding()
        }
    }
}
