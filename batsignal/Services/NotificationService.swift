import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

final class NotificationService: NSObject, MessagingDelegate {
    static let shared = NotificationService()

    private override init() {}

    // Called after sign-in: asks for permission then ensures token is stored
    func requestPermissionAndRefresh() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            // Fetch current token in case the delegate won't fire (token unchanged since last launch)
            self?.saveCurrentToken()
        }
    }

    // Stores whatever token FCM has already issued. On a new account the token
    // arrives at sign-in, before there's a user document to hold it, and the
    // delegate won't fire again for the rest of the launch — so profile setup
    // calls this once the document exists and the write has somewhere to land.
    func saveCurrentToken() {
        Messaging.messaging().token { [weak self] token, error in
            guard let token, error == nil else { return }
            self?.saveToken(token)
        }
    }

    // FCM calls this whenever the registration token is issued or rotated
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        saveToken(token)
    }

    private func saveToken(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).setData(["fcmToken": token], merge: true)
    }
}