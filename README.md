# Baby Buddy for iPhone

A native SwiftUI starting point for offline infant care tracking. All implementation code here is original; no Baby Buddy code or assets have been copied.


## Implemented in this first milestone

- Create and edit one child's name and birth date.
- Log bottle feeds in milliliters, breastfeeds by side and minutes, and wet/dirty/mixed diapers.
- Start and stop a sleep timer. The start timestamp is persisted, including across app restarts.
- See today's feeding count, diaper count and sleep duration, plus recent activity.
- View history, edit saved entries, and confirm deletions.
- Save every successful change to a local JSON file with an atomic write. On iOS, the file uses complete file protection.
- Validate times, measurements, record IDs, child references and duplicate running sleep timers.
- Preserve an unreadable data file and block writes rather than replacing it with an empty history.

**iCloud sync and invitations are not implemented.** The Family tab states this explicitly. This version stores records only on the device, has no export/restore screen yet, and is an early development build. Use test data until the build and persistence behavior have been verified on a Mac and iPhone.

## Open on a Mac

1. Copy this folder to a Mac with Xcode 15 or later and the iOS 17 SDK or later.
2. Open `BabyBuddy.xcodeproj` and select the **BabyBuddy** scheme.
3. Select an iPhone simulator and press Run.
4. For a physical iPhone, open the target's **Signing & Capabilities**, choose your development team, and replace `org.example.BabyBuddy` with a unique bundle identifier. Then select your iPhone and Run.

The checked-in project needs no external dependencies or project generator. It targets iOS 17 and later. The app icon and distribution configuration are still to be added.

If Swift source files are added or removed, regenerate the project before reapplying local signing changes:

```sh
python3 tools/generate_xcode_project.py
```

The generator rewrites the project configuration and shared scheme, including resetting its bundle identifier to the development placeholder.

## Verification

On a Mac, run the Foundation-only domain and persistence tests from this folder:

```sh
swift test
```

Build the app for a simulator without signing:

```sh
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddy \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The package tests cover disk round trips, timer restoration, corrupt-file preservation, failed-save preservation, invalid entries, duplicate records, midnight splitting, and the 23-hour spring daylight-saving day in Stockholm. They do not exercise SwiftUI or the app store object.

This workspace was initialized on Windows without Swift or Xcode. **The Swift tests and iOS build have not been run here.** The project generator and project source/scheme wiring have been checked locally.

Manual checks for the first Mac/iPhone run:

1. Create a child, log a bottle and a diaper, and verify both the dashboard and history update.
2. Log a breastfeeding entry with a decimal duration (including a comma decimal separator with a Swedish device locale).
3. Start sleep, terminate and reopen the app, then stop sleep. Verify only one sleep record exists and the elapsed time includes the time the app was closed.
4. Edit an activity and cancel another edit. Verify only the saved edit is retained after relaunch.
5. Delete an activity using the history swipe action, confirm, and verify it stays deleted after relaunch.
6. Check large text, VoiceOver, dark appearance, and landscape layout.

## Structure and persistence choice

`Sources/BabyBuddyCore` contains Codable value models, validation, day calculations and a small `SnapshotRepository` interface. The same sources are compiled into the iOS target and independently exercised through a Swift package test target.

`iOS` contains the SwiftUI app and a main-actor observable store. Mutations are validated and saved before becoming visible in memory. The file is located at `Application Support/BabyBuddy/records.json` inside the app sandbox. Occurrence time is separate from creation/edit timestamps; IDs are stable UUIDs.

The plan proposed SwiftData. This first slice deliberately uses a small JSON repository to keep local persistence replaceable while the sharing architecture is proven. It is not a synchronization implementation: a whole-file store must not be used to merge family changes. Keep the user interface and domain model, then replace the storage layer with a persistence approach chosen alongside the CloudKit proof of concept. Apple's [Core Data sharing sample](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users) and [direct CloudKit sharing sample](https://github.com/apple/sample-cloudkit-sharing) provide two concrete options to evaluate.

## Next milestone: family-sharing proof

Before adding charts or more activity types, test one shared child and feeding/diaper records across two Apple accounts:

- Create a private share, invite a caregiver, and accept on the other device.
- Verify records added from either account arrive on both devices.
- Persist an offline change queue and test reconnects, retries, and duplicate prevention.
- Test concurrent edits, tombstones for deletions, and caregiver removal.
- Handle iCloud sign-out, account changes, and share revocation without leaking one family's records into another account.

That milestone requires a Mac, configured CloudKit capabilities/container, appropriate Apple developer provisioning, and two iCloud accounts. The current target enables no iCloud capability and sends no records to a server.
