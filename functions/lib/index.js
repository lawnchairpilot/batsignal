"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.activateScheduledEvents = void 0;
const admin = require("firebase-admin");
const functions = require("firebase-functions/v2");
admin.initializeApp();
const db = admin.firestore();
// Runs every minute — activates any events whose startTime has passed
exports.activateScheduledEvents = functions.scheduler.onSchedule({ schedule: "every 1 minutes", timeZone: "America/Los_Angeles" }, async (_event) => {
    const now = admin.firestore.Timestamp.now();
    // Single where clause to avoid composite index requirement — filter startTime in memory
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
//# sourceMappingURL=index.js.map