"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupOnUserDelete = exports.enforceUploadQuota = exports.purgeEndedEvents = exports.cleanupReplacedEventPhoto = exports.cleanupOnEventDelete = exports.notifyAdminsOnReport = exports.unblockUser = exports.blockUser = exports.findUsersByPhoneNumbers = exports.getProfiles = exports.removeFriend = exports.notifyOnFriendRequestAccept = exports.backfillEventVisibilityOnFriendAccept = exports.linkFriendsOnRequestAccept = exports.notifyOnFriendRequestCreate = exports.notifyHostOnCommentCreate = exports.notifyHostOnEventJoin = exports.notifyJoinersOnEventUpdate = exports.notifyFriendsOnEventCreate = exports.activateScheduledEvents = void 0;
const admin = require("firebase-admin");
const functions = require("firebase-functions/v2");
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const storage_1 = require("firebase-functions/v2/storage");
const strings_1 = require("./strings");
admin.initializeApp();
const db = admin.firestore();
// MARK: - App Check
//
// App Check attests that a call came from a genuine build of the iOS app.
// Enforcement for callables is a code flag rather than a console toggle, so
// flipping this deploys a hard gate: every build in the wild has to be carrying
// a token first, or real users start getting permission-denied.
//
// The rollout that avoids that: ship the client with App Check configured,
// leave this false, watch the console's App Check metrics (and the warnings
// logUnverified writes below) until unverified traffic reaches zero, then flip
// it and redeploy.
const ENFORCE_APP_CHECK = false;
const CALLABLE_OPTS = { enforceAppCheck: ENFORCE_APP_CHECK };
/**
 * Notes a call that arrived without a verified App Check token. `request.app`
 * is populated only when a valid token was presented, so while enforcement is
 * off this measures exactly what turning it on would have rejected — the same
 * signal, without the outage.
 */
function logUnverified(request, label) {
    if (!ENFORCE_APP_CHECK && !request.app) {
        console.warn(`[appcheck] ${label} ran without a verified App Check token.`);
    }
}
// MARK: - Shared helpers
/**
 * Fetches FCM targets for a list of user IDs.
 */
async function getTokenTargets(userIds) {
    if (userIds.length === 0)
        return [];
    const userDocs = await Promise.all(userIds.map((uid) => db.collection("users").doc(uid).get()));
    return userDocs
        .map((doc) => { var _a; return ({ ref: doc.ref, token: (_a = doc.data()) === null || _a === void 0 ? void 0 : _a.fcmToken }); })
        .filter((t) => typeof t.token === "string" && t.token.length > 0);
}
/**
 * Sends an FCM multicast to a list of targets and cleans up any stale tokens.
 */
