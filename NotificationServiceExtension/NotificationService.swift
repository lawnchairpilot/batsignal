import UserNotifications

// Attaches the event's image to push notifications, when it has one, so
// they show a rich thumbnail instead of just the app icon.
class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.bestAttemptContent = bestAttemptContent

        let imageURLString = request.content.userInfo["iconImageURL"] as? String

        if let imageURLString, !imageURLString.isEmpty, let url = URL(string: imageURLString) {
            downloadAndAttach(url: url, to: bestAttemptContent, contentHandler: contentHandler)
        } else {
            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func downloadAndAttach(
        url: URL,
        to content: UNMutableNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let task = URLSession.shared.downloadTask(with: url) { [weak self] location, _, _ in
            guard let self, let location else {
                contentHandler(content)
                return
            }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
            if (try? FileManager.default.moveItem(at: location, to: fileURL)) != nil {
                self.attach(fileURL: fileURL, to: content)
            }
            contentHandler(content)
        }
        task.resume()
    }

    private func attach(fileURL: URL, to content: UNMutableNotificationContent) {
        if let attachment = try? UNNotificationAttachment(identifier: "icon", url: fileURL, options: nil) {
            content.attachments = [attachment]
        }
    }
}
