import Foundation

extension Strings {
    enum Home {
        static let emptyStateTitle = "No signals yet"
        static let emptyStateDescription = "When your friends are booling, it'll show up here."
        static let whatsHappening = "Current Bools"
        static let comingUp = "Future Bools"
        static let activeEventAlertTitle = "Signal already active"
        static let activeEventAlertMessage = "End your current signal before starting a new one."
        static let yourSignal = "Your signal"
        static let openEnded = "Open-ended"
        static let extend30Min = "30 min"

        static func tomorrowAt(_ time: String) -> String {
            "Tomorrow · \(time)"
        }

        static func durationSuffix(_ label: String) -> String {
            "· \(label)"
        }
    }
}
