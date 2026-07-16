import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { ScheduledEvent } from "firebase-functions/v2/scheduler";

admin.initializeApp();
const db = admin.firestore();

// MARK: - Shared helpers

/**
 * Fetches creator name and all friends' FCM targets for a given creator UID.
 */
async function getFriendsTargets(creatorId: string): Promise<{
  creatorName: string;
  targets: Array<{ ref: FirebaseFirestore.DocumentReference; token: string }>;
}> {
  const creatorDoc = await db.collection("users").doc(creatorId).get();
  const creatorData = creatorDoc.data();
  if (!creatorData) return { creatorName: "Someone", targets: [] };

  const creatorName: string = creatorData.displayName || "Someone";
  const friendIds: string[] = creatorData.friends || [];
  if (friendIds.length === 0) return { creatorName, targets: [] };

  const friendDocs = await Promise.all(
    friendIds.map((uid) => db.collection("users").doc(uid).get())
  );

  const targets = friendDocs
    .map((doc) => ({ ref: doc.ref, token: doc.data()?.fcmToken as string | undefined }))
    .filter((t): t is { ref: FirebaseFirestore.DocumentReference; token: string } =>
      typeof t.token === "string" && t.token.length > 0
    );

  return { creatorName, targets };
}

/**
 * Sends an FCM multicast to a list of targets and cleans up any stale tokens.
 */
async function sendMulticast(
  targets: Array<{ ref: FirebaseFirestore.DocumentReference; token: string }>,
  message: Omit<admin.messaging.MulticastMessage, "tokens">,
  label: string
): Promise<void> {
  if (targets.length === 0) return;

  const response = await admin.messaging().sendEachForMulticast({
    ...message,
    tokens: targets.map((t) => t.token),
  });

  console.log(`[${label}] ${response.successCount} succeeded, ${response.failureCount} failed`);

  const staleCleanups = response.responses
    .map((res, i) => ({ res, target: targets[i] }))
    .filter(({ res }) =>
      !res.success &&
      res.error?.code === "messaging/registration-token-not-registered"
    )
    .map(({ target }) =>
      target.ref.update({ fcmToken: admin.firestore.FieldValue.delete() })
    );

  if (staleCleanups.length > 0) {
    await Promise.all(staleCleanups);
    console.log(`[${label}] Cleaned up ${staleCleanups.length} stale token(s).`);
  }
}

// MARK: - Cloud Functions

// Runs every minute — activates any events whose startTime has passed
export const activateScheduledEvents = functions.scheduler.onSchedule(
  { schedule: "every 1 minutes", timeZone: "America/Los_Angeles" },
  async (_event: ScheduledEvent) => {
    const now = admin.firestore.Timestamp.now();

    const snapshot = await db
      .collection("events")
      .where("isActive", "==", false)
      .get();

    if (snapshot.empty) return;

    const toActivate = snapshot.docs.filter((doc) => {
      const data = doc.data();
      if (data.startTime?.toMillis() > now.toMillis()) return false; // hasn't started yet
      const endTime = data.endTime?.toMillis?.();
      if (endTime && endTime < now.toMillis()) return false; // already ended manually
      return true;
    });

    if (toActivate.length === 0) return;

    const batch = db.batch();
    toActivate.forEach((doc) => batch.update(doc.ref, { isActive: true }));

    await batch.commit();
    console.log(`Activated ${toActivate.length} scheduled event(s).`);
  }
);

// Notifies friends when a new event is created
export const notifyFriendsOnEventCreate = onDocumentCreated(
  "events/{eventId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const { creatorName, targets } = await getFriendsTargets(data.creatorId);
    if (targets.length === 0) return;

    const activity: string = data.activity;
    const emoji: string | undefined = data.emoji;
    const body = emoji ? `${emoji} ${activity}` : activity;

    await sendMulticast(
      targets,
      {
        notification: { title: `${creatorName} sent a signal`, body },
        apns: { payload: { aps: { sound: "default" } } },
        data: { eventId: event.params.eventId, type: "event_created" },
      },
      "event_created"
    );
  }
);

const DEBOUNCE_COLLECTION = "eventNotifyDebounce";
const DEBOUNCE_MS = 10_000;

