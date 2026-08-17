import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
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

const DEBOUNCE_COLLECTION = "eventNotifyDebounce";
const DEBOUNCE_MS = 10_000;

// Just the signal's text. The old version of this watched location, duration
// and timing too, which meant every +30 tap or move of the pin was an "updated"
// notification; rewording the signal is the only edit that sends one now.
const MESSAGE_FIELDS = ["activity", "description"];

// Tells everyone who joined a signal when its host rewords it. Only joiners are
// notified — this used to go to every friend, which is why it was turned off —
// and never the host, who is the one doing the editing.
//
// Debounced 10 s: the edit sheet writes on every save and a joiner should get
// one "updated" notification for a round of changes rather than one per write.
// Each run writes a token, sleeps, and only sends if it's still the newest
// writer, so a later edit cancels the earlier one's notification.
export const notifyJoinersOnEventUpdate = onDocumentUpdated(
  { document: "events/{eventId}", timeoutSeconds: 30 },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const messageChanged = MESSAGE_FIELDS.some((field) => before[field] !== after[field]);
    if (!messageChanged) return;

    // Nobody to tell. Checked before the sleep so an untouched signal doesn't
    // hold a function open for ten seconds on every edit.
    const joinedAtEdit: string[] = after.joinedUserIds || [];
    if (joinedAtEdit.filter((id) => id !== after.creatorId).length === 0) return;

    const eventId = event.params.eventId;
    const token = `${Date.now()}-${Math.random()}`;
    const debounceRef = db.collection(DEBOUNCE_COLLECTION).doc(eventId);

    await debounceRef.set({ token, creatorId: after.creatorId });
    await new Promise((resolve) => setTimeout(resolve, DEBOUNCE_MS));

    const [debounceSnap, eventSnap] = await Promise.all([
      debounceRef.get(),
      db.collection("events").doc(eventId).get(),
    ]);
    if (!debounceSnap.exists || debounceSnap.data()?.token !== token) return; // a later edit won
    if (!eventSnap.exists) return; // event was deleted while the debounce slept

    await debounceRef.delete();

    // Read off the settled event rather than the update that triggered this, so
    // the notification describes what the signal actually says now, and reaches
    // whoever is in it now.
    const settled = eventSnap.data();
    if (!settled) return;

    const joinerIds: string[] = (settled.joinedUserIds || []).filter(
      (id: string) => id !== settled.creatorId
    );
    const targets = await getTokenTargets(joinerIds);
    if (targets.length === 0) return;

    const creatorDoc = await db.collection("users").doc(settled.creatorId).get();
    const creatorName: string = creatorDoc.data()?.displayName || Strings.common.someone;

    await sendMulticast(
      targets,
      {
        notification: {
          title: Strings.event.updatedTitle(creatorName),
          body: Strings.event.body(settled.activity, settled.emoji),
        },
        apns: { payload: { aps: { sound: "default", mutableContent: true } } },
        data: {
          eventId,
          type: "event_updated",
          ...eventIconData(settled.imageURL),
        },
      },
      "event_updated"
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

// Writes both halves of a new friendship.
//
// This used to run on the client (FriendService.addMutualFriendship), which
// meant a phone had to be trusted to edit someone else's friends list. Rules
// can't check that trust: verifying "you really did accept a request from this
// person" means finding the request document, and rules can only look a
// document up by id, never search for one. So the write moves here, and rules
// now refuse `friends` writes from clients entirely.
//
// arrayUnion is idempotent, so a retry — or an older build still writing its
// own half — settles on the same result.
export const linkFriendsOnRequestAccept = onDocumentUpdated(
  "friendRequests/{requestId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status || after.status !== "accepted") return;

    const fromUserId: string | undefined = after.fromUserId;
    const toUserId: string | undefined = after.toUserId;
    if (!fromUserId || !toUserId || fromUserId === toUserId) return;

    const batch = db.batch();
    batch.update(db.collection("users").doc(fromUserId), {
      friends: admin.firestore.FieldValue.arrayUnion(toUserId),
    });
    batch.update(db.collection("users").doc(toUserId), {
      friends: admin.firestore.FieldValue.arrayUnion(fromUserId),
    });

    try {
      await batch.commit();
      console.log(`[friends] Linked ${fromUserId} <-> ${toUserId}.`);
    } catch (error) {
      // An update to a document that no longer exists fails the whole batch,
      // which is the right outcome: if either side deleted their account
      // between the accept and this running, there is no friendship to record.
      console.error(`[friends] Could not link ${fromUserId} <-> ${toUserId}: ${(error as Error).message}`);
    }
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

// MARK: - Profile lookup
//
// A `users` document is readable only by its owner and that owner's friends
// (see firestore.rules). Every other screen that legitimately shows a name and
// a face — a pending friend request, the people who joined someone else's
// signal, a contact who turns out to have an account — goes through one of the
// two callables below, where the caller's right to see each profile is decided
// server-side and only the public fields ever leave.

type PublicProfile = {
  id: string;
  displayName: string;
  profilePhotoURL?: string;
  phoneNumber?: string;
};

/**
 * The fields anyone is allowed to see. Notably absent: fcmToken, which is a
 * push-notification credential, and friends, which is nobody else's business.
 */
function toPublicProfile(
  doc: FirebaseFirestore.DocumentSnapshot,
  includePhoneNumber = false
): PublicProfile | undefined {
  const data = doc.data();
  if (!data) return undefined;

  const profile: PublicProfile = {
    id: doc.id,
    displayName: (data.displayName as string) || "",
  };
  if (data.profilePhotoURL) profile.profilePhotoURL = data.profilePhotoURL as string;
  if (includePhoneNumber && data.phoneNumber) profile.phoneNumber = data.phoneNumber as string;
  return profile;
}

const MAX_PHONE_LOOKUP = 2000;
const PHONE_QUERY_CHUNK = 30; // Firestore caps an `in` filter at 30 values.
const MAX_PROFILE_LOOKUP = 200;

/**
 * Which users this caller is entitled to see, as a set of ids: themselves,
 * their friends, anyone they have a friend request open with in either
 * direction, and — when the caller names a signal they can actually see — its
 * host and whoever has joined it.
 */
async function visibleUserIds(uid: string, eventId?: string): Promise<Set<string>> {
  const visible = new Set<string>([uid]);

  const [selfDoc, sent, received] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("friendRequests").where("fromUserId", "==", uid).get(),
    db.collection("friendRequests").where("toUserId", "==", uid).get(),
  ]);

  ((selfDoc.data()?.friends as string[]) || []).forEach((id) => visible.add(id));
  sent.docs.forEach((doc) => visible.add(doc.data().toUserId));
  received.docs.forEach((doc) => visible.add(doc.data().fromUserId));

  // Someone this user has blocked is no longer a friend, but the unblock
  // screen still has to be able to put a name to them.
  const blocked = await db.collection("blocks").where("blockerId", "==", uid).get();
  blocked.docs.forEach((doc) => visible.add(doc.data().blockedId));

  if (eventId) {
    const eventDoc = await db.collection("events").doc(eventId).get();
    const data = eventDoc.data();
    const recipientIds: string[] = data?.recipientIds || [];

    // Only someone the signal was sent to gets to see who else is on it. The
    // rest of the invite list stays private — being sent the same signal isn't
    // reason enough to be handed a stranger's profile.
    if (data && (data.creatorId === uid || recipientIds.includes(uid))) {
      visible.add(data.creatorId);
      ((data.joinedUserIds as string[]) || []).forEach((id) => visible.add(id));
    }
  }

  return visible;
}

/**
 * Profiles for a list of user ids, filtered down to the ones the caller is
 * allowed to see. Ids that don't survive that filter are dropped silently
 * rather than reported, so this can't be used to probe who exists.
 */
export const getProfiles = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const raw = request.data?.userIds;
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "userIds must be an array.");
  }

  const userIds = Array.from(
    new Set(raw.filter((v): v is string => typeof v === "string" && v.length > 0))
  );
  if (userIds.length === 0) return { profiles: [] };
  if (userIds.length > MAX_PROFILE_LOOKUP) {
    throw new HttpsError("invalid-argument", `At most ${MAX_PROFILE_LOOKUP} ids per call.`);
  }

  const eventId = typeof request.data?.eventId === "string" ? request.data.eventId : undefined;
  const visible = await visibleUserIds(uid, eventId);
  const allowed = userIds.filter((id) => visible.has(id));
  if (allowed.length === 0) return { profiles: [] };

  const docs = await db.getAll(
    ...allowed.map((id) => db.collection("users").doc(id))
  );

  return {
    profiles: docs
      .map((doc) => toPublicProfile(doc))
      .filter((p): p is PublicProfile => p !== undefined),
  };
});

