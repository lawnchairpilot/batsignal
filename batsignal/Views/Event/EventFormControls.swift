import SwiftUI
import UIKit
import CoreLocation

// Large circular preview of how the event's icon will appear on the map, with
// camera/emoji selector buttons flanking it. Shared by the create and edit forms.
struct EventSymbolHeader: View {
    @Binding var selectedImage: UIImage?
    @Binding var emoji: String?
    @Binding var imageURL: String?
    /// 0 for the icon at rest, 1 for the icon lit — the send button drives this
    /// to 1 as the signal goes out, so the thing you built is briefly shown
    /// alight the way it will look on the map. Left at 0 by the edit forms,
    /// which aren't sending anything.
    var flare: Double = 0

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
                    }
                }
            } else if let photoURL = AuthService.shared.currentUser?.profilePhotoURL,
                      let url = URL(string: photoURL) {
                // Nothing picked, so the preview shows what the pin is actually
                // going to fall back to rather than a mark of its own. The map
                // hands EventIconView the creator's photo whenever a signal
                // carries neither image nor emoji (see HomeView's
                // annotationPhotoURL), and EventIconView draws a photo in
                // preference to a label — so a photo outranks initials here too.
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        creatorFallback(size: size)
                    }
                }
            } else {
                creatorFallback(size: size)
            }
        }
        .frame(width: size, height: size)
        // Lights from the inside as the signal goes out. An inner bloom rather
        // than a shadow because of the clipping described below: it's drawn
        // before the clipShape, so it's bounded by the circle itself and there
        // is nothing for the row to slice off. Its own blur is what softens it
        // into light instead of a second ring.
        .overlay(
            Circle()
                .strokeBorder(Blipper.amber, lineWidth: size * 0.09)
                .blur(radius: size * 0.05)
                .opacity(flare)
        )
        .clipShape(Circle())
        // This is the event's own icon being composed, so it wears the signal
        // style the finished pin does — amber fill and amber ring — rather than
        // a neutral hairline.
        //
        // No haze here at rest, though the map pin has one. A shadow draws
        // outside its view's bounds and a form row clips to them, and this
        // circle already fills its container to within the 12pt padding, so the
        // glow came out sliced flat top and bottom. Reserving room for it would
        // mean ~100pt more height on a form that can't scroll (see
        // CreateEventView), and shrinking the circle would break its match with
        // heroIconMaxSize.
        //
        // The flare gets one anyway, and pays for the room by shrinking the
        // circle as it lights: at full flare the circle gives back 4% of its
        // size, which is what the haze spreads into. That trade only holds for
        // the moment the view is on its way out, so the resting size — and its
        // match with heroIconMaxSize — is untouched.
        .overlay(Circle().strokeBorder(Blipper.amber, lineWidth: 2 + 2 * flare))
        .scaleEffect(1 - 0.04 * flare)
        .blipperGlow(Blipper.amber, radius: size * 0.12 * flare, opacity: 0.75 * flare)
    }

    private var imageThumbnail: some View {
        Image(systemName: "camera.fill")
            .font(.title3)
            .foregroundColor(.accentColor)
            .frame(width: buttonSize, height: buttonSize)
            .background(Blipper.surface)
            .clipShape(Circle())
    }

    // The last two rungs of the map pin's ladder, in the same order and at the
    // same proportions EventIconView uses, so what you compose against is what
    // gets drawn once the signal is out.
    @ViewBuilder
    private func creatorFallback(size: CGFloat) -> some View {
        if let initials = AuthService.shared.currentUser?.initials {
            Text(initials)
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(EventIconStyle.signal.content)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(EventIconStyle.signal.content.opacity(0.8))
        }
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
        textField.attributedPlaceholder = styledPlaceholder
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
        // Compared before assigning: rebuilding the attributed string on every
        // update pass would throw away the placeholder's layout mid-keystroke.
        if uiView.attributedPlaceholder?.string != placeholder {
            uiView.attributedPlaceholder = styledPlaceholder
        }
    }

    // Left to itself, UITextField draws its placeholder in UIColor.placeholderText
    // — a UIKit system grey that isn't in the palette at all, and which lands
    // dimmer and bluer on our surfaces than the theme's own quiet text. Setting
    // it explicitly puts the field's placeholder on the same muted grey as every
    // other piece of secondary text in the app.
    //
    // Colour only, deliberately: with no font attribute the field's own `font`
    // still applies, so this doesn't freeze the placeholder at the type size it
    // was built at and adjustsFontForContentSizeCategory goes on working.
    private var styledPlaceholder: NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(Blipper.textMuted)]
        )
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

// MARK: - Audience

// One circle-and-label tile in the row of people a signal can go to. Lives here
// rather than beside the create form because the edit sheets show the same
// tiles, as a record of where a signal already went.
struct AudienceCard: View {
    let title: String
    let emoji: String?
    let systemImage: String
    let isSelected: Bool
    /// A card that reports a choice instead of offering one. Dimmed and inert,
    /// so it doesn't invite a tap that wouldn't do anything.
    var isReadOnly: Bool = false
    var action: () -> Void = {}

    private let circleSize: CGFloat = 56

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Blipper.surface)

                    if let emoji {
                        Text(emoji).font(.title2)
                    } else {
                        Image(systemName: systemImage)
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(width: circleSize, height: circleSize)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Blipper.hairline, lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                Text(title)
                    .font(.blipperUI(.caption1))
                    .fontWeight(.medium)
                    .foregroundColor(Blipper.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        // Held back rather than hidden: who a signal went to is worth seeing on
        // the edit sheet, but it isn't something that can be changed after the
        // fact, so the cards sit a step behind the controls around them.
        .opacity(isReadOnly ? 0.55 : 1)
        .disabled(isReadOnly)
    }
}

// The create form's audience picker shown as a record: the same row of cards,
// carrying only what was actually chosen, greyed and inert. Fetches the owner's
// groups itself so both edit sheets can drop it in and hand it nothing but the
// event.
struct EventAudienceSummary: View {
    let event: Event

    @State private var groups: [FriendGroup] = []

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if event.wentToAllFriends {
                        AudienceCard(
                            title: Strings.Event.allFriendsLabel,
                            emoji: nil,
                            systemImage: "person.3.fill",
                            isSelected: true,
                            isReadOnly: true
                        )
                    } else {
                        ForEach(groups) { group in
                            AudienceCard(
                                title: group.name,
                                emoji: group.emoji,
                                systemImage: "person.2.fill",
                                isSelected: true,
                                isReadOnly: true
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                // Leading rather than the picker's centred default: with only
                // the chosen cards left there are usually too few to fill the
                // row, and a couple of tiles adrift in the middle reads as a
                // layout accident.
                .frame(minWidth: geo.size.width, alignment: .leading)
            }
        }
        .frame(height: 100)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .task(id: event.id) { await load() }
    }

    private func load() async {
        // Owner rather than the signed-in user: it's the same person on an edit
        // sheet, and taking it off the event keeps this from needing auth.
        guard !event.wentToAllFriends else { return }
        let owned = (try? await GroupService().fetchGroups(ownerId: event.creatorId)) ?? []
        groups = event.audienceGroups(from: owned)
    }
}
