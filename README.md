# Baby Buddy for iPhone and Mac

A native SwiftUI infant tracker that works offline, with iCloud family sharing as the priority. No self-hosted backend or API account is required.

## Current build

The installed phone build is **0.1.0 (1)**. Current source is the **0.1.1 (2)** candidate, adding permission checks and account-change guards; it has not replaced the phone build yet.

- Create and edit a child profile; select among profiles received through iCloud.
- Log bottle feeds, breastfeeding by side and duration, and wet/dirty/mixed diapers.
- Start and stop sleep, including across app restarts.
- View daily totals and activity history; edit and confirm deletions.
- Save to a local Core Data SQLite database after every successful change.
- Import the prototype's JSON records without changing IDs or deleting the original file.
- Preserve concurrent additions and reject stale edits rather than overwriting them.
- Keep simultaneous offline sleep timers usable and count overlapping sleep only once.
- Provide App Intents for feeding, diaper changes and last-sleep queries, with device authentication.
- Include CKShare creation, caregiver management, invitation acceptance and private/shared stores.

**Sharing code is implemented but has not been verified with two Apple Accounts.** The default project is a local testing build; iCloud remains disabled until a developer team and container are configured. Use test data until the device acceptance checks below pass.

The supplied specification also calls for tummy time, solids, feeding timers, widgets, Live Activities, analytics and local reminders. Those remain unfinished.

## Run and install

Open `BabyBuddy.xcodeproj`, choose the **BabyBuddy** scheme, select an iPhone simulator or **My Mac (Mac Catalyst)**, and Run. The deployment target is iOS 17. There are no external dependencies.

For physical phones and iCloud setup, follow [INSTALL.md](INSTALL.md). A free Personal Team supports temporary local device tests. iCloud/CloudKit requires Apple Developer Program membership. Your app should not be treated as ready for family use until both phones pass the sharing checks.

Signing overrides belong in the ignored `Config/Signing.local.xcconfig`. They survive regeneration:

```sh
python3 tools/generate_xcode_project.py
```

The generated project reads `Config/Development.xcconfig` and the optional local overrides. Do not store Apple passwords or private keys in these files.

## Verification

Use the full Xcode toolchain if Command Line Tools is selected globally:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddy \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddy \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```

The most recent package run passed 25 tests: validation, disk round trips, timer restoration, JSON migration, corrupt-file preservation, simultaneous caregiver additions, stale edits, simultaneous offline timers, overlapping sleep, midnight counts, daylight-saving boundaries, permission failures, transaction rollback, removed-family records, stale open forms and account-change UI masking. These are local database tests, not proof of network synchronization.

The iPhone simulator, physical-iPhone (unsigned), and Mac Catalyst builds succeeded. The Mac app launches. Both automated simulator UI tests pass: profile creation, feeding and diaper logging, sleep-timer restoration after relaunch, invalid-entry handling and cancellation. The tests use isolated databases. The installed 0.1.0 result bundle is `/tmp/babybud-ui-tests-3`. The 0.1.1 candidate also passes both UI tests; its result bundle is `/tmp/babybud-ui-tests-4`. The candidate Mac build succeeds too.

Signed-device installation and launch have been verified. Two-account iCloud synchronization remains unverified.

## Persistence and sharing architecture

`Sources/BabyBuddyCore` contains the Codable domain types, validation, daily calculations, persistence repositories and the observable app store shared by the UI and App Intents. `iOS` contains SwiftUI, App Intents and the sharing controllers. The same core sources are compiled into the app and Swift package tests.

The specification proposes SwiftData. This implementation uses Apple's documented **Core Data + NSPersistentCloudKitContainer + CKShare** approach to support sharing between distinct caregiver accounts. SwiftData's automatic private sync is not assumed to provide that invitation flow. See [Apple's sharing documentation](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users).

Each child and activity is a separate managed object. Relationships connect activities to their child's share. Private and shared SQLite stores live under `Application Support/BabyBuddy/`. The retained `records.json` is a legacy backup, not the active database. The iOS database uses system file protection; this is not a claim of custom database encryption or end-to-end encryption of shared CloudKit records.

Only changed records are saved. Local stale edits are rejected. CloudKit's eventual conflict behavior, account changes and share revocation must still be exercised on real accounts; local tests do not prove those cases.

## Local build artifacts

Generated applications, device-specific packages, screenshots and signing overrides stay local and are excluded from version control. Device packages must be provisioned for each intended device. Local Mac test builds are not notarized distribution packages.

## Sharing hardening in the 0.1.1 candidate

Writes and deletions check CloudKit permissions, and a denied operation rolls back the whole save. The UI disables care mutations for a read-only profile. Activity payloads must match their stored IDs and child relationships, preventing silent cross-profile routing. Background notifications schedule UI refreshes asynchronously instead of synchronously calling the main queue.

An in-session iCloud account-change notification clears displayed records and blocks further operations until the app reopens. This is only an interim guard: **cold-start account isolation, sign-out/restart behavior and real share revocation still need two-account validation before family sharing can be considered ready**.
