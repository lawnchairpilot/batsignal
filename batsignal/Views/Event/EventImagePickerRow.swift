import SwiftUI

// Shared image picker row used by the create and edit event forms.
// Camera-only: photos must be taken live, not chosen from the library.
struct EventImagePickerRow: View {
    @Binding var imageURL: String?
    @Binding var selectedImage: UIImage?
    @State private var showCamera = false

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

            Button(action: { showCamera = true }) {
                Text(selectedImage == nil && imageURL == nil ? Strings.Event.addImage : Strings.Event.changeImage)
                    .foregroundColor(.accentColor)
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            Spacer()

            if selectedImage != nil || imageURL != nil {
                Button(role: .destructive) {
                    selectedImage = nil
                    imageURL = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView(image: $selectedImage)
                .ignoresSafeArea()
        }
    }
}