async function sendMulticast(targets, message, label) {
    if (targets.length === 0)
        return;
    const response = await admin.messaging().sendEachForMulticast(Object.assign(Object.assign({}, message), { tokens: targets.map((t) => t.token) }));
    console.log(`[${label}] ${response.successCount} succeeded, ${response.failureCount} failed`);
    response.responses.forEach((res, i) => {
        var _a, _b;
        if (!res.success) {
            console.error(`[${label}] token[${i}] failed — code: ${(_a = res.error) === null || _a === void 0 ? void 0 : _a.code}, message: ${(_b = res.error) === null || _b === void 0 ? void 0 : _b.message}`);
        }
    });
    const staleCleanups = response.responses
        .map((res, i) => ({ res, target: targets[i] }))
        .filter(({ res }) => {
        var _a, _b;
        return !res.success && (((_a = res.error) === null || _a === void 0 ? void 0 : _a.code) === "messaging/registration-token-not-registered" ||
            ((_b = res.error) === null || _b === void 0 ? void 0 : _b.code) === "messaging/third-party-auth-error");
    })
        .map(({ target }) => target.ref.update({ fcmToken: admin.firestore.FieldValue.delete() }));
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
function eventIconData(imageURL) {
    return { iconImageURL: imageURL || "" };
}
// MARK: - Cloud Functions
// Runs every minute — activates any events whose startTime has passed
exports.activateScheduledEvents = functions.scheduler.onSchedule({ schedule: "every 1 minutes", timeZone: "America/Los_Angeles" }, async (_event) => {
    const now = admin.firestore.Timestamp.now();
    const snapshot = await db
        .collection("events")
        .where("isActive", "==", false)
        .get();
    if (snapshot.empty)
        return;
    const toActivate = snapshot.docs.filter((doc) => {
        var _a, _b, _c;
        const data = doc.data();
        if (((_a = data.startTime) === null || _a === void 0 ? void 0 : _a.toMillis()) > now.toMillis())
            return false; // hasn't started yet
        const endTime = (_c = (_b = data.endTime) === null || _b === void 0 ? void 0 : _b.toMillis) === null || _c === void 0 ? void 0 : _c.call(_b);
        if (endTime && endTime < now.toMillis())
            return false; // already ended manually
        return true;
    });
    if (toActivate.length === 0)
        return;
    const batch = db.batch();
    toActivate.forEach((doc) => batch.update(doc.ref, { isActive: true }));
    await batch.commit();
    console.log(`Activated ${toActivate.length} scheduled event(s).`);
});
// Notifies friends when a new event is created
exports.notifyFriendsOnEventCreate = (0, firestore_1.onDocumentCreated)("events/{eventId}", async (event) => {
    var _a, _b;
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    // The creator document gets fetched here for the display name anyway, so
    // re-deriving the audience from the live friends list is free. firestore.rules
    // already requires recipients to be friends at write time; this is the same
    // guarantee applied on the way out, and it additionally covers the window
    // between a block landing and removeFromEventsOf finishing its sweep — the
    // push is the part of a signal that can't be taken back once it's sent.
    const creatorDoc = await db.collection("users").doc(data.creatorId).get();
    const creatorFriends = new Set(((_a = creatorDoc.data()) === null || _a === void 0 ? void 0 : _a.friends) || []);
    const recipientIds = (data.recipientIds || []).filter((id) => creatorFriends.has(id));
    if (recipientIds.length === 0)
        return;
    const targets = await getTokenTargets(recipientIds);
    if (targets.length === 0)
        return;
    const creatorName = ((_b = creatorDoc.data()) === null || _b === void 0 ? void 0 : _b.displayName) || strings_1.Strings.common.someone;
    const activity = data.activity;
    const emoji = data.emoji;
    const body = strings_1.Strings.event.body(activity, emoji);
    await sendMulticast(targets, {
        notification: { title: strings_1.Strings.event.createdTitle(creatorName), body },
        apns: { payload: { aps: { sound: "default", mutableContent: true } } },
        data: Object.assign({ eventId: event.params.eventId, type: "event_created" }, eventIconData(data.imageURL)),
    }, "event_created");
});
const DEBOUNCE_COLLECTION = "eventNotifyDebounce";
const DEBOUNCE_MS = 10000;
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
exports.notifyJoinersOnEventUpdate = (0, firestore_1.onDocumentUpdated)({ document: "events/{eventId}", timeoutSeconds: 30 }, async (event) => {
    var _a, _b, _c, _d;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    const messageChanged = MESSAGE_FIELDS.some((field) => before[field] !== after[field]);
    if (!messageChanged)
        return;
    // Nobody to tell. Checked before the sleep so an untouched signal doesn't
    // hold a function open for ten seconds on every edit.
    const joinedAtEdit = after.joinedUserIds || [];
    if (joinedAtEdit.filter((id) => id !== after.creatorId).length === 0)
        return;
    const eventId = event.params.eventId;
    const token = `${Date.now()}-${Math.random()}`;
    const debounceRef = db.collection(DEBOUNCE_COLLECTION).doc(eventId);
    await debounceRef.set({ token, creatorId: after.creatorId });
    await new Promise((resolve) => setTimeout(resolve, DEBOUNCE_MS));
    const [debounceSnap, eventSnap] = await Promise.all([
        debounceRef.get(),
        db.collection("events").doc(eventId).get(),
    ]);
    if (!debounceSnap.exists || ((_c = debounceSnap.data()) === null || _c === void 0 ? void 0 : _c.token) !== token)
        return; // a later edit won
    if (!eventSnap.exists)
        return; // event was deleted while the debounce slept
    await debounceRef.delete();
    // Read off the settled event rather than the update that triggered this, so
    // the notification describes what the signal actually says now, and reaches
    // whoever is in it now.
    const settled = eventSnap.data();
    if (!settled)
        return;
    const joinerIds = (settled.joinedUserIds || []).filter((id) => id !== settled.creatorId);
    const targets = await getTokenTargets(joinerIds);
    if (targets.length === 0)
        return;
    const creatorDoc = await db.collection("users").doc(settled.creatorId).get();
    const creatorName = ((_d = creatorDoc.data()) === null || _d === void 0 ? void 0 : _d.displayName) || strings_1.Strings.common.someone;
    await sendMulticast(targets, {
        notification: {
            title: strings_1.Strings.event.updatedTitle(creatorName),
            body: strings_1.Strings.event.body(settled.activity, settled.emoji),
        },
        apns: { payload: { aps: { sound: "default", mutableContent: true } } },
        data: Object.assign({ eventId, type: "event_updated" }, eventIconData(settled.imageURL)),
    }, "event_updated");
});
// Notifies the host when a friend joins their event
exports.notifyHostOnEventJoin = (0, firestore_1.onDocumentUpdated)("events/{eventId}", async (event) => {
    var _a, _b, _c, _d;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    const beforeJoined = before.joinedUserIds || [];
    const afterJoined = after.joinedUserIds || [];
    const newJoinerIds = afterJoined.filter((id) => !beforeJoined.includes(id) && id !== after.creatorId);
    if (newJoinerIds.length === 0)
        return;
    const hostDoc = await db.collection("users").doc(after.creatorId).get();
    const hostToken = (_c = hostDoc.data()) === null || _c === void 0 ? void 0 : _c.fcmToken;
    if (!hostToken)
        return;
    const joinerDocs = await Promise.all(newJoinerIds.map((id) => db.collection("users").doc(id).get()));
    for (const joinerDoc of joinerDocs) {
        const joinerName = ((_d = joinerDoc.data()) === null || _d === void 0 ? void 0 : _d.displayName) || strings_1.Strings.common.someone;
        await sendMulticast([{ ref: hostDoc.ref, token: hostToken }], {
            notification: {
                title: strings_1.Strings.event.joinedTitle(joinerName),
                body: strings_1.Strings.event.joinedBody(joinerName, after.activity),
            },
            apns: { payload: { aps: { sound: "default", mutableContent: true } } },
            data: Object.assign({ eventId: event.params.eventId, type: "event_joined" }, eventIconData(after.imageURL)),
        }, "event_joined");
    }
});
// Notifies the host when someone comments on their event
exports.notifyHostOnCommentCreate = (0, firestore_1.onDocumentCreated)("events/{eventId}/comments/{commentId}", async (event) => {
    var _a;
    const snap = event.data;
    if (!snap)
        return;
    const comment = snap.data();
    const eventDoc = await db.collection("events").doc(event.params.eventId).get();
    const eventData = eventDoc.data();
    if (!eventData)
        return;
    // The host doesn't need to be notified about their own comment
    if (comment.authorId === eventData.creatorId)
        return;
    const hostDoc = await db.collection("users").doc(eventData.creatorId).get();
    const hostToken = (_a = hostDoc.data()) === null || _a === void 0 ? void 0 : _a.fcmToken;
    if (!hostToken)
        return;
    const commenterName = comment.authorName || strings_1.Strings.common.someone;
    await sendMulticast([{ ref: hostDoc.ref, token: hostToken }], {
        notification: {
            title: strings_1.Strings.event.commentTitle(commenterName),
            body: strings_1.Strings.event.commentBody(comment.text),
        },
        apns: { payload: { aps: { sound: "default", mutableContent: true } } },
        data: Object.assign({ eventId: event.params.eventId, commentId: event.params.commentId, type: "event_comment" }, eventIconData(eventData.imageURL)),
    }, "event_comment");
});
// Notifies a user when they receive a new friend request
exports.notifyOnFriendRequestCreate = (0, firestore_1.onDocumentCreated)("friendRequests/{requestId}", async (event) => {
    var _a, _b;
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    const [fromDoc, toDoc] = await Promise.all([
        db.collection("users").doc(data.fromUserId).get(),
        db.collection("users").doc(data.toUserId).get(),
    ]);
    const token = (_a = toDoc.data()) === null || _a === void 0 ? void 0 : _a.fcmToken;
    if (!token)
        return;
    const fromName = ((_b = fromDoc.data()) === null || _b === void 0 ? void 0 : _b.displayName) || strings_1.Strings.common.someone;
    await sendMulticast([{ ref: toDoc.ref, token }], {
        notification: { title: strings_1.Strings.friends.requestTitle, body: strings_1.Strings.friends.requestBody(fromName) },
        apns: { payload: { aps: { sound: "default" } } },
        data: { requestId: event.params.requestId, type: "friend_request" },
    }, "friend_request");
});
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
exports.linkFriendsOnRequestAccept = (0, firestore_1.onDocumentUpdated)("friendRequests/{requestId}", async (event) => {
    var _a, _b;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    if (before.status === after.status || after.status !== "accepted")
        return;
    const fromUserId = after.fromUserId;
    const toUserId = after.toUserId;
    if (!fromUserId || !toUserId || fromUserId === toUserId)
        return;
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
    }
    catch (error) {
        // An update to a document that no longer exists fails the whole batch,
        // which is the right outcome: if either side deleted their account
        // between the accept and this running, there is no friendship to record.
        console.error(`[friends] Could not link ${fromUserId} <-> ${toUserId}: ${error.message}`);
    }
});
// Backfills recipientIds on each user's still-visible events when a friend request
// is accepted, so a newly-added friend can immediately see events created before
// the friendship existed. recipientIds is otherwise a snapshot frozen at event
// creation — without this, "add a friend after the event started" silently hides
// the event from them forever. Runs server-side (not from the client) because
// whichever user taps accept only has write access to their own events; this
// needs to write to the *other* user's events too.
exports.backfillEventVisibilityOnFriendAccept = (0, firestore_1.onDocumentUpdated)("friendRequests/{requestId}", async (event) => {
    var _a, _b;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    if (before.status === after.status || after.status !== "accepted")
        return;
    const now = admin.firestore.Timestamp.now();
    // Equality-only and unordered so it needs no composite index — mirrors the
    // pattern in listenToMyActiveEvent on the client.
    const addAsRecipientToOwnedEvents = async (ownerId, newRecipientId) => {
        const snapshot = await db.collection("events").where("creatorId", "==", ownerId).get();
        if (snapshot.empty)
            return;
        const batch = db.batch();
        let updateCount = 0;
        snapshot.docs.forEach((doc) => {
            var _a, _b;
            const data = doc.data();
            const endTimeMillis = (_b = (_a = data.endTime) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a);
            if (endTimeMillis !== undefined && endTimeMillis < now.toMillis())
                return; // already over
            // Missing field predates the group-scoping feature, so it was always "all friends".
            if (data.audienceIsAllFriends === false)
                return; // creator scoped this to specific groups
            const recipientIds = data.recipientIds || [];
            if (recipientIds.includes(newRecipientId))
                return; // already visible to them
            batch.update(doc.ref, {
                recipientIds: admin.firestore.FieldValue.arrayUnion(newRecipientId),
            });
            updateCount++;
        });
        if (updateCount > 0)
            await batch.commit();
    };
    await Promise.all([
        addAsRecipientToOwnedEvents(after.fromUserId, after.toUserId),
        addAsRecipientToOwnedEvents(after.toUserId, after.fromUserId),
    ]);
});
// Notifies the requester when their friend request is accepted
exports.notifyOnFriendRequestAccept = (0, firestore_1.onDocumentUpdated)("friendRequests/{requestId}", async (event) => {
    var _a, _b, _c, _d;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    if (before.status === after.status || after.status !== "accepted")
        return;
    const [fromDoc, toDoc] = await Promise.all([
        db.collection("users").doc(after.fromUserId).get(),
        db.collection("users").doc(after.toUserId).get(),
    ]);
    const token = (_c = fromDoc.data()) === null || _c === void 0 ? void 0 : _c.fcmToken;
    if (!token)
        return;
    const toName = ((_d = toDoc.data()) === null || _d === void 0 ? void 0 : _d.displayName) || strings_1.Strings.common.someone;
    await sendMulticast([{ ref: fromDoc.ref, token }], {
        notification: { title: strings_1.Strings.friends.acceptedTitle, body: strings_1.Strings.friends.acceptedBody(toName) },
        apns: { payload: { aps: { sound: "default" } } },
        data: { requestId: event.params.requestId, type: "friend_request_accepted" },
    }, "friend_request_accepted");
});
/**
 * Removes a friendship, from the profile screen's swipe-to-remove.
 *
 * Same shape as blockUser, and for the same reason: unfriending writes two
 * users' documents and no client may write another's. It stops short of
 * writing a block — this is "we're not friends any more", not "never contact
 * me" — but it does everything else a block does to the pair, because leaving
 * any of it behind leaves access behind with it.
 *
 * Every step is idempotent, so removing someone who is already gone settles on
 * the same state rather than failing.
 */
