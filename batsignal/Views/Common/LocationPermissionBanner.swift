import SwiftUI
import UIKit
import CoreLocation

// Shown on your own live signal when the app can't keep your pin up to date on
// its own. It sits here rather than in onboarding because this is the moment it
// costs the user something: friends are watching a pin that has stopped moving.
// Granting Always makes it disappear for good, so nobody is asked twice.
//
// The button goes to Settings rather than re-prompting: requestAlwaysAuthorization
// only ever shows its dialog once, and after a decline the call does nothing at
// all — Settings is the only way back.
struct LocationPermissionBanner: View {
    let status: CLAuthorizationStatus

    private var warning: String? {
        switch status {
        case .authorizedAlways:
            return nil
        case .denied, .restricted:
            return Strings.Home.locationDeniedWarning
        default:
            // When In Use, and not-determined — both leave the pin frozen once
            // the app is closed.
            return Strings.Home.locationWhenInUseWarning
        }
    }

    var body: some View {
        if let warning {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(Strings.Home.openSettings, action: openSettings)
                        .font(.caption.bold())
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.1))
            )
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
