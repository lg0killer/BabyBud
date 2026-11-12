# Install on your two iPhones

## Local tests with your current Personal Team

1. Connect an iPhone by USB, unlock it, and accept the Trust prompt.
2. Open `BabyBuddy.xcodeproj`. Select the BabyBuddy target, then Signing & Capabilities.
3. Enable automatic signing, choose your Personal Team, and use a unique bundle ID such as `com.yourfamily.BabyBuddy`.
4. Leave the iCloud container and entitlement overrides empty for a Personal Team build. Do not add iCloud or Push Notifications capabilities to this free-team build.
5. Select your connected iPhone as the run destination. Follow Xcode's prompts to enable Developer Mode on the phone if needed, then press Run.
6. Repeat on the second phone. Each keeps separate local records until family sharing is enabled.

If iOS blocks the first launch, open **Settings → General → VPN & Device Management**, select your Apple Development profile and establish trust. Complete any **Allow & Restart** prompt on the phone, reconnect and unlock it, then launch Baby Buddy again. See [Apple's developer trust guide](https://help.apple.com/xcode/mac/current/en.lproj/dev96a12fb84.html).

Apple's free provisioning profiles expire after seven days, so these builds need regular rebuilding. [Apple account limits](https://developer.apple.com/help/account/basics/about-your-developer-account)

To preserve signing settings across project regeneration, put the Team ID and bundle ID in the ignored local configuration:

```sh
python3 tools/configure_signing.py --team YOURTEAMID --bundle com.yourfamily.BabyBuddy --local-only
```

Replace the placeholders with your actual values. If the local configuration already exists, edit it rather than overwriting it. Xcode can create the signing certificate and development profile when a phone is connected.

## Enable iCloud family sharing

CloudKit needs a paid Apple Developer Program membership; a Personal Team cannot provision this capability. [Apple CloudKit sample requirements](https://github.com/apple/sample-cloudkit-sharing)

1. In the developer account, register the app bundle ID and an iCloud container. Associate that container with the app.
2. In Xcode, choose the paid team. Enable **iCloud → CloudKit**, select the registered container, and enable **Push Notifications**. The project already declares background remote notifications and CloudKit share acceptance.
3. Configure these values in `Config/Signing.local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOURTEAMID
BABYBUDDY_BUNDLE_IDENTIFIER = com.yourfamily.BabyBuddy
BABYBUDDY_CLOUD_CONTAINER = iCloud.com.yourfamily.BabyBuddy
BABYBUDDY_ENTITLEMENTS = iOS/BabyBuddy.entitlements
BABYBUDDY_MAC_ENTITLEMENTS = iOS/BabyBuddyMac.entitlements
```

4. Build on both phones with the same bundle ID, container and CloudKit environment. Each phone should use its caregiver's own iCloud account. The app's development signing team is separate from those iCloud accounts.
5. On one phone only, create the child profile. Wait for the Family screen to show a successful iCloud transfer.
6. In **Family**, choose **Invite or manage caregivers**, keep access restricted to invited people, and send the invitation to your partner. The invitation permits editing that child's care records.
7. On the other phone, open and accept the invitation. Wait for the shared child to appear. Do not create a duplicate profile for the same child.
8. Select that child in Family and perform the acceptance checks below before relying on shared records.

Signing does not prove synchronization works. The account and two-device checks remain necessary. For TestFlight, deploy the CloudKit schema to **Production** in CloudKit Console, use production push signing, and install matching TestFlight builds on both devices. Do not mix Development and Production builds while testing the same family.

## Acceptance checks before family use

- Log a feeding on each phone. Both additions must appear on both phones.
- Edit a record on one phone; verify the edit on the other. Verify cancel leaves it unchanged.
- Delete a test record, confirm deletion and verify it stays deleted after both apps restart.
- Start sleep, terminate and reopen the app, then stop it. The original start time must survive.
- Disconnect both phones, add different activities, then reconnect. Neither addition may be lost or duplicated.
- Start sleep on both phones offline, then reconnect. End sleep must remain possible and overlapping time must count once.
- Edit the same record concurrently. Record the observed conflict outcome and verify no unrelated entries disappear.
- Remove a caregiver and verify their shared child disappears after iCloud processes the revocation; they must not be able to keep writing to that share.
- Test iCloud sign-out and account changes with disposable data; verify one family's records never appear under another account.
- Check dark mode, large text, VoiceOver and phone rotation.

No live invitation, two-account sync, revocation or account-switch test has passed yet. Keep using test data until those checks are complete.

## MacBook

Choose **My Mac (Mac Catalyst)** and Run in Xcode. With matching iCloud signing and the same caregiver account, it should use the same container; verify that behavior before relying on it. The default unsigned/local build keeps a separate Mac database.
