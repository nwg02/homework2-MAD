# Message Board Vault Hunt

**CSC 4360 – Mobile App Development | Homework 02 | Fall 2026**

A Flutter message board using Firebase Authentication and Cloud Firestore. Signed-in users can create, read, edit, and delete their own messages. All signed-in users see the shared board update in real time, while Firestore Security Rules prevent unauthorized access.

**Repository:** https://github.com/nwg02/homework2-MAD  
**Firebase project:** `message-board-hw2`  
**Platforms used:** Android (APK) and Flutter Web (cross-device testing)

## Features

- Styled splash screen that initializes Firebase and provides a retry action if initialization fails.
- Email/password registration, login, logout, form validation, and `authStateChanges()` routing.
- Firestore profile for each account, keyed by its Firebase Authentication UID.
- Required profile-completion gate before the message board.
- Create, live-read, edit, and delete messages, with loading, empty, and error states.
- Real-time synchronization through Firestore `snapshots()`.
- Ownership-based editing and deletion enforced by Firestore Security Rules.
- Server timestamps for message creation and edits.
- Duplicate-submission protection using an in-flight button guard and transaction with a stable message ID.
- Optional Firebase Emulator Suite mode and automated security-rules tests.

## Technologies

Flutter, Dart, Firebase Core, Firebase Authentication, Cloud Firestore, Firebase CLI, FlutterFire CLI, Firebase Emulator Suite, Node.js, and `@firebase/rules-unit-testing`.

## Project structure

```text
lib/
  main.dart              Firebase initialization and splash screen
  firebase_options.dart  Generated FlutterFire platform configuration
  auth_service.dart      Authentication operations and auth-state stream
  auth_gate.dart         Login/registration interface and routing
  user_service.dart      Firestore profile operations and validation
  profile_gate.dart      Profile completion and access control
  board_service.dart     Message CRUD, live stream, and transaction
  board_screen.dart      Message UI and debug duplicate-write test
firestore.rules           Firestore access-control rules
firebase.json             Firebase and emulator configuration
rules-tests/
  rules.test.mjs         Automated security rules tests
  package.json
android/                  Android application
web/                      Flutter web application
```

## Setup and run

1. Install Flutter, Android Studio/Android SDK, Node.js, and Firebase CLI.
2. Create/select a Firebase project. Enable **Authentication → Email/Password** and create a **Cloud Firestore** database.
3. In the project root, install dependencies and configure FlutterFire:

```bash
flutter pub get
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android,web
```

Select your own Firebase project or, with appropriate access, `message-board-hw2`. FlutterFire generates `lib/firebase_options.dart`; it should not be handwritten.

4. Review `firestore.rules` and publish the rules in Firebase Console → Firestore Database → Rules. If using the CLI, confirm the selected Firebase project first:

```bash
firebase deploy --only firestore:rules
```

**Android:** Start an Android emulator or connect a device, then run:

```bash
flutter devices
flutter run
```

**Web:** Run:

```bash
flutter run -d web-server --web-port=8085
```

Open `http://localhost:8085`. Configure Firebase Authentication's authorized domains for local web testing if needed.

## Authentication and navigation

`main.dart` initializes Firebase behind the splash screen. `AuthService` centralizes registration, sign-in, sign-out, current-user access, and an `authStateChanges()` stream. `AuthGate` shows authentication screens when signed out. After sign-in, `ProfileGate` checks for a complete Firestore user record; a missing profile must be completed before the message board opens.

Firebase Authentication manages user credentials. **Passwords are never stored in the Firestore user records.**

## Firestore data model and field writers

### `users/{uid}` — private profile

| Field | Type | Writer / reason |
| --- | --- | --- |
| `uid` | String | Client on registration; matches authenticated UID |
| `firstName` | String | Client on profile completion; display identity |
| `lastName` | String | Client on profile completion; display identity |
| `role` | String | Client writes fixed value `member`; descriptive, not privileged |
| `registrationDateTime` | Timestamp | Client requests `serverTimestamp()`; server provides time |

A single document is keyed by the authenticated user's UID. Rules allow the owner to read and create the profile. Profile updates and deletes are denied in this version.

### `messages/{messageId}` — shared board

| Field | Type | Writer / reason |
| --- | --- | --- |
| `text` | String | Author creates/edits; 1–500 characters |
| `authorUid` | String | Author on creation; immutable ownership ID |
| `authorName` | String | Author on creation; must match their profile name |
| `createdAt` | Timestamp | Client requests server timestamp on creation; immutable |
| `editedAt` | Timestamp or null | Null on creation, server timestamp when edited |

`BoardService` centralizes all message Firestore operations. Its `messageBoard()` method sorts by `createdAt` and uses `snapshots()` so the interface updates without refreshing. Updates and deletes address one document by ID.

