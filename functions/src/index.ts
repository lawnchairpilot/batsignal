import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2";
import { ScheduledEvent } from "firebase-functions/v2/scheduler";

admin.initializeApp();
const db = admin.firestore();

// Runs every minute — activates any events whose startTime has passed
export const activateScheduledEvents = functions.scheduler.onSchedule(
  { schedule: "every 1 minutes", timeZone: "America/Los_Angeles" },
  async (_event: ScheduledEvent) => {
    const now = admin.firestore.Timestamp.now();

    // Single where clause to avoid composite index requirement — filter startTime in memory
    const snapshot = await db
      .collection("events")
      .where("isActive", "==", false)
      .get();

    if (snapshot.empty) return;

    const toActivate = snapshot.docs.filter(
      (doc) => doc.data().startTime?.toMillis() <= now.toMillis()
    );

    if (toActivate.length === 0) return;

    const batch = db.batch();
    toActivate.forEach((doc) => batch.update(doc.ref, { isActive: true }));

    await batch.commit();
    console.log(`Activated ${toActivate.length} scheduled event(s).`);
  }
);
