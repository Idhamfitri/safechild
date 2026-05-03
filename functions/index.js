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