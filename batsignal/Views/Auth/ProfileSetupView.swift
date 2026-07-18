import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var authService: AuthService
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                Text(Strings.Common.appName)
                    .font(.largeTitle).bold()
            }
            .padding(.top, 60)
            .padding(.bottom, 48)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Strings.Auth.setUpProfileHeadline)
                        .font(.title2).bold()
                    Text(Strings.Auth.setUpProfileSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                TextField(Strings.Auth.displayNamePlaceholder, text: $displayName)
                    .textContentType(.name)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button(action: { Task { await createProfile() } }) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(Strings.Auth.continueLabel).fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func createProfile() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.createUserDocument(displayName: displayName.trimmingCharacters(in: .whitespaces))
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
