import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// The agreement Apple requires before anyone can post: a zero-tolerance
// statement, shown once and recorded on the user document. Accounts made before
// this existed have no acceptedTermsAt, which is what routes them through here
// on their next launch rather than only catching new signups.
struct CommunityRulesView: View {
    // No completion handler: AuthService keeps a listener on the user document,
    // so writing the timestamp is what moves the app past this screen.
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Strings.Moderation.termsTitle)
                        .font(.title2.bold())

                    Text(Strings.Moderation.termsBody)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // TODO: point these at the hosted documents once they're
                    // live — App Store Connect needs the same two URLs.
                    HStack(spacing: 4) {
                        Text(Strings.Moderation.termsFooter)
                        Link(Strings.Moderation.termsLinkTerms, destination: Self.termsURL)
                        Text("&")
                        Link(Strings.Moderation.termsLinkPrivacy, destination: Self.privacyURL)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }

            Button(action: accept) {
                HStack {
                    Spacer()
                    Text(Strings.Moderation.termsAgree).bold()
                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
            .padding(24)
        }
    }

    static let termsURL = URL(string: "https://boolsignal.app/terms")!
    static let privacyURL = URL(string: "https://boolsignal.app/privacy")!

    private func accept() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await Firestore.firestore().collection("users").document(uid).updateData([
                    "acceptedTermsAt": Timestamp(date: Date())
                ])
            } catch {
                errorMessage = Strings.Moderation.termsFailed
            }
            isSaving = false
        }
    }
}