exports.removeFriend = (0, https_1.onCall)(CALLABLE_OPTS, async (request) => {
    var _a, _b;
    logUnverified(request, "removeFriend");
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in first.");
    const friendId = (_b = request.data) === null || _b === void 0 ? void 0 : _b.userId;
    if (typeof friendId !== "string" || friendId.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "userId is required.");
    }
    if (friendId === uid) {
        throw new https_1.HttpsError("invalid-argument", "You can't remove yourself.");
    }
    // Both sides, or the other person keeps a friend who no longer has them —
    // and with it the read access on the user document that the friends list
    // grants.
    const batch = db.batch();
    batch.update(db.collection("users").doc(uid), {
        friends: admin.firestore.FieldValue.arrayRemove(friendId),
    });
    batch.update(db.collection("users").doc(friendId), {
        friends: admin.firestore.FieldValue.arrayRemove(uid),
    });
    await batch.commit();
    // The accepted request that made them friends is what's usually sitting here.
    // Left in place it's a stale record of a friendship that no longer exists, so
    // it goes along with anything else pending in either direction.
    const [sent, received] = await Promise.all([
        db.collection("friendRequests")
            .where("fromUserId", "==", uid).where("toUserId", "==", friendId).get(),
        db.collection("friendRequests")
            .where("fromUserId", "==", friendId).where("toUserId", "==", uid).get(),
    ]);
    const requestBatch = db.batch();
    [...sent.docs, ...received.docs].forEach((doc) => requestBatch.delete(doc.ref));
    if (sent.size + received.size > 0)
        await requestBatch.commit();
    // Events are gated on recipientIds rather than on friendship, so a signal
    // that's already out keeps arriving until each is taken off the other's.
    await Promise.all([
        removeFromEventsOf(uid, friendId),
        removeFromEventsOf(friendId, uid),
    ]);
    console.log(`[friends] ${uid} removed ${friendId}.`);
    return { removed: true };
});
/**
 * The fields anyone is allowed to see. Notably absent: fcmToken, which is a
 * push-notification credential, and friends, which is nobody else's business.
 */
