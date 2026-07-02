"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyFriendsOnEventUpdate = exports.notifyFriendsOnEventCreate = exports.activateScheduledEvents = void 0;
const admin = require("firebase-admin");
const functions = require("firebase-functions/v2");
const firestore_1 = require("firebase-functions/v2/firestore");
admin.initializeApp();
const db = admin.firestore();
// MARK: - Shared helpers
/**
 * Fetches creator name and all friends' FCM targets for a given creator UID.
 */
async function getFriendsTargets(creatorId) {
    const creatorDoc = await db.collection("users").doc(creatorId).get();
    const creatorData = creatorDoc.data();
    if (!creatorData)
        return { creatorName: "Someone", targets: [] };
    const creatorName = creatorData.displayName || "Someone";
    const friendIds = creatorData.friends || [];
    if (friendIds.length === 0)
        return { creatorName, targets: [] };
    const friendDocs = await Promise.all(friendIds.map((uid) => db.collection("users").doc(uid).get()));
    const targets = friendDocs
        .map((doc) => { var _a; return ({ ref: doc.ref, token: (_a = doc.data()) === null || _a === void 0 ? void 0 : _a.fcmToken }); })
        .filter((t) => typeof t.token === "string" && t.token.length > 0);
    return { creatorName, targets };
}
/**
 * Sends an FCM multicast to a list of targets and cleans up any stale tokens.
 */
async function sendMulticast(targets, message, label) {
    if (targets.length === 0)
        return;
    const response = await admin.messaging().sendEachForMulticast(Object.assign(Object.assign({}, message), { tokens: targets.map((t) => t.token) }));
    console.log(`[${label}] ${response.successCount} succeeded, ${response.failureCount} failed`);
    const staleCleanups = response.responses
        .map((res, i) => ({ res, target: targets[i] }))
        .filter(({ res }) => {
        var _a;
        return !res.success &&
            ((_a = res.error) === null || _a === void 0 ? void 0 : _a.code) === "messaging/registration-token-not-registered";
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
    const toActivate = snapshot.docs.filter((doc) => { var _a; return ((_a = doc.data().startTime) === null || _a === void 0 ? void 0 : _a.toMillis()) <= now.toMillis(); });
    if (toActivate.length === 0)
        return;
    const batch = db.batch();
    toActivate.forEach((doc) => batch.update(doc.ref, { isActive: true }));
    await batch.commit();
    console.log(`Activated ${toActivate.length} scheduled event(s).`);
});
// Notifies friends when a new event is created
exports.notifyFriendsOnEventCreate = (0, firestore_1.onDocumentCreated)("events/{eventId}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    const { creatorName, targets } = await getFriendsTargets(data.creatorId);
    if (targets.length === 0)
        return;
    const activity = data.activity;
    const emoji = data.emoji;
    const body = emoji ? `${emoji} ${activity}` : activity;
    await sendMulticast(targets, {
        notification: { title: `${creatorName} sent a signal`, body },
        apns: { payload: { aps: { sound: "default" } } },
        data: { eventId: event.params.eventId, type: "event_created" },
    }, "event_created");
});
// Handles two cases on event update:
// 1. isActive flips false→true (scheduled event starting) → "starting now" notification
// 2. Content fields change (edit) → "updated" notification
// Live location updates (locationCoordinate) are intentionally excluded.
exports.notifyFriendsOnEventUpdate = (0, firestore_1.onDocumentUpdated)("events/{eventId}", async (event) => {
    var _a, _b, _c, _d;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    const justActivated = before.isActive === false && after.isActive === true;
    const contentFields = [
        "activity", "description", "emoji",
        "locationLabel", "locationType",
        "durationMinutes", "durationVagueLabel",
    ];
    const contentChanged = contentFields.some((f) => before[f] !== after[f]) ||
        ((_c = before.startTime) === null || _c === void 0 ? void 0 : _c.toMillis()) !== ((_d = after.startTime) === null || _d === void 0 ? void 0 : _d.toMillis());
    if (!justActivated && !contentChanged)
        return;
    const { creatorName, targets } = await getFriendsTargets(after.creatorId);
    if (targets.length === 0)
        return;
    const activity = after.activity;
    const emoji = after.emoji;
    const eventLabel = emoji ? `${emoji} ${activity}` : activity;
    if (justActivated) {
        await sendMulticast(targets, {
            notification: { title: `${creatorName} is starting now`, body: eventLabel },
            apns: { payload: { aps: { sound: "default" } } },
            data: { eventId: event.params.eventId, type: "event_started" },
        }, "event_started");
    }
    if (contentChanged) {
        await sendMulticast(targets, {
            notification: { title: `${creatorName} updated their signal`, body: eventLabel },
            apns: { payload: { aps: { sound: "default" } } },
            data: { eventId: event.params.eventId, type: "event_updated" },
        }, "event_updated");
    }
});
//# sourceMappingURL=index.js.map