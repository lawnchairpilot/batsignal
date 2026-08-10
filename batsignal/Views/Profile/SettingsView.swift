import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth

// Pushed from the profile screen's gear button, so like ProfileView it borrows
// the home screen's navigation stack instead of starting one of its own.
struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @FocusState private var isNameFocused: Bool

    @State private var displayName = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var cropCandidate: CropCandidate?
    @State private var previewImage: UIImage?
    @State private var isUploadingPhoto = false
    @State private var errorMessage: String?

    var body: some View {
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
                        .overlay {
                            if isUploadingPhoto {
                                ZStack {
                                    Circle().fill(.black.opacity(0.4))
                                    ProgressView().tint(.white)
                                }
                            }
                        }

                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Image(systemName: "camera.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white, Color.accentColor)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                        }
                        .disabled(isUploadingPhoto)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)
            }

            Section(Strings.Profile.displayNameSection) {
                TextField(Strings.Profile.displayNamePlaceholder, text: $displayName)
                    .textContentType(.name)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitDisplayName() }
            }

            if let error = errorMessage {
                Section {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }

            Section {
                Button(Strings.Profile.signOut, role: .destructive) {
                    try? authService.signOut()
                }
            }
        }
        .navigationTitle(Strings.Profile.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            displayName = authService.currentUser?.displayName ?? ""
        }
        // Tapping out of the field counts as committing it, so the name
        // doesn't need the return key to stick.
        .onChange(of: isNameFocused) { _, focused in
            if !focused { commitDisplayName() }
        }
        // Backing out is the other way to leave the field, and that doesn't
        // always unfocus first.
        .onDisappear { commitDisplayName() }
        .onChange(of: selectedItem) { _, item in
            Task { await loadForCropping(item) }
        }
        .fullScreenCover(item: $cropCandidate) { candidate in
            CircleCropView(
                image: candidate.image,
                onCancel: { cropCandidate = nil },
                onConfirm: { cropped in
                    cropCandidate = nil
                    previewImage = cropped
                    Task { await uploadPhoto(cropped) }
                }
            )
        }
    }

    private var initials: String? {
        guard !displayName.isEmpty else { return nil }
        let parts = displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return parts.isEmpty ? nil : parts.uppercased()
    }

    // Writes only when the name actually changed, so a tap through the field or
    // a Done on an untouched sheet doesn't cost a Firestore write. An empty
    // field isn't a name — it snaps back to what's saved.
    private func commitDisplayName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = authService.currentUser?.displayName ?? ""
        guard !trimmed.isEmpty else {
            displayName = current
            return
        }
        displayName = trimmed
        guard trimmed != current else { return }
        save(["displayName": trimmed])
    }

    // Nothing is uploaded straight off the picker — the photo goes to the crop
    // screen first, and only what comes back from there is saved.
    private func loadForCropping(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        // Cleared so that picking the same photo again still counts as a change
        // and reopens the crop screen.
        selectedItem = nil
        cropCandidate = CropCandidate(image: image)
    }

    private func uploadPhoto(_ image: UIImage) async {
        isUploadingPhoto = true
        errorMessage = nil
        do {
            let url = try await PhotoStorageService().uploadProfilePhoto(image)
            save(["profilePhotoURL": url])
        } catch {
            // Drop the preview so the avatar goes back to showing what's
            // actually stored rather than a photo that never landed.
            previewImage = nil
            errorMessage = Strings.Profile.photoUploadFailed(error.localizedDescription)
        }
        isUploadingPhoto = false
    }

    private func save(_ updates: [String: Any]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        errorMessage = nil
        Task {
            do {
                try await Firestore.firestore().collection("users").document(uid).updateData(updates)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// A picked photo waiting to be framed. Wrapped because fullScreenCover(item:)
// wants something identifiable, and a fresh id per pick is what reopens the
// crop screen for the same photo twice.
private struct CropCandidate: Identifiable {
    let id = UUID()
    let image: UIImage
}
