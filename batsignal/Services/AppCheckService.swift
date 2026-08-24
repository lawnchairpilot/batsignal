import FirebaseAppCheck
import FirebaseCore

/// Chooses the attestation provider App Check uses, per build configuration.
///
/// App Check gets Firebase to reject requests that didn't come from a genuine
/// build of this app. The call it matters most for is findUsersByPhoneNumbers:
/// that one has to accept numbers the caller has no prior relationship with —
/// that's what contact matching is — so the only thing standing between it and
/// being used from a script to test which numbers are on the app is proof that
/// the caller really is this app.
///
/// Nothing here touches the Firebase console or the Admin SDK. Both sit outside
/// App Check entirely, so editing documents by hand in the console and running
/// admin scripts against the project keep working exactly as they do now.
final class BlipperAppCheckProviderFactory: NSObject, AppCheckProviderFactory {

    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        // App Attest can't run in the Simulator. Debug builds present a debug
        // token instead, which has to be registered once under
        // App Check → Apps → Manage debug tokens in the console. It's printed
        // on every launch below. The token is per-install, so a wiped simulator
        // or a new machine mints a fresh one that needs registering too.
        let provider = AppCheckDebugProvider(app: app)
        if let token = provider?.localDebugToken() {
            print("[AppCheck] Debug token — register this in the Firebase console: \(token)")
        }
        return provider
        #else
        // Release builds — TestFlight and the App Store — attest with App
        // Attest, which needs iOS 14 and is always available at the iOS 18
        // deployment target this app builds against.
        return AppAttestProvider(app: app)
        #endif
    }
}
