import SwiftUI
import UIKit
import CoreLocation

// Large circular preview of how the event's icon will appear on the map, with
// camera/emoji selector buttons flanking it. Shared by the create and edit forms.
struct EventSymbolHeader: View {
    @Binding var selectedImage: UIImage?
    @Binding var emoji: String?
    @Binding var imageURL: String?

    @State private var showEmojiPicker = false
    @State private var showCamera = false

    private let maxPreviewSize: CGFloat = 220
    private let minPreviewSize: CGFloat = 140
    private let buttonSize: CGFloat = 44
    private let spacing: CGFloat = 28

    private var hasImage: Bool {
        selectedImage != nil || imageURL != nil
    }

    private func previewSize(for availableWidth: CGFloat) -> CGFloat {
        let reserved = buttonSize * 2 + spacing * 2
        return min(maxPreviewSize, max(minPreviewSize, availableWidth - reserved))
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: spacing) {
                imageButton
                previewCircle(size: previewSize(for: geo.size.width))
                emojiButton
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: maxPreviewSize)
        .padding(.vertical, 12)
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerView(selectedEmoji: $emoji)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureFlow { image in selectedImage = image }
        }
        .onChange(of: selectedImage) { _, newImage in
            if newImage != nil { emoji = nil }
        }
        .onChange(of: emoji) { _, newEmoji in
            if newEmoji != nil {
                selectedImage = nil
                imageURL = nil
            }
        }
    }

    private func previewCircle(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(EventIconStyle.signal.fill)

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
            } else if let emoji {
                Text(emoji)
                    .font(.system(size: size * 0.45))
            } else if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallbackIcon(size: size)
                    }
                }
            } else {
                fallbackIcon(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // This is the event's own icon being composed, so it wears the signal
        // style the finished pin does — amber fill, amber ring, and the same
        // haze — rather than a neutral hairline.
        .overlay(Circle().strokeBorder(Blipper.amber, lineWidth: 2))
        .blipperGlow(Blipper.amber, radius: size * 0.16)
    }

    private func fallbackIcon(size: CGFloat) -> some View {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: size * 0.3))
            .foregroundColor(EventIconStyle.signal.content.opacity(0.8))
    }

    private var imageThumbnail: some View {
        Image(systemName: "camera.fill")
            .font(.title3)
            .foregroundColor(.accentColor)
            .frame(width: buttonSize, height: buttonSize)
            .background(Blipper.surface)
            .clipShape(Circle())
    }

    private var imageButton: some View {
        Group {
            if hasImage {
                Menu {
                    Button(action: { showCamera = true }) {
                        Label(Strings.Event.changeImage, systemImage: "camera")
                    }
                    Button(role: .destructive) {
                        selectedImage = nil
                        imageURL = nil
                    } label: {
                        Label(Strings.Event.removeImage, systemImage: "trash")
                    }
                } label: {
                    imageThumbnail
                }
            } else {
                Button(action: { showCamera = true }) {
                    imageThumbnail
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emojiButton: some View {
        Button(action: { showEmojiPicker = true }) {
            Image(systemName: "face.smiling")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: buttonSize, height: buttonSize)
                .background(Blipper.surface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// Tactile scrolling wheel for picking an event's duration. Shared by the
// create and edit forms.
struct EventDurationWheel: View {
    @Binding var durationMinutes: Int?
    @Binding var vagueLabel: String?

    var body: some View {
        Picker(Strings.Event.durationPickerLabel, selection: selectionBinding) {
            ForEach(Event.durationOptions, id: \.minutes) { option in
                Text(option.label).tag(option.label)
            }
            ForEach(Event.vagueOptions, id: \.self) { label in
                Text(label).tag(label)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding(.horizontal, 40)
        .clipped()
    }

    private var currentLabel: String {
        if let durationMinutes {
            return Event.durationOptions.first { $0.minutes == durationMinutes }?.label ?? ""
        }
        return vagueLabel ?? ""
    }

    // Maps the picker's selection (a label string) back to the two duration fields.
    private var selectionBinding: Binding<String> {
        Binding(
            get: { currentLabel },
            set: { label in
                if let option = Event.durationOptions.first(where: { $0.label == label }) {
                    durationMinutes = option.minutes
                    vagueLabel = nil
                } else {
                    durationMinutes = nil
                    vagueLabel = label
                }
            }
        )
    }
}

// Live-location vs. fixed-pin picker, shared by the edit forms (create events
// are always live).
struct EventLocationField: View {
    @Binding var locationType: LocationType
    @Binding var locationLabel: String
    @Binding var fixedCoordinate: CLLocationCoordinate2D?
    var showError: Bool = false

    @State private var showLocationPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(Strings.Event.locationTypePickerLabel, selection: $locationType) {
                Text(Strings.Event.liveLocation).tag(LocationType.live)
                Text(Strings.Event.fixedPlace).tag(LocationType.fixed)
            }
            .pickerStyle(.segmented)

            if locationType == .fixed {
                Button(action: { showLocationPicker = true }) {
                    HStack {
                        Image(systemName: "mappin.circle")
                            .foregroundColor(showError ? Blipper.roseBright : Color.accentColor)
                        if locationLabel.isEmpty {
                            Text(Strings.Event.pickLocationOnMap)
                                .foregroundColor(showError ? Blipper.roseBright : Blipper.textMuted)
                        } else {
                            Text(locationLabel)
                                .foregroundColor(Blipper.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.blipperUI(.caption1))
                            .foregroundColor(Blipper.textMuted)
                    }
                }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView { picked in
                locationLabel = picked.name
                fixedCoordinate = picked.coordinate
            }
        }
    }
}

// The activity field on every event form. A UITextField rather than SwiftUI's
// TextField because the placeholder and the text both have to sit centered,
// which SwiftUI's own field won't do for the placeholder.
struct CenteredTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.textAlignment = .center
        textField.placeholder = placeholder
        textField.text = text
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.tintColor = UIColor(Color.accentColor)
        textField.returnKeyType = .done
        textField.delegate = context.coordinator
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: CenteredTextField

        init(_ parent: CenteredTextField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        // A UITextField does nothing on return unless its delegate resigns it,
        // which is why this field alone couldn't be dismissed with the keyboard's
        // return key the way SwiftUI's own TextField can.
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