function toPublicProfile(doc, includePhoneNumber = false) {
    const data = doc.data();
    if (!data)
        return undefined;
    const profile = {
        id: doc.id,
        displayName: data.displayName || "",
    };
    if (data.profilePhotoURL)
        profile.profilePhotoURL = data.profilePhotoURL;
    if (includePhoneNumber && data.phoneNumber)
        profile.phoneNumber = data.phoneNumber;
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
async function visibleUserIds(uid, eventId) {
    var _a;
    const visible = new Set([uid]);
    const [selfDoc, sent, received] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("friendRequests").where("fromUserId", "==", uid).get(),
        db.collection("friendRequests").where("toUserId", "==", uid).get(),
    ]);
    (((_a = selfDoc.data()) === null || _a === void 0 ? void 0 : _a.friends) || []).forEach((id) => visible.add(id));
    sent.docs.forEach((doc) => visible.add(doc.data().toUserId));
    received.docs.forEach((doc) => visible.add(doc.data().fromUserId));
    // Someone this user has blocked is no longer a friend, but the unblock
    // screen still has to be able to put a name to them.
    const blocked = await db.collection("blocks").where("blockerId", "==", uid).get();
    blocked.docs.forEach((doc) => visible.add(doc.data().blockedId));
    if (eventId) {
        const eventDoc = await db.collection("events").doc(eventId).get();
        const data = eventDoc.data();
        const recipientIds = (data === null || data === void 0 ? void 0 : data.recipientIds) || [];
        // Only someone the signal was sent to gets to see who else is on it. The
        // rest of the invite list stays private — being sent the same signal isn't
        // reason enough to be handed a stranger's profile.
        if (data && (data.creatorId === uid || recipientIds.includes(uid))) {
            visible.add(data.creatorId);
            (data.joinedUserIds || []).forEach((id) => visible.add(id));
        }
    }
    return visible;
}
/**
 * Profiles for a list of user ids, filtered down to the ones the caller is
 * allowed to see. Ids that don't survive that filter are dropped silently
 * rather than reported, so this can't be used to probe who exists.
 */