**Placement decision:** Messages are shared so all authenticated users can subscribe to one board. Profiles remain private under each user's UID. The `authorUid` stored on every message allows rules to verify authorship independently of buttons in the app. A client-written `role` never grants elevated authorization.

## Security and authorization

The `firestore.rules` file enforces:

- Signed-out message reads are denied.
- Signed-in users can read board messages.
- Message creation requires the authenticated author's UID, a matching profile name, valid text, and a server timestamp.
- Message updates are allowed only for the author and only for `text` and `editedAt`.
- Message deletes are allowed only for the author.
- Users cannot read another account's private profile.

**Authentication** establishes who the user is; **authorization** determines what Firestore documents the user can access. Hiding an Edit or Delete button is helpful UI behavior but is not a replacement for security rules.

## Manual verification: Auth and CRUD

1. Register, sign in, and complete a profile; confirm all five fields in `users/{uid}` in Firestore.
2. Create a message and check that it appears on the board and in Firestore.
3. Confirm messages load through the live stream, including an intentional empty-board state.
4. Edit your own message and verify that `editedAt` changes.
5. Delete exactly one message and verify other messages remain.
6. Sign out, sign in again, and confirm messages persist.
7. Sign in as another account on a second client (Android emulator and Safari). Verify a post appears on both without refresh.
8. Verify other users lack edit/delete UI controls, and test the actual authorization denials through the rules test suite.
9. Rapidly double-submit a message and inspect Firestore to confirm only one intended document.

## Extra Spice #1: Firebase Emulator Explorer

Start the local Firebase emulators from the project root:

```bash
firebase emulators:start --only auth,firestore
```

Configured ports: Authentication **9099**, Firestore **8080**, Emulator UI **4000**.

From a second terminal, run the web app against local emulators:

```bash
flutter run -d web-server --web-port=8086 --dart-define=USE_FIREBASE_EMULATORS=true
```

Open `http://localhost:8086`, register a fictional test account, and try CRUD. View the local records at `http://localhost:4000`. Compare with the production Firebase Console to confirm emulator-only accounts and messages were not written to production. The flag is optional: without it, the app uses its configured production Firebase project. Android emulators use host `10.0.2.2` instead of `localhost`.

## Extra Spice #2: Automated Rules Unit Tester

The `rules-tests/rules.test.mjs` suite uses the local Firestore emulator, fictional Alice/Bob accounts, and Firebase's `assertFails` / `assertSucceeds` methods. It covers seven scenarios:

1. Signed-out read denied.
2. Cross-user update denied.
3. Cross-user delete denied.
4. Forged `authorUid` creation denied.
5. Authenticated message read allowed.
6. Correct-author create/read/update/delete allowed.
7. Cross-user private profile read denied.

With the emulators running:

```bash
cd rules-tests
npm ci
node --test rules.test.mjs
```

The tests seed data with rules disabled **only inside the local test environment**. Inspect terminal output for actual results. These tests do not edit production Firestore data.

## Extra Spice #4: Idempotent Alchemist

`BoardService.postMessage()` uses a predetermined message ID in a Firestore transaction. If that document does not exist, the transaction creates it. When retried with the same ID and content, it skips the second write; a conflicting ID/content combination raises an error.

In debug builds, a science icon runs two submissions with the same ID. The expected output is **CREATED** followed by **SKIPPED**, with exactly one corresponding Firestore document. The Post button is disabled while a send is pending.

**Trade-off:** Firestore transactions require network connectivity. The pending message ID is only retained in the current widget session, so retry state does not survive an app restart. Different IDs are not treated as duplicate messages.

## Required Main Spice: Release APK

Build the Android release APK **without** the emulator flag:

```bash
flutter build apk --release
```

APK location:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Install the **same APK that will be submitted**:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Test splash, registration/login, complete profile, create/read/edit/delete, live updates from a second client, sign-out, ownership and rules denials, and duplicate submission on the release build. Record device, APK version, expected/observed outcomes, and screenshots in the separate evidence document. Local rules tests support the denial evidence but do not replace release-build testing.

## Assignment submission

Submit three items through the LMS: **(1)** this GitHub repository URL, **(2)** the tested release APK, and **(3)** one Word or PDF evidence/reflection document. The document should contain captioned screenshots, test results, Main/Extra Spice evidence, the undergraduate AI Lab comparison, two critical-thinking case files, reflections, and official-source references.

## Official references

- [FlutterFire setup](https://firebase.google.com/docs/flutter/setup)
- [Firebase Authentication for Flutter](https://firebase.google.com/docs/auth/flutter/start)
- [Cloud Firestore for Flutter](https://firebase.google.com/docs/firestore/quickstart#dart)
- [Firestore real-time listeners](https://firebase.google.com/docs/firestore/query-data/listen)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite)
- [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions)
