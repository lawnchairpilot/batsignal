import SwiftUI

// The profile and settings screens present their rows as separate cards rather
// than as one continuous block, which means each row gives up the list's shared
// background and carries its own.
extension View {
    // The card itself. Kept separate from the row chrome because a row that's a
    // button or a navigation link needs the padding and background inside its
    // label, so the whole card takes the tap rather than just the text on it.
    func cardSurface() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    // Clears the list's own background and separators so the cards are what's
    // visible, and spaces them apart.
    func cardRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }

    func profileCard() -> some View {
        cardSurface().cardRow()
    }
}
