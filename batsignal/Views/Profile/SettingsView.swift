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
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false

    // Matches the event form's preview circle so the two photo pickers read as
    // the same control.
    private let photoSize: CGFloat = 220
    private let pencilWidth: CGFloat = 14

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
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
                                    size: photoSize
                                )
                            }
                        }
                        .frame(width: photoSize, height: photoSize)
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
                                .font(.largeTitle)
                                .foregroundStyle(.white, Color.accentColor)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                        }
                        .disabled(isUploadingPhoto)
                        // The corner of the frame is off the circle at this
                        // size, so the badge gets pulled back onto its edge.
                        .offset(x: -photoSize * 0.07, y: -photoSize * 0.07)
                    }

                    nameField
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)
            }

            Section {
                NavigationLink(Strings.Profile.eventRadiusFilter) {
                    RadiusSettingView()
                }
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
                .disabled(isDeletingAccount)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text(Strings.Profile.deleteAccount)
                        if isDeletingAccount {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeletingAccount)
            }
        }
        // Deleting is irreversible, so it takes a deliberate second tap, and the
        // alert spells out what goes with the account.
        .alert(Strings.Profile.deleteAccountTitle, isPresented: $showDeleteConfirmation) {
            Button(Strings.Common.cancel, role: .cancel) {}
            Button(Strings.Profile.deleteAccountConfirm, role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text(Strings.Profile.deleteAccountMessage)
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

    // Sits under the photo as the heading for the screen rather than in a row
    // of its own, so the pencil is what says it's editable. The field hugs its
    // text to keep the two together as the name changes length.
    private var nameField: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: pencilWidth)

            TextField(Strings.Profile.displayNamePlaceholder, text: $displayName)
                .font(.title2).bold()
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .fixedSize()
                .textContentType(.name)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit { commitDisplayName() }

            // Balances the pencil so what's centered under the photo is the
            // name itself, with the pencil hanging off its side.
            Color.clear.frame(width: pencilWidth, height: 1)
        }
        // The pencil is a label, not a button, so the whole pairing takes the
        // tap and hands it to the field.
        .contentShape(Rectangle())
        .onTapGesture { isNameFocused = true }
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

    // On success the auth state changes out from under this screen and the app
    // returns to the sign-in flow, so there's nothing to reset afterwards.
    private func deleteAccount() async {
        isDeletingAccount = true
        errorMessage = nil
        do {
            try await authService.deleteAccount()
        } catch {
            errorMessage = Strings.Profile.accountDeletionFailed(error.localizedDescription)
            isDeletingAccount = false
        }
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
