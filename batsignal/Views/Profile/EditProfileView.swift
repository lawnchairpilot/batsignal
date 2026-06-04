import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct EditProfileView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var phoneNumber = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                }

                Section("Phone Number") {
                    TextField("e.g. +16505551234", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isLoading { ProgressView() } else { Text("Save") }
                    }
                    .disabled(displayName.isEmpty || isLoading)
                }
            }
            .onAppear {
                displayName = authService.currentUser?.displayName ?? ""
                phoneNumber = authService.currentUser?.phoneNumber ?? ""
            }
        }
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        errorMessage = nil
        Firestore.firestore().collection("users").document(uid).updateData([
            "displayName": displayName,
            "phoneNumber": phoneNumber
        ]) { error in
            isLoading = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                dismiss()
            }
        }
    }
}
