import Foundation

extension Strings {
    enum Moderation {

        // MARK: - Reporting

        static let report = "Report"
        static let reportComment = "Report Comment"
        static let reportEvent = "Report Signal"
        static let reportUser = "Report User"
        static let reportReasonPrompt = "What's wrong with it?"
        static let reportNotePlaceholder = "Anything else we should know? (optional)"
        static let reportSubmit = "Submit Report"
        static let reportSubmitting = "Submitting…"
        static let reportThanksTitle = "Report Received"
        static let reportThanksMessage = """
        Thanks — we review every report within 24 hours. You won't see this \
        content anymore.
        """
        static let reportFailed = "Couldn't submit that report. Try again."

        static let reasonHarassment = "Harassment or bullying"
        static let reasonSexualContent = "Nudity or sexual content"
        static let reasonViolence = "Violence or threats"
        static let reasonSpam = "Spam or a scam"
        static let reasonImpersonation = "Pretending to be someone else"
        static let reasonOther = "Something else"

        // MARK: - Blocking

        static let block = "Block"
        static let unblock = "Unblock"
        static func blockTitle(_ name: String) -> String { "Block \(name)?" }
        static let blockMessage = """
        You'll stop seeing each other's signals and comments, and you'll no \
        longer be friends. Neither of you can send the other a friend request \
        until you unblock them.
        """
        static let blockConfirm = "Block"
        static let blockFailed = "Couldn't block them. Try again."

        static func unblockTitle(_ name: String) -> String { "Unblock \(name)?" }
        static let unblockMessage = """
        They'll be able to send you a friend request again. You won't \
        automatically be friends.
        """
        static let unblockFailed = "Couldn't unblock them. Try again."

        static let blockedUsersTitle = "Blocked"
        static let noBlockedUsers = "You haven't blocked anyone."
        static let blockedSectionFooter = """
        Blocked people can't see your signals or send you friend requests.
        """

        // MARK: - Terms

        static let termsTitle = "Community Rules"
        static let termsBody = """
        \(Strings.Common.appName) has no tolerance for objectionable content or \
        abusive behavior.

        Don't post harassment, threats, nudity, or anything illegal. Don't \
        pretend to be someone you're not. Signals and comments you post are \
        visible to the friends you send them to.

        Report anything that breaks these rules and we'll review it within 24 \
        hours — content gets removed and accounts get banned for repeat or \
        serious violations.
        """
        static let termsAgree = "I Agree"
        static let termsLinkTerms = "Terms of Use"
        static let termsLinkPrivacy = "Privacy Policy"
        static let termsFooter = "By continuing you agree to our"
        static let termsFailed = "Couldn't save that. Try again."
    }
}
