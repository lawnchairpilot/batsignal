"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyOnFriendRequestAccept = exports.notifyOnFriendRequestCreate = exports.notifyHostOnEventJoin = exports.notifyFriendsOnEventCreate = exports.activateScheduledEvents = void 0;
const admin = require("firebase-admin");
const functions = require("firebase-functions/v2");
const firestore_1 = require("firebase-functions/v2/firestore");
const strings_1 = require("./strings");
admin.initializeApp();
const db = admin.firestore();
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
    var _a;
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    const recipientIds = data.recipientIds || [];
    const targets = await getTokenTargets(recipientIds);
    if (targets.length === 0)
        return;
    const creatorDoc = await db.collection("users").doc(data.creatorId).get();
    const creatorName = ((_a = creatorDoc.data()) === null || _a === void 0 ? void 0 : _a.displayName) || strings_1.Strings.common.someone;
    const activity = data.activity;
    const emoji = data.emoji;
    const body = strings_1.Strings.event.body(activity, emoji);
    await sendMulticast(targets, {
        notification: { title: strings_1.Strings.event.createdTitle(creatorName), body },
        apns: { payload: { aps: { sound: "default" } } },
        data: { eventId: event.params.eventId, type: "event_created" },
    }, "event_created");
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
            apns: { payload: { aps: { sound: "default" } } },
            data: { eventId: event.params.eventId, type: "event_joined" },
        }, "event_joined");
    }
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
//# sourceMappingURL=index.js.map