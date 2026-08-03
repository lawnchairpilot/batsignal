import SwiftUI
import PhotosUI

// Shared image picker row used by the create and edit event forms.
struct EventImagePickerRow: View {
    @Binding var imageURL: String?
    @Binding var selectedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                } else if let imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").foregroundColor(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(action: { showCamera = true }) {
                        Label(Strings.Event.takePhoto, systemImage: "camera")
                    }
                }
                Button(action: { showPhotoLibrary = true }) {
                    Label(Strings.Event.chooseFromLibrary, systemImage: "photo.on.rectangle")
                }
            } label: {
                Text(selectedImage == nil && imageURL == nil ? Strings.Event.addImage : Strings.Event.changeImage)
                    .foregroundColor(.accentColor)
            }

            Spacer()

            if selectedImage != nil || imageURL != nil {
                Button(role: .destructive) {
                    selectedImage = nil
                    imageURL = nil
                    selectedPhotoItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                selectedImage = image
            }
        }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhotoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView(image: $selectedImage)
                .ignoresSafeArea()
        }
    }
}
