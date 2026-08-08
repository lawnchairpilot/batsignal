import Foundation

extension Strings {
    enum Home {
        static let emptyStateTitle = "No signals yet"
        static let emptyStateDescription = "When your friends are booling, it'll show up here."
        static let comingUp = "Future Bools"
        static let createSignalTitle = "Send a Signal"
        static let yourSignal = "Your signal"
        static let openEnded = "Open-ended"
        static let extend30Min = "30"

        static func tomorrowAt(_ time: String) -> String {
            "Tomorrow · \(time)"
        }

        static func durationSuffix(_ label: String) -> String {
            "· \(label)"
        }
    }
}
