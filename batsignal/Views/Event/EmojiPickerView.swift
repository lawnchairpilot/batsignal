import SwiftUI

struct EmojiPickerView: View {
    @Binding var selectedEmoji: String?
    @Environment(\.dismiss) private var dismiss

    private let categories: [(name: String, emojis: [String])] = [
        ("Food & Drink", ["🍕", "🍔", "🌮", "🍜", "🍣", "🌯", "🍦", "🧁", "🍩", "🍺", "🍻", "🥂", "🍷", "☕", "🧋", "🥤", "🍸", "🍹"]),
        ("Activities",   ["🎮", "🎬", "🎵", "🎸", "🎤", "🎨", "📚", "🎲", "🎯", "🧩", "🎭", "🎪", "🎻", "🎹", "🎧"]),
        ("Sports",       ["🏀", "⚽", "🎾", "🏈", "⚾", "🏐", "🏋️", "🏃", "🚴", "🏊", "🏄", "🧘", "🥊", "🎿", "⛷️", "🧗"]),
        ("Outdoors",     ["🏖️", "🌄", "🌲", "🏔️", "🌅", "🌊", "🏕️", "🚵", "⛺", "🌻"]),
        ("Social",       ["🎉", "🎊", "🥳", "💪", "🤝", "✈️", "🚗", "🛍️", "🛒"]),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(categories, id: \.name) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.name)
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(category.emojis, id: \.self) { emoji in
                                    Button {
                                        selectedEmoji = emoji
                                        dismiss()
                                    } label: {
                                        Text(emoji)
                                            .font(.title2)
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .background(selectedEmoji == emoji
                                                ? Color.accentColor.opacity(0.15)
                                                : Color.clear)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(Strings.Event.chooseEmojiTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                if selectedEmoji != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.Event.remove) {
                            selectedEmoji = nil
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}