/**
 * Which of these phone numbers have accounts. Backs both contact matching and
 * the add-by-number field.
 *
 * This is the one lookup that has to accept numbers the caller has no prior
 * relationship with — that's what contact matching is. So it can still be used
 * to test whether a given number is on the app. What it no longer does is hand
 * back the whole user document: a match returns a name and a photo, never an
 * fcmToken or a friends list. Turning on App Check is what would stop the
 * lookup being called from anything but the real app.
 */
export const findUsersByPhoneNumbers = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const raw = request.data?.phoneNumbers;
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "phoneNumbers must be an array.");
  }

  const phoneNumbers = Array.from(
    new Set(raw.filter((v): v is string => typeof v === "string" && v.length > 0))
  );
  if (phoneNumbers.length === 0) return { profiles: [] };
  if (phoneNumbers.length > MAX_PHONE_LOOKUP) {
    throw new HttpsError("invalid-argument", `At most ${MAX_PHONE_LOOKUP} numbers per call.`);
  }

  const chunks: string[][] = [];
  for (let i = 0; i < phoneNumbers.length; i += PHONE_QUERY_CHUNK) {
    chunks.push(phoneNumbers.slice(i, i + PHONE_QUERY_CHUNK));
  }

  const snapshots = await Promise.all(
    chunks.map((chunk) => db.collection("users").where("phoneNumber", "in", chunk).get())
  );

  return {
    profiles: snapshots
      .flatMap((snapshot) => snapshot.docs)
      .filter((doc) => doc.id !== uid)
      .map((doc) => toPublicProfile(doc, true))
      .filter((p): p is PublicProfile => p !== undefined),
  };
});

