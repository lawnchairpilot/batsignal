import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
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

// Backfills recipientIds on each user's still-visible events when a friend request
// is accepted, so a newly-added friend can immediately see events created before
// the friendship existed. recipientIds is otherwise a snapshot frozen at event
// creation — without this, "add a friend after the event started" silently hides
// the event from them forever. Runs server-side (not from the client) because
// whichever user taps accept only has write access to their own events; this
// needs to write to the *other* user's events too.
export const backfillEventVisibilityOnFriendAccept = onDocumentUpdated(
  "friendRequests/{requestId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status || after.status !== "accepted") return;

    const now = admin.firestore.Timestamp.now();

    // Equality-only and unordered so it needs no composite index — mirrors the
    // pattern in listenToMyActiveEvent on the client.
    const addAsRecipientToOwnedEvents = async (ownerId: string, newRecipientId: string) => {
      const snapshot = await db.collection("events").where("creatorId", "==", ownerId).get();
      if (snapshot.empty) return;

      const batch = db.batch();
      let updateCount = 0;

      snapshot.docs.forEach((doc) => {
        const data = doc.data();

        const endTimeMillis = data.endTime?.toMillis?.();
        if (endTimeMillis !== undefined && endTimeMillis < now.toMillis()) return; // already over

        // Missing field predates the group-scoping feature, so it was always "all friends".
        if (data.audienceIsAllFriends === false) return; // creator scoped this to specific groups

        const recipientIds: string[] = data.recipientIds || [];
        if (recipientIds.includes(newRecipientId)) return; // already visible to them

        batch.update(doc.ref, {
          recipientIds: admin.firestore.FieldValue.arrayUnion(newRecipientId),
        });
        updateCount++;
      });

      if (updateCount > 0) await batch.commit();
    };

    await Promise.all([
      addAsRecipientToOwnedEvents(after.fromUserId, after.toUserId),
      addAsRecipientToOwnedEvents(after.toUserId, after.fromUserId),
    ]);
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

// MARK: - Account deletion

/**
 * Deletes every document matched by a query, in batches. Safe to re-run: a
 * retry after a partial failure simply finds fewer documents left to delete.
 */
async function deleteQueryResults(
  query: FirebaseFirestore.Query,
  label: string
): Promise<void> {
  const snapshot = await query.get();
  if (snapshot.empty) return;

  // Firestore caps a batch at 500 writes.
  for (let i = 0; i < snapshot.docs.length; i += 400) {
    const batch = db.batch();
    snapshot.docs.slice(i, i + 400).forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  console.log(`[deleteAccount] Deleted ${snapshot.size} from ${label}.`);
}

/**
 * Strips a user id out of an array field wherever it appears.
 */
async function removeFromArrayField(
  collection: string,
  field: string,
  uid: string
): Promise<void> {
  const snapshot = await db.collection(collection).where(field, "array-contains", uid).get();
  if (snapshot.empty) return;

  for (let i = 0; i < snapshot.docs.length; i += 400) {
    const batch = db.batch();
    snapshot.docs.slice(i, i + 400).forEach((doc) =>
      batch.update(doc.ref, { [field]: admin.firestore.FieldValue.arrayRemove(uid) })
    );
    await batch.commit();
  }
  console.log(`[deleteAccount] Removed ${uid} from ${snapshot.size} ${collection}.${field}.`);
}

/**
 * Turns a Storage download URL back into the object path it points at, so an
 * event's photo can be deleted alongside the event. Returns undefined for
 * anything that isn't one of our own download URLs.
 */
function storagePathFromDownloadURL(url?: string): string | undefined {
  if (!url) return undefined;
  const match = /\/o\/([^?]+)/.exec(url);
  return match ? decodeURIComponent(match[1]) : undefined;
}

async function deleteStorageObject(path: string): Promise<void> {
  try {
    await admin.storage().bucket().file(path).delete();
  } catch (error) {
    // Already gone is the expected case on a retry, and a photo that outlives
    // its event isn't worth failing the rest of the cleanup over.
    console.warn(`[deleteAccount] Could not delete ${path}: ${(error as Error).message}`);
  }
}

/**
 * Deleting the user document is how the client asks for its account to go away
 * — see AuthService.deleteAccount. Everything the account leaves behind is torn
 * down here rather than on the client for two reasons: most of it lives in
 * other people's documents, which the client has no right to write to, and the
 * Firebase Auth user itself can only be deleted client-side within a few
 * minutes of signing in, which would force a phone re-verification just to quit.
 *
 * Every step is idempotent, so the retry re-runs whatever didn't finish.
 */
export const cleanupOnUserDelete = onDocumentDeleted(
  { document: "users/{uid}", retry: true },
  async (event) => {
    const uid = event.params.uid;
    console.log(`[deleteAccount] Cleaning up after ${uid}.`);

    // The user's own events, with their comments and photos.
    const ownedEvents = await db.collection("events").where("creatorId", "==", uid).get();
    for (const doc of ownedEvents.docs) {
      await deleteQueryResults(doc.ref.collection("comments"), `events/${doc.id}/comments`);
      const photoPath = storagePathFromDownloadURL(doc.data().imageURL as string | undefined);
      if (photoPath) await deleteStorageObject(photoPath);
      await doc.ref.delete();
    }
    console.log(`[deleteAccount] Deleted ${ownedEvents.size} owned events.`);

    await Promise.all([
      // Groups they own, and their membership in anyone else's.
      deleteQueryResults(db.collection("groups").where("ownerId", "==", uid), "owned groups"),
      removeFromArrayField("groups", "memberIds", uid),

      // Friend requests in either direction.
      deleteQueryResults(
        db.collection("friendRequests").where("fromUserId", "==", uid),
        "sent friend requests"
      ),
      deleteQueryResults(
        db.collection("friendRequests").where("toUserId", "==", uid),
        "received friend requests"
      ),

      // Their place in other people's friend lists and events.
      removeFromArrayField("users", "friends", uid),
      removeFromArrayField("events", "recipientIds", uid),
      removeFromArrayField("events", "joinedUserIds", uid),

      // Profile photos live under a folder of their own.
      admin.storage().bucket().deleteFiles({ prefix: `profile-photos/${uid}/` }).catch((error) => {
        console.warn(`[deleteAccount] Could not delete profile photos: ${error.message}`);
      }),
    ]);

    // Comments they left on other people's events. A collection group query
    // needs an index Firestore won't create on its own, so a missing one is
    // logged rather than allowed to strand the rest of the cleanup.
    try {
      await deleteQueryResults(
        db.collectionGroup("comments").where("authorId", "==", uid),
        "authored comments"
      );
    } catch (error) {
      console.error(`[deleteAccount] Comment cleanup failed: ${(error as Error).message}`);
    }

    // Last, so a failure above still leaves an account that can sign in and retry.
    try {
      await admin.auth().deleteUser(uid);
      console.log(`[deleteAccount] Deleted auth user ${uid}.`);
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code !== "auth/user-not-found") throw error;
    }
  }
);
