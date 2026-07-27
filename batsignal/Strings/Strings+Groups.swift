import Foundation

extension Strings {
    enum Groups {
        static let title = "Groups"
        static let newGroupTitle = "New Group"
        static let editGroupTitle = "Edit Group"
        static let groupNamePlaceholder = "Group name"
        static let iconFieldLabel = "Icon"
        static let membersSectionHeader = "Members"
        static let noFriendsToAdd = "Add some friends first to build a group."
        static let noGroupsYet = "No groups yet — create one to organize your friends."
        static let delete = "Delete"

        static func memberCount(_ count: Int) -> String {
            count == 1 ? "1 friend" : "\(count) friends"
        }
    }
}
