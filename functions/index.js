/**
 * Cloud Function: extractTimetable
 *
 * Server-side proxy for the Claude (Anthropic) timetable-extraction feature.
 * The Anthropic API key lives ONLY here (as a Secret Manager secret) and is
 * never shipped inside the mobile app. The endpoint is gated so only an
 * approved admin of this Firebase project can use it:
 *
 *   1. The caller must send a valid Firebase ID token (Authorization: Bearer).
 *   2. That token's email must have an approved doc in the `admins` collection
 *      (same gate the app already uses — doc id = encodeURIComponent(email)).
 *
 * On success it forwards the request to Anthropic and returns the response
 * body verbatim, so the app parses `content[0].text` exactly as before.
 */

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

// Set once with:  firebase functions:secrets:set ANTHROPIC_API_KEY
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// Must match the app's AdminService._docId (Dart Uri.encodeComponent of the
// lowercased email — equivalent to JS encodeURIComponent for email chars).
const emailToDocId = (email) => encodeURIComponent(email.toLowerCase());

exports.extractTimetable = onRequest(
  {
    secrets: [ANTHROPIC_API_KEY],
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 120,
    maxInstances: 5,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Verify the Firebase ID token.
    const authHeader = req.get("Authorization") || "";
    const m = authHeader.match(/^Bearer (.+)$/);
    if (!m) {
      res.status(401).json({ error: "Missing bearer token" });
      return;
    }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(m[1]);
    } catch (e) {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }

    const email = (decoded.email || "").toLowerCase();
    if (!email) {
      res.status(403).json({ error: "Token has no email" });
      return;
    }

    // 2. Confirm the caller is an approved admin.
    try {
      const snap = await admin
        .firestore()
        .collection("admins")
        .doc(emailToDocId(email))
        .get();
      if (!snap.exists) {
        res.status(403).json({ error: "Not an approved admin" });
        return;
      }
    } catch (e) {
      logger.error("Admin lookup failed", e);
      res.status(500).json({ error: "Admin check failed" });
      return;
    }

    // 3. Validate the payload.
    const body = req.body || {};
    const mediaType = body.media_type;
    const data = body.data;
    const prompt = body.prompt;
    const isPdf = body.is_pdf === true;
    if (!mediaType || !data || !prompt) {
      res
        .status(400)
        .json({ error: "Missing media_type, data, or prompt" });
      return;
    }

    const contentBlock = isPdf
      ? { type: "document", source: { type: "base64", media_type: mediaType, data } }
      : { type: "image", source: { type: "base64", media_type: mediaType, data } };

    // 4. Forward to Anthropic with the server-side key.
    try {
      const upstream = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": ANTHROPIC_API_KEY.value(),
          "anthropic-version": "2023-06-01",
          "anthropic-beta": "pdfs-2024-09-25",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: "claude-haiku-4-5-20251001",
          max_tokens: 8192,
          messages: [
            {
              role: "user",
              content: [contentBlock, { type: "text", text: prompt }],
            },
          ],
        }),
      });

      const text = await upstream.text();
      // Pass Anthropic's status + body straight through so the app's existing
      // error handling and content parsing keep working unchanged.
      res.status(upstream.status).set("content-type", "application/json").send(text);
    } catch (e) {
      logger.error("Anthropic request failed", e);
      res.status(502).json({ error: "Upstream request failed: " + e.message });
    }
  }
);
