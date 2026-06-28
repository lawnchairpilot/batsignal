import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth

struct EditProfileView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var phoneNumber = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let previewImage {
                                    Image(uiImage: previewImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    EventIconView(
                                        photoURL: authService.currentUser?.profilePhotoURL,
                                        label: initials,
                                        size: 80
                                    )
                                }
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())

                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white, Color.accentColor)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                }

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
            .onChange(of: selectedItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    previewImage = image
                }
            }
        }
    }

    private var initials: String? {
        guard !displayName.isEmpty else { return nil }
        let parts = displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return parts.isEmpty ? nil : parts.uppercased()
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        errorMessage = nil

        Task {
            var photoURL: String? = nil
            if let image = previewImage {
                do {
                    photoURL = try await PhotoStorageService().uploadProfilePhoto(image)
                } catch {
                    errorMessage = "Photo upload failed: \(error.localizedDescription)"
                    isLoading = false
                    return
                }
            }

            var updates: [String: Any] = [
                "displayName": displayName,
                "phoneNumber": phoneNumber
            ]
            if let url = photoURL {
                updates["profilePhotoURL"] = url
            }

            do {
                try await Firestore.firestore().collection("users").document(uid).updateData(updates)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}