exports.getProfiles = (0, https_1.onCall)(CALLABLE_OPTS, async (request) => {
    var _a, _b, _c;
    logUnverified(request, "getProfiles");
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in first.");
    const raw = (_b = request.data) === null || _b === void 0 ? void 0 : _b.userIds;
    if (!Array.isArray(raw)) {
        throw new https_1.HttpsError("invalid-argument", "userIds must be an array.");
    }
    const userIds = Array.from(new Set(raw.filter((v) => typeof v === "string" && v.length > 0)));
    if (userIds.length === 0)
        return { profiles: [] };
    if (userIds.length > MAX_PROFILE_LOOKUP) {
        throw new https_1.HttpsError("invalid-argument", `At most ${MAX_PROFILE_LOOKUP} ids per call.`);
    }
    const eventId = typeof ((_c = request.data) === null || _c === void 0 ? void 0 : _c.eventId) === "string" ? request.data.eventId : undefined;
    const visible = await visibleUserIds(uid, eventId);
    const allowed = userIds.filter((id) => visible.has(id));
    if (allowed.length === 0)
        return { profiles: [] };
    const docs = await db.getAll(...allowed.map((id) => db.collection("users").doc(id)));
    return {
        profiles: docs
            .map((doc) => toPublicProfile(doc))
            .filter((p) => p !== undefined),
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
exports.findUsersByPhoneNumbers = (0, https_1.onCall)(CALLABLE_OPTS, async (request) => {
    var _a, _b;
    logUnverified(request, "findUsersByPhoneNumbers");
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in first.");
    const raw = (_b = request.data) === null || _b === void 0 ? void 0 : _b.phoneNumbers;
    if (!Array.isArray(raw)) {
        throw new https_1.HttpsError("invalid-argument", "phoneNumbers must be an array.");
    }
    const phoneNumbers = Array.from(new Set(raw.filter((v) => typeof v === "string" && v.length > 0)));
    if (phoneNumbers.length === 0)
        return { profiles: [] };
    if (phoneNumbers.length > MAX_PHONE_LOOKUP) {
        throw new https_1.HttpsError("invalid-argument", `At most ${MAX_PHONE_LOOKUP} numbers per call.`);
    }
    const chunks = [];
    for (let i = 0; i < phoneNumbers.length; i += PHONE_QUERY_CHUNK) {
        chunks.push(phoneNumbers.slice(i, i + PHONE_QUERY_CHUNK));
    }
    const snapshots = await Promise.all(chunks.map((chunk) => db.collection("users").where("phoneNumber", "in", chunk).get()));
    return {
        profiles: snapshots
            .flatMap((snapshot) => snapshot.docs)
            .filter((doc) => doc.id !== uid)
            .map((doc) => toPublicProfile(doc, true))
            .filter((p) => p !== undefined),
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
exports.blockUser = (0, https_1.onCall)(CALLABLE_OPTS, async (request) => {
    var _a, _b;
    logUnverified(request, "blockUser");
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in first.");
    const blockedId = (_b = request.data) === null || _b === void 0 ? void 0 : _b.userId;
    if (typeof blockedId !== "string" || blockedId.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "userId is required.");
    }
    if (blockedId === uid) {
        throw new https_1.HttpsError("invalid-argument", "You can't block yourself.");
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
        console.warn(`[block] Could not unfriend ${uid} <-> ${blockedId}: ${error.message}`);
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
    if (sent.size + received.size > 0)
        await requestBatch.commit();
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
async function removeFromEventsOf(ownerId, removedId) {
    const snapshot = await db.collection("events").where("creatorId", "==", ownerId).get();
    if (snapshot.empty)
        return;
    const batch = db.batch();
    let count = 0;
    snapshot.docs.forEach((doc) => {
        const data = doc.data();
        const inRecipients = (data.recipientIds || []).includes(removedId);
        const inJoined = (data.joinedUserIds || []).includes(removedId);
        if (!inRecipients && !inJoined)
            return;
        batch.update(doc.ref, {
            recipientIds: admin.firestore.FieldValue.arrayRemove(removedId),
            joinedUserIds: admin.firestore.FieldValue.arrayRemove(removedId),
        });
        count++;
    });
    if (count > 0)
        await batch.commit();
}
/**
 * Lifts a block. Deliberately does not restore the friendship — someone has to
 * send a fresh request, which is what the confirmation copy promises.
 */
exports.unblockUser = (0, https_1.onCall)(CALLABLE_OPTS, async (request) => {
    var _a, _b;
    logUnverified(request, "unblockUser");
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in first.");
    const blockedId = (_b = request.data) === null || _b === void 0 ? void 0 : _b.userId;
    if (typeof blockedId !== "string" || blockedId.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "userId is required.");
    }
    await db.collection("blocks").doc(`${uid}_${blockedId}`).delete();
    console.log(`[block] ${uid} unblocked ${blockedId}.`);
    return { blocked: false };
});
// Comma-separated user ids that should be told when a report comes in. Set at
// deploy time; leaving it empty just means no alert is sent.
const moderationAdmins = (0, params_1.defineString)("MODERATION_ADMIN_UIDS", { default: "" });
/**
 * Pushes to whoever moderates as soon as a report lands. The 24-hour
 * commitment in the reporting flow needs something that actually prompts a
 * human — a queue nobody is told about isn't a process.
 */
exports.notifyAdminsOnReport = (0, firestore_1.onDocumentCreated)("reports/{reportId}", async (event) => {
    var _a, _b;
    const snap = event.data;
    if (!snap)
        return;
    const report = snap.data();
    const adminIds = moderationAdmins.value()
        .split(",")
        .map((id) => id.trim())
        .filter((id) => id.length > 0);
    if (adminIds.length === 0) {
        console.log("[report] No MODERATION_ADMIN_UIDS configured; skipping alert.");
        return;
    }
    const targets = await getTokenTargets(adminIds);
    if (targets.length === 0)
        return;
    await sendMulticast(targets, {
        notification: {
            title: strings_1.Strings.moderation.reportTitle,
            body: strings_1.Strings.moderation.reportBody(report.targetType, report.reason),
        },
        apns: { payload: { aps: { sound: "default" } } },
        data: {
            reportId: event.params.reportId,
            targetType: String((_a = report.targetType) !== null && _a !== void 0 ? _a : ""),
            targetId: String((_b = report.targetId) !== null && _b !== void 0 ? _b : ""),
            type: "content_report",
        },
    }, "content_report");
});
// MARK: - Account deletion
/**
 * Deletes every document matched by a query, in batches. Safe to re-run: a
 * retry after a partial failure simply finds fewer documents left to delete.
 */
async function deleteQueryResults(query, label) {
    const snapshot = await query.get();
    if (snapshot.empty)
        return;
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
async function removeFromArrayField(collection, field, uid) {
    const snapshot = await db.collection(collection).where(field, "array-contains", uid).get();
    if (snapshot.empty)
        return;
    for (let i = 0; i < snapshot.docs.length; i += 400) {
        const batch = db.batch();
        snapshot.docs.slice(i, i + 400).forEach((doc) => batch.update(doc.ref, { [field]: admin.firestore.FieldValue.arrayRemove(uid) }));
        await batch.commit();
    }
    console.log(`[deleteAccount] Removed ${uid} from ${snapshot.size} ${collection}.${field}.`);
}
/**
 * Turns a Storage download URL back into the object path it points at, so an
 * event's photo can be deleted alongside the event. Returns undefined for
 * anything that isn't one of our own download URLs.
 */
function storagePathFromDownloadURL(url) {
    if (!url)
        return undefined;
    const match = /\/o\/([^?]+)/.exec(url);
    return match ? decodeURIComponent(match[1]) : undefined;
}
async function deleteStorageObject(path) {
    try {
        await admin.storage().bucket().file(path).delete();
    }
    catch (error) {
        // Already gone is the expected case on a retry, and a photo that outlives
        // its event isn't worth failing the rest of the cleanup over.
        console.warn(`[deleteAccount] Could not delete ${path}: ${error.message}`);
    }
}
// MARK: - Event teardown
// How long an ended signal sticks around before it's deleted outright.
const EVENT_RETENTION_DAYS = 30;
const PURGE_BATCH = 300;
const PURGE_MAX_BATCHES = 20;
/**
 * A signal's photo and its comment thread exist only for that signal, so they
 * go when it does.
 *
 * Cancelling used to delete the event document and leave both behind: the photo
 * with nothing left pointing at it — storage.rules refuses client deletes, so
 * the app couldn't have tidied up even if it had tried — and the comments as a
 * subcollection, which Firestore keeps whether or not the document it hangs
 * from still exists. Hanging the teardown off the delete rather than off each
 * caller means anything that removes an event gets it for free, purgeEndedEvents
 * below included.
 */
exports.cleanupOnEventDelete = (0, firestore_1.onDocumentDeleted)({ document: "events/{eventId}", retry: true }, async (event) => {
    var _a, _b;
    const eventId = event.params.eventId;
    await deleteQueryResults(db.collection("events").doc(eventId).collection("comments"), `events/${eventId}/comments`);
    const photoPath = storagePathFromDownloadURL((_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data()) === null || _b === void 0 ? void 0 : _b.imageURL);
    if (photoPath)
        await deleteStorageObject(photoPath);
});
/**
 * Deletes the photo a signal used to carry when its photo is changed or cleared.
 *
 * Every upload gets a fresh UUID, so swapping a signal's photo doesn't overwrite
 * the old object — it strands it, with nothing left pointing at it and no way
 * for the app to tidy up, since storage.rules refuses client deletes.
 * cleanupOnEventDelete only ever sees the photo an event is carrying when it
 * dies, which means without this the ones replaced along the way outlive both
 * the delete and the 30-day purge.
 *
 * Profile photos need no equivalent: they're written to a fixed filename, so a
 * new one overwrites the old in place and there's only ever one per account.
 */
exports.cleanupReplacedEventPhoto = (0, firestore_1.onDocumentUpdated)({ document: "events/{eventId}", retry: true }, async (event) => {
    var _a, _b, _c, _d;
    const before = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data()) === null || _b === void 0 ? void 0 : _b.imageURL;
    const after = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after.data()) === null || _d === void 0 ? void 0 : _d.imageURL;
    // Covers both directions: swapped for a different photo, and cleared
    // entirely. Every other edit to a signal lands here too and stops on this
    // line.
    if (!before || before === after)
        return;
    const path = storagePathFromDownloadURL(before);
    if (path)
        await deleteStorageObject(path);
});
/**
 * Deletes signals once they're EVENT_RETENTION_DAYS past their end. The app
 * never shows an ended signal again, so past that point the document is just a
 * record nobody asked us to keep.
 *
 * Only the documents are deleted here — each one fires cleanupOnEventDelete,
 * which is what takes the photo and the comments with it.
 */
exports.purgeEndedEvents = functions.scheduler.onSchedule({ schedule: "every day 04:00", timeZone: "America/Los_Angeles", timeoutSeconds: 540 }, async (_event) => {
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - EVENT_RETENTION_DAYS * 24 * 60 * 60 * 1000);
    let deleted = 0;
    for (let pass = 0; pass < PURGE_MAX_BATCHES; pass++) {
        const snapshot = await db
            .collection("events")
            .where("endTime", "<", cutoff)
            .limit(PURGE_BATCH)
            .get();
        if (snapshot.empty)
            break;
        // A write batch still fires the delete trigger on every document in it,
        // so this stays one round trip per batch rather than one per event.
        const batch = db.batch();
        snapshot.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        deleted += snapshot.size;
        if (snapshot.size < PURGE_BATCH)
            break;
    }
    // A signal written without an endTime never matches the query above —
    // Firestore skips documents that are missing the field being compared — so
    // it would otherwise sit there forever. Caught by age instead, and only
    // where endTime really is absent rather than merely later than the cutoff.
    const byAge = await db
        .collection("events")
        .where("createdAt", "<", cutoff)
        .orderBy("createdAt")
        .limit(PURGE_BATCH)
        .get();
    const undated = byAge.docs.filter((doc) => doc.data().endTime === undefined);
    if (undated.length > 0) {
        const batch = db.batch();
        undated.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        deleted += undated.length;
    }
    if (deleted > 0) {
        console.log(`[purge] Deleted ${deleted} signal(s) ended over ${EVENT_RETENTION_DAYS} days ago.`);
    }
});
// MARK: - Upload quota
// A signal carries at most one photo and a profile has exactly one, so a real
// account produces a handful of uploads a day. The ceiling is set well above
// that: it's here to stop a script filling the bucket, not to ration ordinary
// use, and tripping it should be a thing that essentially only abuse does.
const UPLOAD_WINDOW_MS = 24 * 60 * 60 * 1000;
const UPLOAD_LIMIT_PER_WINDOW = 60;
const UPLOAD_BLOCK_MS = 24 * 60 * 60 * 1000;
/**
 * Counts uploads per account and shuts off the ones that run away with it.
 *
 * Storage rules can cap the size of a single object but can't count objects, so
 * the counting happens here and storage.rules reads only the verdict — the
 * uploadBlocks document this writes. That leaves a gap of one object between
 * hitting the limit and the block taking effect, which is why the offending
 * upload is deleted here rather than just noted.
 */
exports.enforceUploadQuota = (0, storage_1.onObjectFinalized)(async (event) => {
    const name = event.data.name;
    if (!name)
        return;
    // Both upload paths carry the uploader's uid as their first segment. Anything
    // else in the bucket isn't user-uploaded and isn't counted.
    const owner = /^(?:event-photos|profile-photos)\/([^/]+)\//.exec(name);
    if (!owner)
        return;
    const uid = owner[1];
    const quotaRef = db.collection("uploadQuotas").doc(uid);
    const now = Date.now();
    // Transactional so two uploads landing together can't both read the same
    // count and each write back one more than it.
    const count = await db.runTransaction(async (tx) => {
        var _a, _b, _c, _d;
        const snap = await tx.get(quotaRef);
        const data = snap.data();
        const windowStart = (_c = (_b = (_a = data === null || data === void 0 ? void 0 : data.windowStart) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : 0;
        const windowIsOpen = now - windowStart < UPLOAD_WINDOW_MS;
        const next = (windowIsOpen ? ((_d = data === null || data === void 0 ? void 0 : data.count) !== null && _d !== void 0 ? _d : 0) : 0) + 1;
        tx.set(quotaRef, {
            count: next,
            windowStart: windowIsOpen
                ? admin.firestore.Timestamp.fromMillis(windowStart)
                : admin.firestore.Timestamp.fromMillis(now),
        });
        return next;
    });
    if (count <= UPLOAD_LIMIT_PER_WINDOW)
        return;
    await Promise.all([
        admin.storage().bucket(event.data.bucket).file(name).delete().catch((error) => {
            console.warn(`[upload] Could not delete ${name}: ${error.message}`);
        }),
        db.collection("uploadBlocks").doc(uid).set({
            until: admin.firestore.Timestamp.fromMillis(now + UPLOAD_BLOCK_MS),
            reason: "upload-quota",
            trippedAt: admin.firestore.FieldValue.serverTimestamp(),
        }),
    ]);
    console.warn(`[upload] ${uid} passed ${UPLOAD_LIMIT_PER_WINDOW} uploads in the window ` +
        `(${count}). Object deleted and uploads blocked for 24h.`);
});
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
exports.cleanupOnUserDelete = (0, firestore_1.onDocumentDeleted)({ document: "users/{uid}", retry: true }, async (event) => {
    const uid = event.params.uid;
    console.log(`[deleteAccount] Cleaning up after ${uid}.`);
    // The user's own events, with their comments and photos.
    const ownedEvents = await db.collection("events").where("creatorId", "==", uid).get();
    for (const doc of ownedEvents.docs) {
        await deleteQueryResults(doc.ref.collection("comments"), `events/${doc.id}/comments`);
        const photoPath = storagePathFromDownloadURL(doc.data().imageURL);
        if (photoPath)
            await deleteStorageObject(photoPath);
        await doc.ref.delete();
    }
    console.log(`[deleteAccount] Deleted ${ownedEvents.size} owned events.`);
    await Promise.all([
        // Groups they own, and their membership in anyone else's.
        deleteQueryResults(db.collection("groups").where("ownerId", "==", uid), "owned groups"),
        removeFromArrayField("groups", "memberIds", uid),
        // Friend requests in either direction.
        deleteQueryResults(db.collection("friendRequests").where("fromUserId", "==", uid), "sent friend requests"),
        deleteQueryResults(db.collection("friendRequests").where("toUserId", "==", uid), "received friend requests"),
        // Their place in other people's friend lists and events.
        removeFromArrayField("users", "friends", uid),
        removeFromArrayField("events", "recipientIds", uid),
        removeFromArrayField("events", "joinedUserIds", uid),
        // Photos of both kinds live under a folder named for the uploader.
        admin.storage().bucket().deleteFiles({ prefix: `event-photos/${uid}/` }).catch((error) => {
            console.warn(`[deleteAccount] Could not clear event photos: ${error.message}`);
        }),
        db.collection("uploadQuotas").doc(uid).delete(),
        db.collection("uploadBlocks").doc(uid).delete(),
        admin.storage().bucket().deleteFiles({ prefix: `profile-photos/${uid}/` }).catch((error) => {
            console.warn(`[deleteAccount] Could not delete profile photos: ${error.message}`);
        }),
    ]);
    // Comments they left on other people's events. A collection group query
    // needs an index Firestore won't create on its own, so a missing one is
    // logged rather than allowed to strand the rest of the cleanup.
    try {
        await deleteQueryResults(db.collectionGroup("comments").where("authorId", "==", uid), "authored comments");
    }
    catch (error) {
        console.error(`[deleteAccount] Comment cleanup failed: ${error.message}`);
    }
    // Last, so a failure above still leaves an account that can sign in and retry.
    try {
        await admin.auth().deleteUser(uid);
        console.log(`[deleteAccount] Deleted auth user ${uid}.`);
    }
    catch (error) {
        const code = error.code;
        if (code !== "auth/user-not-found")
            throw error;
    }
});
//# sourceMappingURL=index.js.map