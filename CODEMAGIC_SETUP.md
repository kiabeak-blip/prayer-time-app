# Codemagic setup (one-time)

`codemagic.yaml` in the repo root defines the build. A few credentials can't
live in the repo — set these up once in the Codemagic UI, then every push to
`main` builds and publishes automatically.

## 0. Switch the app to codemagic.yaml

In Codemagic → your app → **Settings**, switch the build configuration from the
**Workflow Editor** to **codemagic.yaml**. Codemagic will detect the file on the
next build.

## 1. Pin the Flutter version (already done in yaml)

`codemagic.yaml` pins `flutter: 3.44.8`. Confirm that matches your machine:

```bash
flutter --version
```

If yours differs, edit the `flutter_version` value at the top of `codemagic.yaml`
so CI and local always agree (this is what prevents the `intl` / dependency
drift you hit).

## 2. Android — signing keystore

Codemagic needs its own copy of your release keystore (`prayertimes-release.jks`).

1. Codemagic → **Teams/App settings → Code signing identities → Android keystores**
2. **Upload** `prayertimes-release.jks` and enter:
   - **Reference name:** `awqat_keystore`  ← must match `android_signing` in the yaml
   - **Keystore password**, **Key alias**, **Key password** (same values as your
     local `android/key.properties`)

The yaml's "Write key.properties" step recreates `key.properties` on the build
machine from these, so Gradle signs the `.aab`.

## 3. Android — Google Play publishing

1. In Google Cloud / Play Console, create a **service account** with the *Google
   Play Android Developer API* enabled, grant it release permissions in Play
   Console, and download its **JSON key**.
2. Codemagic → app → **Environment variables**:
   - Variable: `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`
   - Value: paste the entire JSON file contents
   - Group: `google_play`  ← must match `groups:` in the yaml
   - Check **Secure**.

First upload to a track must sometimes be done manually in Play Console; after
that the `internal` track auto-publishes. Promote internal → production in the
Play Console when you're happy.

## 4. iOS — App Store Connect API key

1. App Store Connect → **Users and Access → Integrations → App Store Connect API**
   → create a key with **App Manager** role. Note the **Issuer ID**, **Key ID**,
   and download the **.p8** file.
2. Codemagic → **Teams/App settings → Integrations → App Store Connect** → add the
   key with name **`awqat_asc_key`**  ← must match `integrations` in the yaml.

With this, `ios_signing` fetches/creates the distribution certificate and
provisioning profile automatically for `com.muslimapp.awqat` — no manual certs.

Also set **`APP_STORE_APPLE_ID`** in `codemagic.yaml` (ios-workflow `vars`) to your
app's numeric Apple ID — find it in App Store Connect → your app → **App
Information → Apple ID** (a number like `1234567890`). This lets CI auto-increment
the build number from TestFlight. If left as `0000000000`, iOS still builds but
uses the `pubspec.yaml` build number instead.

## 5. Run it

Push to `main` (or press **Start new build** and pick a workflow). Android and
iOS each build, sign, and publish to their store's test track.

## Notes

- **Build numbers:** auto-incremented by CI — each build queries the store for the
  latest build number and adds 1 (Android via Google Play, iOS via TestFlight),
  so you won't hit "version code already used" rejections. The **version name**
  (`1.0.0`) still comes from `pubspec.yaml` — bump that for user-facing releases.
  Auto-increment needs step 3 (Play credentials) and the `APP_STORE_APPLE_ID`
  (step 4) set; until then it safely falls back to the pubspec build number.
- The old **Workflow Editor** settings are ignored once you switch to
  codemagic.yaml — that's intentional; the yaml is now the single source of truth.
