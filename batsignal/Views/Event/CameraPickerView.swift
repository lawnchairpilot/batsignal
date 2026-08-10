import SwiftUI
import UIKit

// Shoot, then frame — one presentation with two steps. The crop screen used to
// be a fixed circle drawn over the viewfinder, which meant composing the shot
// blind and living with whatever the centre of the frame caught.
struct CameraCaptureFlow: View {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var captured: UIImage?

    var body: some View {
        if let captured {
            CircleCropView(
                image: captured,
                // Backing out of the crop returns to the camera for another
                // try rather than throwing the whole thing away.
                onCancel: { self.captured = nil },
                onConfirm: { image in
                    onCapture(image)
                    dismiss()
                }
            )
        } else {
            CameraPickerView(image: $captured)
                .ignoresSafeArea()
        }
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        // Hands back the full frame and stays put: whoever presented this
        // decides what happens next, and dismissing here would take the crop
        // step down with it.
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
