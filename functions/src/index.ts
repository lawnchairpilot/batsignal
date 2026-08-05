import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { ScheduledEvent } from "firebase-functions/v2/scheduler";
import { Strings } from "./strings";

admin.initializeApp();
const db = admin.firestore();

// MARK: - Shared helpers

/**
 * Fetches FCM targets for a list of user IDs.
 */
async function getTokenTargets(
  userIds: string[]
): Promise<Array<{ ref: FirebaseFirestore.DocumentReference; token: string }>> {
  if (userIds.length === 0) return [];

  const userDocs = await Promise.all(
    userIds.map((uid) => db.collection("users").doc(uid).get())
  );

  return userDocs
    .map((doc) => ({ ref: doc.ref, token: doc.data()?.fcmToken as string | undefined }))
    .filter((t): t is { ref: FirebaseFirestore.DocumentReference; token: string } =>
      typeof t.token === "string" && t.token.length > 0
    );
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

  response.responses.forEach((res, i) => {
    if (!res.success) {
      console.error(`[${label}] token[${i}] failed — code: ${res.error?.code}, message: ${res.error?.message}`);
    }
  });

  const staleCleanups = response.responses
    .map((res, i) => ({ res, target: targets[i] }))
    .filter(({ res }) =>
      !res.success && (
        res.error?.code === "messaging/registration-token-not-registered" ||
        res.error?.code === "messaging/third-party-auth-error"
      )
    )
    .map(({ target }) =>
      target.ref.update({ fcmToken: admin.firestore.FieldValue.delete() })
    );

  if (staleCleanups.length > 0) {
    await Promise.all(staleCleanups);
    console.log(`[${label}] Cleaned up ${staleCleanups.length} stale token(s).`);
  }
}

/**
 * Data-payload field the NotificationServiceExtension reads to attach the
 * event's photo to the notification instead of just showing the app icon.
 * Omitted (empty string) when the event has no photo.
 */
function eventIconData(imageURL?: string): Record<string, string> {
  return { iconImageURL: imageURL || "" };
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
    const recipientIds: string[] = data.recipientIds || [];
    const targets = await getTokenTargets(recipientIds);
    if (targets.length === 0) return;

    const creatorDoc = await db.collection("users").doc(data.creatorId).get();
    const creatorName: string = creatorDoc.data()?.displayName || Strings.common.someone;

    const activity: string = data.activity;
    const emoji: string | undefined = data.emoji;
    const body = Strings.event.body(activity, emoji);

    await sendMulticast(
      targets,
      {
        notification: { title: Strings.event.createdTitle(creatorName), body },
        apns: { payload: { aps: { sound: "default", mutableContent: true } } },
        data: {
          eventId: event.params.eventId,
          type: "event_created",
          ...eventIconData(data.imageURL),
        },
      },
      "event_created"
    );
  }
);

// Notifies the host when a friend joins their event
export const notifyHostOnEventJoin = onDocumentUpdated(
  "events/{eventId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const beforeJoined: string[] = before.joinedUserIds || [];
    const afterJoined: string[] = after.joinedUserIds || [];
    const newJoinerIds = afterJoined.filter(
      (id) => !beforeJoined.includes(id) && id !== after.creatorId
    );
    if (newJoinerIds.length === 0) return;

    const hostDoc = await db.collection("users").doc(after.creatorId).get();
    const hostToken = hostDoc.data()?.fcmToken as string | undefined;
    if (!hostToken) return;

    const joinerDocs = await Promise.all(
      newJoinerIds.map((id) => db.collection("users").doc(id).get())
    );

    for (const joinerDoc of joinerDocs) {
      const joinerName: string = joinerDoc.data()?.displayName || Strings.common.someone;

      await sendMulticast(
        [{ ref: hostDoc.ref, token: hostToken }],
        {
          notification: {
            title: Strings.event.joinedTitle(joinerName),
            body: Strings.event.joinedBody(joinerName, after.activity),
          },
          apns: { payload: { aps: { sound: "default", mutableContent: true } } },
          data: {
            eventId: event.params.eventId,
            type: "event_joined",
            ...eventIconData(after.imageURL),
          },
        },
        "event_joined"
      );
    }
  }
);

// Notifies the host when someone comments on their event
export const notifyHostOnCommentCreate = onDocumentCreated(
  "events/{eventId}/comments/{commentId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const comment = snap.data();

    const eventDoc = await db.collection("events").doc(event.params.eventId).get();
    const eventData = eventDoc.data();
    if (!eventData) return;

    // The host doesn't need to be notified about their own comment
    if (comment.authorId === eventData.creatorId) return;

    const hostDoc = await db.collection("users").doc(eventData.creatorId).get();
    const hostToken = hostDoc.data()?.fcmToken as string | undefined;
    if (!hostToken) return;

    const commenterName: string = comment.authorName || Strings.common.someone;

    await sendMulticast(
      [{ ref: hostDoc.ref, token: hostToken }],
      {
        notification: {
          title: Strings.event.commentTitle(commenterName),
          body: Strings.event.commentBody(comment.text),
        },
        apns: { payload: { aps: { sound: "default", mutableContent: true } } },
        data: {
          eventId: event.params.eventId,
          commentId: event.params.commentId,
          type: "event_comment",
          ...eventIconData(eventData.imageURL),
        },
      },
      "event_comment"
    );
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

    const fromName: string = fromDoc.data()?.displayName || Strings.common.someone;

    await sendMulticast(
      [{ ref: toDoc.ref, token }],
      {
        notification: { title: Strings.friends.requestTitle, body: Strings.friends.requestBody(fromName) },
        apns: { payload: { aps: { sound: "default" } } },
        data: { requestId: event.params.requestId, type: "friend_request" },
      },
      "friend_request"
    );
  }
);

// Notifies the requester when their friend request is accepted
export const notifyOnFriendRequestAccept = onDocumentUpdated(
  "friendRequests/{requestId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status || after.status !== "accepted") return;

    const [fromDoc, toDoc] = await Promise.all([
      db.collection("users").doc(after.fromUserId).get(),
      db.collection("users").doc(after.toUserId).get(),
    ]);

    const token = fromDoc.data()?.fcmToken as string | undefined;
    if (!token) return;

    const toName: string = toDoc.data()?.displayName || Strings.common.someone;

    await sendMulticast(
      [{ ref: fromDoc.ref, token }],
      {
        notification: { title: Strings.friends.acceptedTitle, body: Strings.friends.acceptedBody(toName) },
        apns: { payload: { aps: { sound: "default" } } },
        data: { requestId: event.params.requestId, type: "friend_request_accepted" },
      },
      "friend_request_accepted"
    );
  }
);
