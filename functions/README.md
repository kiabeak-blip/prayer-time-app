# Awqat Cloud Functions

Server-side proxy for the Claude timetable-extraction feature. Keeps the
Anthropic API key off the mobile app.

## `extractTimetable`

HTTP function. The app POSTs the timetable image/PDF (base64) plus the prompt,
with the admin's Firebase ID token in the `Authorization: Bearer` header. The
function:

1. Verifies the Firebase ID token.
2. Confirms the caller has an approved doc in the `admins` Firestore collection.
3. Calls Anthropic with the server-side key and returns the response verbatim.

Endpoint: `https://us-central1-prayer-times-app-a863d.cloudfunctions.net/extractTimetable`

## One-time setup

Requires the Firebase **Blaze (pay-as-you-go)** plan — Cloud Functions won't
deploy on the free Spark plan.

```bash
# 1. Install the Firebase CLI (once, globally)
npm install -g firebase-tools

# 2. Sign in
firebase login

# 3. Install function deps
cd functions
npm install
cd ..

# 4. Store the Anthropic API key as a secret (generate a FRESH key in the
#    Anthropic Console first — the old hardcoded one was leaked and revoked).
#    Paste the sk-ant-... value when prompted.
firebase functions:secrets:set ANTHROPIC_API_KEY

# 5. Deploy
firebase deploy --only functions
```

## Updating

After editing `index.js`:

```bash
firebase deploy --only functions
```

To rotate the key later: `firebase functions:secrets:set ANTHROPIC_API_KEY`
then redeploy.

## Logs

```bash
firebase functions:log
```
