// functions/index.js
// Using Firebase Functions v1 syntax — avoids Eventarc permission issues.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendIncidentAlert = functions.region("asia-southeast1").firestore
    .document("incidents/{incidentId}")
    .onCreate(async (snap, context) => {
        const incident = snap.data();
        const incidentId = context.params.incidentId;

        // Only alert if confidence >= 0.75
        if (!incident.is_alert_send) {
            console.log(`Incident ${incidentId} logged silently — no alert.`);
            return null;
        }

        const deviceId = incident.device_id;
        if (!deviceId) return null;

        // Find linked parent
        const linksSnap = await admin.firestore()
            .collection("parent_child_links")
            .where("device_id", "==", deviceId)
            .where("link_status", "==", "active")
            .get();

        if (linksSnap.empty) {
            console.warn(`No active parent link for device ${deviceId}`);
            return null;
        }

        const parentId = linksSnap.docs[0].data().parent_id;

        // Get parent FCM token
        const parentSnap = await admin.firestore()
            .collection("parents")
            .doc(parentId)
            .get();

        if (!parentSnap.exists) return null;

        const fcmToken = parentSnap.data().fcm_token;
        if (!fcmToken) {
            console.warn(`Parent ${parentId} has no FCM token.`);
            return null;
        }

        // Send FCM notification
        const message = {
            token: fcmToken,
            notification: {
                title: "⚠️ SafeChild Alert",
                body: incident.text_summary ?? "Harmful content detected",
            },
            data: {
                type: "content_alert",
                incident_id: incidentId,
                device_id: deviceId,
                category: incident.category ?? "unknown",
                confidence: String(incident.confidence_score ?? 0),
            },
            android: {
                priority: "high",
                notification: {
                    channelId: "safechild_alerts",
                    sound: "default",
                },
            },
        };

        try {
            const response = await admin.messaging().send(message);
            console.log(`Alert sent: ${response}`);

            await admin.firestore()
                .collection("incidents")
                .doc(incidentId)
                .update({ alert_send_at: admin.firestore.FieldValue.serverTimestamp() });

            return response;
        } catch (err) {
            console.error(`FCM send failed: ${err}`);
            return null;
        }
    });

exports.sendScreenTimeRequestAlert = functions.region("asia-southeast1").firestore
    .document("screen_time_requests/{requestId}")
    .onCreate(async (snap, context) => {
        const request = snap.data();
        const requestId = context.params.requestId;

        const deviceId = request.device_id;
        if (!deviceId) return null;

        console.log(`New screen time request ${requestId} detected for device ${deviceId}`);

        // Find linked parent
        const linksSnap = await admin.firestore()
            .collection("parent_child_links")
            .where("device_id", "==", deviceId)
            .where("link_status", "==", "active")
            .get();

        if (linksSnap.empty) {
            console.warn(`No active parent link for device ${deviceId}`);
            return null;
        }

        const parentId = linksSnap.docs[0].data().parent_id;

        // Get parent FCM token
        const parentSnap = await admin.firestore()
            .collection("parents")
            .doc(parentId)
            .get();

        if (!parentSnap.exists) return null;

        const fcmToken = parentSnap.data().fcm_token;
        if (!fcmToken) {
            console.warn(`Parent ${parentId} has no FCM token.`);
            return null;
        }

        // Send FCM notification
        const minutes = request.requested_time;
        const reason = request.reason || "No reason given";

        const message = {
            token: fcmToken,
            notification: {
                title: "⏳ Screen Time Request",
                body: `Child requested ${minutes} mins.\nReason: ${reason}`,
            },
            data: {
                type: "screen_time_request",
                request_id: requestId,
                device_id: deviceId,
            },
            android: {
                priority: "high",
                notification: {
                    channelId: "safechild_alerts",
                    sound: "default",
                },
            },
        };

        try {
            const response = await admin.messaging().send(message);
            console.log(`Screen time alert sent: ${response}`);
            return response;
        } catch (err) {
            console.error(`FCM send failed: ${err}`);
            return null;
        }
    });

// ── Instant lock/unlock signal to child device ─────────────────────────────
// Fires whenever screen_time_locks/{deviceId} is created, updated, or deleted.
// Sends a high-priority FCM data message so the child device reacts in < 3 s
// even when Android Doze has throttled the Firestore WebSocket.
exports.onLockChange = functions.region("asia-southeast1").firestore
    .document("screen_time_locks/{deviceId}")
    .onWrite(async (change, context) => {
        const deviceId = context.params.deviceId;
        const before   = change.before.exists ? change.before.data() : null;
        const after    = change.after.exists  ? change.after.data()  : null;

        const wasLocked = before ? before.is_locked : false;
        const isLocked  = after  ? after.is_locked  : false;
        // Skip if lock state did not actually change
        if (wasLocked === isLocked) return null;

        const deviceSnap = await admin.firestore()
            .collection("child_devices")
            .doc(deviceId)
            .get();

        if (!deviceSnap.exists) return null;
        const fcmToken = deviceSnap.data().registration_token;
        if (!fcmToken) {
            console.warn(`onLockChange: no FCM token for device ${deviceId}`);
            return null;
        }

        const lockedBy = after ? (after.locked_by || "parent") : "parent";

        const message = {
            token: fcmToken,
            data: {
                type:      "lock_change",
                is_locked: String(isLocked),
                locked_by: lockedBy,
                device_id: deviceId,
            },
            android: { priority: "high" },
        };

        try {
            await admin.messaging().send(message);
            console.log(`onLockChange FCM → device ${deviceId}: isLocked=${isLocked}`);
        } catch (err) {
            console.error(`onLockChange FCM failed: ${err}`);
        }
        return null;
    });

// ── Instant unlink signal to child device ──────────────────────────────────
// Fires when a parent_child_links document is updated or deleted.
// Reads FCM token from the link document itself (stored during pairing) so it
// works even when unlinkAndDeleteAll() deletes child_devices in the same batch.
exports.onLinkChange = functions.region("asia-southeast1").firestore
    .document("parent_child_links/{linkId}")
    .onWrite(async (change, context) => {
        const before = change.before.exists ? change.before.data() : null;
        const after  = change.after.exists  ? change.after.data()  : null;

        // Only act when a previously-active link becomes inactive or is deleted
        const wasActive = before && before.link_status === "active";
        const isActive  = after  && after.link_status  === "active";
        if (!wasActive || isActive) return null;

        const deviceId = before.device_id;
        if (!deviceId) return null;

        // Primary: token stored on the link doc during pairing (survives batch delete)
        let fcmToken = before.registration_token || null;

        // Fallback: read from child_devices (works for soft-unlink where doc is kept)
        if (!fcmToken) {
            try {
                const deviceSnap = await admin.firestore()
                    .collection("child_devices")
                    .doc(deviceId)
                    .get();
                fcmToken = deviceSnap.exists
                    ? (deviceSnap.data().registration_token || null)
                    : null;
            } catch (_) {}
        }

        if (!fcmToken) {
            console.warn(`onLinkChange: no FCM token for device ${deviceId}`);
            return null;
        }

        const message = {
            token: fcmToken,
            data: {
                type:      "device_unlinked",
                device_id: deviceId,
            },
            android: { priority: "high" },
        };

        try {
            await admin.messaging().send(message);
            console.log(`onLinkChange FCM → device ${deviceId} (unlinked)`);
        } catch (err) {
            console.error(`onLinkChange FCM failed: ${err}`);
        }
        return null;
    });