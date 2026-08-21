import SwiftUI

struct GroupFormView: View {
    enum Mode {
        case create
        case edit(FriendGroup)
    }

    let mode: Mode
    let friends: [User]
    @ObservedObject var groupsViewModel: GroupsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedEmoji: String?
    @State private var selectedMemberIds: Set<String>
    @State private var isSaving = false
    @State private var showEmojiPicker = false

    init(mode: Mode, friends: [User], groupsViewModel: GroupsViewModel) {
        self.mode = mode
        self.friends = friends
        self.groupsViewModel = groupsViewModel
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _selectedEmoji = State(initialValue: nil)
            _selectedMemberIds = State(initialValue: [])
        case .edit(let group):
            _name = State(initialValue: group.name)
            _selectedEmoji = State(initialValue: group.emoji)
            _selectedMemberIds = State(initialValue: Set(group.memberIds))
        }
    }

    private var title: String {
        switch mode {
        case .create: return Strings.Groups.newGroupTitle
        case .edit: return Strings.Groups.editGroupTitle
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Strings.Groups.groupNamePlaceholder, text: $name)

                    Button(action: { showEmojiPicker = true }) {
                        HStack {
                            Text(Strings.Groups.iconFieldLabel)
                                .foregroundColor(Blipper.textPrimary)
                            Spacer()
                            if let selectedEmoji {
                                Text(selectedEmoji).font(.title2)
                            } else {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(Blipper.textMuted)
                            }
                            Image(systemName: "chevron.right")
                                .font(.blipperUI(.caption1))
                                .foregroundColor(Blipper.textMuted)
                        }
                    }
                    .sheet(isPresented: $showEmojiPicker) {
                        EmojiPickerView(selectedEmoji: $selectedEmoji)
                    }
                }
                .blipperRows()

                Section(Strings.Groups.membersSectionHeader) {
                    if friends.isEmpty {
                        Text(Strings.Groups.noFriendsToAdd)
                            .foregroundColor(Blipper.textMuted)
                    } else {
                        ForEach(friends) { friend in
                            Button {
                                toggle(friend)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName)
                                            // Held near regular, since this row
                                            // was never the emphasized one.
                                            .font(.blipperUI(.body, weight: 500))
                                            .foregroundColor(Blipper.textPrimary)
                                        if !friend.phoneNumber.isEmpty {
                                            Text(friend.phoneNumber)
                                                .font(.blipperUI(.caption1))
                                                .foregroundColor(Blipper.textMuted)
                                        }
                                    }
                                    Spacer()
                                    if let id = friend.id, selectedMemberIds.contains(id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(Blipper.textMuted)
                                    }
                                }
                            }
                        }
                    }
                }
                .blipperRows()
            }
            .blipperBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.save) {
                        Task {
                            await save()
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func toggle(_ friend: User) {
        guard let id = friend.id else { return }
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

    private func save() async {
        isSaving = true
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .create:
            await groupsViewModel.createGroup(name: trimmedName, emoji: selectedEmoji, memberIds: Array(selectedMemberIds))
        case .edit(let group):
            guard let id = group.id else { return }
            await groupsViewModel.updateGroup(id: id, name: trimmedName, emoji: selectedEmoji, memberIds: Array(selectedMemberIds))
        }
        isSaving = false
    }
}
