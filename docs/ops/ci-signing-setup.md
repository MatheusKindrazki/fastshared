# CI code signing setup (persistent certificate)

The Apple release/production workflows sign with a **persistent Apple
Distribution certificate** plus committed-as-secret provisioning profiles —
manual signing, no `-allowProvisioningUpdates`. This stops CI from minting a
throwaway Development certificate on every run (which exhausted the account's
certificate limit and broke every archive).

The workflows consume three GitHub secrets you must create once (in addition to
the existing `APPSTORE_CONNECT_*` secrets):

| Secret | Contents |
| --- | --- |
| `BUILD_CERT_P12_B64` | Base64 of your Apple Distribution `.p12` export |
| `BUILD_CERT_PASSWORD` | Password you set when exporting the `.p12` |
| `PROVISIONING_PROFILES_B64` | Base64 of a `.tar.gz` of all App Store profiles |

## 0. Clean up the throwaway certificates first

In the Apple Developer portal → **Certificates**, revoke every
`Created via API` / **Development** certificate (these are CI garbage). Keep:
- `iOS Distribution` (the active one)
- `Developer ID Application` (macOS)
- `Distribution Managed`
- your local `Apple Development` (on your Mac)

## 1. Export the Distribution certificate (.p12)

In **Keychain Access** on your Mac:
1. Find **Apple Distribution: MATHEUS SALDANHA (YFYB6NKC73)** (expand it to confirm it has a private key).
2. Right-click → **Export** → format **Personal Information Exchange (.p12)** → save as `dist.p12`, set a password.
3. Base64 it and push as a secret:
   ```bash
   base64 -i dist.p12 | gh secret set BUILD_CERT_P12_B64
   gh secret set BUILD_CERT_PASSWORD   # paste the .p12 password when prompted
   ```

## 2. Download the App Store provisioning profiles

You need one **App Store** profile per bundle id, each tied to the Distribution
cert above. In the portal → **Profiles**, create/download App Store profiles for:
- `dev.kindrazki.fastshared` (iOS + macOS)
- `dev.kindrazki.fastshared.ShareExt` (iOS + macOS)
- `dev.kindrazki.fastshared.LiveActivity` (iOS)
- `dev.kindrazki.fastshared.LoginItem` (macOS)

iOS profiles are `.mobileprovision`; macOS are `.provisionprofile`. Put them all
in one folder, then:
```bash
cd ~/Downloads/fastshared-profiles
tar -czf profiles.tar.gz *.mobileprovision *.provisionprofile
base64 -i profiles.tar.gz | gh secret set PROVISIONING_PROFILES_B64
```

## 3. Trigger a build

Once the three secrets exist:
```bash
# Archive (signed, both platforms) — inspect artifacts in the run:
git push --force origin apple-v1.0.2   # re-trigger, or push a new apple-v* tag

# Promote to TestFlight (manual, both platforms):
gh workflow run apple-production.yml -f confirm=PROMOTE
```

The `setup-apple-signing` composite action
(`.github/actions/setup-apple-signing`) imports the `.p12` into a temporary
keychain and installs the profiles before `xcodebuild`. If signing fails, check
that the profiles match the Distribution cert and that all four bundle ids are
covered.