// MARK: - Moderation

/**
 * Blocking tears down a friendship, which means writing two users' documents,
 * and no client may write either. It also has to reach into events on both
 * sides, so all of it runs here.
 *
 * Every step is idempotent — blocking someone already blocked settles on the
 * same state rather than failing.
 */
export const blockUser = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const blockedId = request.data?.userId;
  if (typeof blockedId !== "string" || blockedId.length === 0) {
    throw new HttpsError("invalid-argument", "userId is required.");
  }
  if (blockedId === uid) {
    throw new HttpsError("invalid-argument", "You can't block yourself.");
  }

  const blockId = `${uid}_${blockedId}`;
  await db.collection("blocks").doc(blockId).set({
    blockerId: uid,
    blockedId,
    createdAt: admin.firestore.Timestamp.now(),
  });

  // Drop the friendship from both sides. arrayRemove on a document that never
  // had them is a no-op, so this is safe whether or not they were friends.
  const batch = db.batch();
  batch.update(db.collection("users").doc(uid), {
    friends: admin.firestore.FieldValue.arrayRemove(blockedId),
  });
  batch.update(db.collection("users").doc(blockedId), {
    friends: admin.firestore.FieldValue.arrayRemove(uid),
  });
  await batch.commit().catch((error) => {
    console.warn(`[block] Could not unfriend ${uid} <-> ${blockedId}: ${(error as Error).message}`);
  });

  // Pending requests in either direction would otherwise sit there offering an
  // accept button for someone who can no longer be a friend.
  const [sent, received] = await Promise.all([
    db.collection("friendRequests")
      .where("fromUserId", "==", uid).where("toUserId", "==", blockedId).get(),
    db.collection("friendRequests")
      .where("fromUserId", "==", blockedId).where("toUserId", "==", uid).get(),
  ]);
  const requestBatch = db.batch();
  [...sent.docs, ...received.docs].forEach((doc) => requestBatch.delete(doc.ref));
  if (sent.size + received.size > 0) await requestBatch.commit();

  // Pull each out of the other's signals, so nothing already sent keeps arriving.
  await Promise.all([
    removeFromEventsOf(uid, blockedId),
    removeFromEventsOf(blockedId, uid),
  ]);

  console.log(`[block] ${uid} blocked ${blockedId}.`);
  return { blocked: true };
});