// Handles two cases on event update:
// 1. isActive flips false→true (scheduled event starting) → "starting now" notification, sent immediately
// 2. Content fields change (edit) → "updated" notification, debounced 10 s to coalesce rapid taps
// Live location updates (locationCoordinate) are intentionally excluded.
export const notifyFriendsOnEventUpdate = onDocumentUpdated(
  { document: "events/{eventId}", timeoutSeconds: 30 },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const eventId = event.params.eventId;
    const justActivated = before.isActive === false && after.isActive === true;

    // Event ended (manually or by expiry) — clear debounce and notify friends
    if (before.isActive === true && after.isActive === false) {
      await db.collection(DEBOUNCE_COLLECTION).doc(eventId).delete().catch(() => {});

      const { creatorName, targets } = await getFriendsTargets(after.creatorId);
      if (targets.length > 0) {
        const activity: string = after.activity;
        const emoji: string | undefined = after.emoji;
        const eventLabel = emoji ? `${emoji} ${activity}` : activity;
        await sendMulticast(
          targets,
          {
            notification: { title: `${creatorName} ended their signal`, body: eventLabel },
            apns: { payload: { aps: { sound: "default" } } },
            data: { eventId, type: "event_ended" },
          },
          "event_ended"
        );
      }
      return;
    }

    const contentFields = [
      "activity", "description", "emoji",
      "locationLabel", "locationType",
      "durationMinutes", "durationVagueLabel",
    ];
    const contentChanged =
      contentFields.some((f) => before[f] !== after[f]) ||
      before.startTime?.toMillis() !== after.startTime?.toMillis();

    if (!justActivated && !contentChanged) return;

    const activity: string = after.activity;
    const emoji: string | undefined = after.emoji;
    const eventLabel = emoji ? `${emoji} ${activity}` : activity;

    // Activation fires immediately — there's only ever one false→true transition
    if (justActivated) {
      const { creatorName, targets } = await getFriendsTargets(after.creatorId);
      await sendMulticast(
        targets,
        {
          notification: { title: `${creatorName} is starting now`, body: eventLabel },
          apns: { payload: { aps: { sound: "default" } } },
          data: { eventId, type: "event_started" },
        },
        "event_started"
      );
    }

    // Edit notifications are debounced: write a token, sleep, then only send if
    // we are still the latest writer (rapid taps overwrite each other's token).
    if (contentChanged) {
      const token = `${Date.now()}-${Math.random()}`;
      const debounceRef = db.collection(DEBOUNCE_COLLECTION).doc(eventId);

      await debounceRef.set({ token, creatorId: after.creatorId, activity, emoji: emoji ?? null });
      await new Promise((resolve) => setTimeout(resolve, DEBOUNCE_MS));

      const [debounceSnap, eventSnap] = await Promise.all([
        debounceRef.get(),
        db.collection("events").doc(eventId).get(),
      ]);
      if (!debounceSnap.exists || debounceSnap.data()?.token !== token) return; // a later edit won
      if (!eventSnap.exists) return; // event was deleted while debounce was sleeping

      await debounceRef.delete();

      const { creatorName, targets } = await getFriendsTargets(after.creatorId);
      await sendMulticast(
        targets,
        {
          notification: { title: `${creatorName} updated their signal`, body: eventLabel },
          apns: { payload: { aps: { sound: "default" } } },
          data: { eventId, type: "event_updated" },
        },
        "event_updated"
      );
    }
  }
);

// Notifies a user when they receive a new friend request
export const notifyOnFriendRequestCreate = onDocumentCreated(
  "friendRequests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const [fromDoc, toDoc] = await Promise.all([
      db.collection("users").doc(data.fromUserId).get(),
      db.collection("users").doc(data.toUserId).get(),
    ]);

    const token = toDoc.data()?.fcmToken as string | undefined;
    if (!token) return;

    const fromName: string = fromDoc.data()?.displayName || "Someone";

    await sendMulticast(
      [{ ref: toDoc.ref, token }],
      {
        notification: { title: "New friend request", body: `${fromName} wants to bool` },
        apns: { payload: { aps: { sound: "default" } } },
        data: { requestId: event.params.requestId, type: "friend_request" },
      },
      "friend_request"
    );
  }
);
