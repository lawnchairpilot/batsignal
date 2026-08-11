import Foundation

extension Strings {
    enum Home {
        static let emptyStateTitle = "No signals yet"
        static let emptyStateDescription = "When your friends are booling, it'll show up here."
        static let comingUp = "Future Bools"
        static let createSignalTitle = "Your city needs you..."
        static let yourSignal = "Your signal"
        static let openEnded = "Open-ended"
        static let extend30Min = "30"

        static let locationWhenInUseWarning = """
            Your pin stops updating when you close the app. Allow location \
            "Always" and friends can follow your signal with your phone in your \
            pocket — Bool Signal only shares your location while a signal is live.
            """
        static let locationDeniedWarning = """
            Location is off, so your signal can't show friends where you are. \
            Bool Signal only shares your location while a signal is live.
            """
        static let openSettings = "Open Settings"

        static func tomorrowAt(_ time: String) -> String {
            "Tomorrow · \(time)"
        }

        static func durationSuffix(_ label: String) -> String {
            "· \(label)"
        }
    }
}