/**
 * Strips one user out of the recipient and joined lists on another user's
 * events.
 */
async function removeFromEventsOf(ownerId: string, removedId: string): Promise<void> {
  const snapshot = await db.collection("events").where("creatorId", "==", ownerId).get();
  if (snapshot.empty) return;

  const batch = db.batch();
  let count = 0;
  snapshot.docs.forEach((doc) => {
    const data = doc.data();
    const inRecipients = (data.recipientIds || []).includes(removedId);
    const inJoined = (data.joinedUserIds || []).includes(removedId);
    if (!inRecipients && !inJoined) return;

    batch.update(doc.ref, {
      recipientIds: admin.firestore.FieldValue.arrayRemove(removedId),
      joinedUserIds: admin.firestore.FieldValue.arrayRemove(removedId),
    });
    count++;
  });
  if (count > 0) await batch.commit();
}

/**
 * Lifts a block. Deliberately does not restore the friendship — someone has to
 * send a fresh request, which is what the confirmation copy promises.
 */
export const unblockUser = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const blockedId = request.data?.userId;
  if (typeof blockedId !== "string" || blockedId.length === 0) {
    throw new HttpsError("invalid-argument", "userId is required.");
  }

  await db.collection("blocks").doc(`${uid}_${blockedId}`).delete();
  console.log(`[block] ${uid} unblocked ${blockedId}.`);
  return { blocked: false };
});

// Comma-separated user ids that should be told when a report comes in. Set at
// deploy time; leaving it empty just means no alert is sent.
const moderationAdmins = defineString("MODERATION_ADMIN_UIDS", { default: "" });

/**
 * Pushes to whoever moderates as soon as a report lands. The 24-hour
 * commitment in the reporting flow needs something that actually prompts a
 * human — a queue nobody is told about isn't a process.
 */
export const notifyAdminsOnReport = onDocumentCreated(
  "reports/{reportId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const report = snap.data();

    const adminIds = moderationAdmins.value()
      .split(",")
      .map((id: string) => id.trim())
      .filter((id: string) => id.length > 0);
    if (adminIds.length === 0) {
      console.log("[report] No MODERATION_ADMIN_UIDS configured; skipping alert.");
      return;
    }

    const targets = await getTokenTargets(adminIds);
    if (targets.length === 0) return;

    await sendMulticast(
      targets,
      {
        notification: {
          title: Strings.moderation.reportTitle,
          body: Strings.moderation.reportBody(report.targetType, report.reason),
        },
        apns: { payload: { aps: { sound: "default" } } },
        data: {
          reportId: event.params.reportId,
          targetType: String(report.targetType ?? ""),
          targetId: String(report.targetId ?? ""),
          type: "content_report",
        },
      },
      "content_report"
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
