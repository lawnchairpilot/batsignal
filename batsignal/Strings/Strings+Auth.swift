import Foundation

extension Strings {
    enum Auth {
        static let countryCode = "+1"
        static let phoneEntryHeadline = "What's your number?"
        static let phoneEntrySubtitle = "We'll send a verification code to confirm it's you."
        static let phoneNumberPlaceholder = "(555) 555-5555"
        static let sendCode = "Send Code"
        static let codeVerificationHeadline = "Enter the code"
        static let codePlaceholder = "6-digit code"
        static let verify = "Verify"
        static let useDifferentNumber = "Use a different number"
        static let setUpProfileHeadline = "Set up your profile"
        static let setUpProfileSubtitle = "Choose a name so your friends can find you."
        static let displayNamePlaceholder = "Display name"
        static let continueLabel = "Continue"
        static let invalidPhoneNumber = "Please enter a valid 10-digit US phone number."
        static let invalidCode = "Please enter the 6-digit code."

        static func sentToCode(_ phoneNumber: String) -> String {
            "Sent to \(countryCode) \(phoneNumber)"
        }
    }
}
