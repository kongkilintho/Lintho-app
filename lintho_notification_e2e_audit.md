# LinTho Notification System — End-to-End Audit
**Scope:** Admin Panel (`lintho-admin`, Next.js) → Cloud Functions (`lintho-app/functions`) → FCM → Customer/Provider App (`lintho-app`, Flutter)
**Date:** 2026-08-08
**Method:** Full source-code trace across both repositories. No code was modified. No live device test was performed (see §14).

---

## 0. Executive Summary

The notification pipeline is **real** — this is not a mocked feature. Admin panel writes → Cloud Function trigger → real `admin.messaging().sendEachForMulticast()` → real FCM → real `firebase_messaging` SDK handlers in the Flutter app. However:

- **The Admin UI's "Sent" status is not proof of delivery.** It only proves a Firestore write succeeded (see §2 classification below).
- **One Critical vulnerability**: any authenticated Customer or Provider can write directly to the `fcm_queue` collection and impersonate an admin broadcast (or any notification type) targeting **any other user**, because the collection's create rule has no admin check and no target-ownership check.
- **One High-risk delivery gap**: Android notification channels referenced in every push payload (`lintho_chat`, `lintho_jobs`, `lintho_payment`) are never created anywhere in the app — no `flutter_local_notifications`, no native channel registration, no manifest default. This can silently suppress background/terminated notifications on Android 8+.
- A client-side Firestore listener meant to catch queued notifications in-app (`_watchFCMQueue`) is permanently broken by the security rules it's subject to — dead code that always fails silently.
- Admin → Specific Provider silently mis-tags the recipient's role in the queue record (works today only by coincidence of how tokens are mirrored).
- There is no notification history UI in the Customer/Provider app at all — the bell icon opens Chat/Promotions/Support tabs, not a notification list.
- FCM tokens are never removed on logout (dead `removeToken()` function) and are never cleaned up when FCM reports them invalid.

---

## 1. Notification Architecture (exact files/functions/collections)

```
Admin Panel (Next.js, lintho-admin)
  src/app/notifications/page.tsx           — Compose UI + history list
  src/lib/hooks/index.ts
    useSendNotification()                  — line 957: resolves targets, batches writes to fcm_queue,
                                               writes 1 summary doc to `notifications`, writes 1 `auditLogs` doc
    resolveNotificationTargets()            — line 896: turns target selector into {id, role}[]
    useNotificationHistory()                — line 929: reads `notifications` collection (client SDK)
        │
        ▼ writeBatch() — Firestore client SDK, browser-side, authenticated as the logged-in admin
  Firestore: fcm_queue/{autoId or dedupeKey}   { targetUserId, targetRole, type, title, body, data, sent:false }
  Firestore: notifications/{autoId}            { title, body, channel, target, sentCount, status:'sent', sentAt, createdAt }
  Firestore: auditLogs/{autoId}                { adminId, adminName, adminRole, action:'notification.send', ... }
        │
        ▼ Firestore onCreate trigger (server-side, Cloud Functions, Admin SDK — bypasses all security rules)
Cloud Functions (lintho-app/functions/index.js)
  exports.processFCMQueue                   — line 78: fires on every fcm_queue/{docId} create
    → reads users/{uid} or providers/{uid} depending on targetRole
    → reads .fcmTokens array (string[])
    → admin.messaging().sendEachForMulticast({ notification:{title,body}, data, android:{...}, apns:{...}, tokens })
    → writes back { sent:true, successCount } (or {sent:true, error}) — ONLY onto the fcm_queue doc, never
      propagated to the `notifications` history doc the admin UI reads
  exports.onBookingStatusChange              — line 104: queues booking-lifecycle notifications (accept/reject/etc.)
  exports.onNewBooking                       — line 480: queues "new booking" notifications to matched providers
  exports.cleanupExpiredBookings             — line 342: queues expiry notifications (pubsub, every 5 min)
  exports.cleanupStaleActiveBookings          — line 386: queues stale-booking notifications (pubsub, every 30 min)
  exports.cleanupOldFcmQueue                  — line 448: deletes sent fcm_queue docs older than 7 days (pubsub, daily)
  queueNotification()                         — line 52: shared helper; honors users/{uid}.notifPrefs, dedupe key
        │
        ▼ FCM (Google) → device
Customer/Provider App (lintho-app, Flutter — single codebase, role decided at runtime)
  lib/main.dart:104        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)  — top-level handler registration
  lib/main.dart:241        RoleRouter.initState() → FCMService.instance.init()                        — fires for both roles
  lib/fcm_service.dart
    FCMService.init()          line 47  — requests permission, gets token, saveToken(), registers onMessage/
                                           onMessageOpenedApp/getInitialMessage listeners, starts _watchFCMQueue()
    saveToken()                line 159 — writes token to users/{uid}.fcmTokens (arrayUnion), mirrors to
                                           providers/{uid}.fcmTokens if role=='provider'
    removeToken()               line 178 — defined, DEAD CODE (never called — see §7 Finding N-06)
    _onForeground()              line 188 — FirebaseMessaging.onMessage handler → in-app SnackBar banner
    _onTap()/_navigate()         line 199/213 — onMessageOpenedApp + getInitialMessage → screen routing by data.type
    _watchFCMQueue()             line 71  — Firestore listener on fcm_queue (BROKEN, see §7 Finding N-02)
    NotificationSender           line 292 — client-side writer to fcm_queue for booking-adjacent events
                                           (chat, review, additional charges) — called from chat_screen.dart:484,
                                           review_screen.dart:155, booking_repository.dart:467
  lib/notification_screen.dart  — bell-icon screen; NOT a notification history/log — 3 tabs: Chat / Promotions / Support
```

**FCM server credentials/configuration:** `admin.initializeApp()` with no arguments (functions/index.js:5) — uses the Cloud Functions runtime's default service account. No service-account JSON or API key appears in client code (`lintho-admin` or `lintho-app`). **PASS** — server credentials are never exposed to Flutter or the browser.

**Token storage:** `users/{uid}.fcmTokens` (all roles) and, additionally, `providers/{uid}.fcmTokens` (mirrored for role=='provider'). Both are plain arrays of token strings, updated via `FieldValue.arrayUnion`.

---

## 2. Admin Panel Result

| Capability | Status | Evidence |
|---|---|---|
| Send to all customers | **Works** | `resolveNotificationTargets('customers')` queries `users`, filters `role==='customer'` |
| Send to all providers | **Works, but unfiltered** | queries entire `providers` collection — no `kycStatus`/`status` filter despite UI label "All active providers" (Finding N-05) |
| Send to specific customer | **Works** | 'specific' branch resolves via `users` doc lookup |
| Send to specific provider | **Works, mis-tagged** | resolves role incorrectly as 'customer' (Finding N-04) — delivery itself is not broken today only because of a coincidence in how tokens are mirrored |
| Send to selected/multiple users | **Works** | newline/comma-separated ID textarea |
| Send by role | **Works** | 'customers'/'providers' targets are role-based |
| Title | **Works** | required for push (disabled Send button if empty) |
| Message/body | **Works** | required, no length cap for push (160-char cap only applies to the disabled SMS channel) |
| Image | **Not implemented** | no image field anywhere in the composer, the `fcm_queue` payload, or the `sendEachForMulticast` call |
| Deep-link/action | **Not implemented for admin sends** | `type:'admin_broadcast'` is never handled by `FCMService._navigate()` — tapping does nothing (Finding N-07) |
| Input validation | **Partial** | Send button disabled until title+body non-empty (push) or specific IDs present; no server-side revalidation of title/body length or content |
| Permission checks | **UI-only for tier, real for coarse admin flag** | `RequireRole` (client component, `useAuthStore` in-memory/localStorage) restricts the page to 3 admin tiers; Firestore rules only enforce the coarse `role=='admin'` flag for the `notifications` write path (blanket-bypass rule, not tier-aware) — consistent with the already-documented ADM-5 pattern in this codebase |
| Admin authorization | **Real** | `realAuthApi.login()` uses actual Firebase Auth (`signInWithEmailAndPassword`) plus a Firestore `users/{uid}.role` check |
| Duplicate-send protection | **Weak** | `sendMutation.isPending` disables the button while in flight; no server-side idempotency key |
| Error handling | **Good** | scheduled sends and non-push channels are explicitly rejected with a thrown error (not silently accepted as success); "no matching recipients" is also rejected |
| Success/failure reporting | **Misleading, see below** | |

### What does "Send successful" actually mean? (explicit classification requested by the audit)

> **It means (A) + partially (B). It does NOT mean (C) or (D).**

- **(A) Notification record created** — YES. `addDoc(collection(db,'notifications'), {status:'sent', sentCount: targets.length, ...})` happens unconditionally once the `fcm_queue` batch writes resolve (lintho-admin/src/lib/hooks/index.ts:998-1007).
- **(B) FCM request accepted** — Only indirectly and asynchronously. The `mutate()` call that shows the toast resolves as soon as the `fcm_queue` **Firestore writes** succeed — this is *before* `processFCMQueue` (the Cloud Function that actually calls `messaging.sendEachForMulticast`) has even started running. The admin UI never awaits or observes that function.
- **(C) FCM actually delivered to device** — NO. `processFCMQueue` records `successCount`/`error` **only on the `fcm_queue` doc itself** (functions/index.js:98,100) — nothing ever writes that result back onto the `notifications` history doc the admin actually reads. The history's `sentCount` is the number of *resolved recipients*, not the number of successful FCM sends.
- **(D) App received the notification** — NO. Nothing in this pipeline observes device-side receipt at all.

**`sentCount` in the admin history list is therefore the count of Firestore documents queued, not the count of notifications delivered.**

---

## 3. Customer Notification Result

| Item | Status | Evidence |
|---|---|---|
| FCM registration | **CODE VERIFIED** | `FCMService.init()` runs for every logged-in user via `RoleRouter.initState()` (main.dart:241) |
| Device token generation | **CODE VERIFIED** | `_messaging.getToken()` (fcm_service.dart:58) |
| Token stored in Firestore | **CODE VERIFIED** | `users/{uid}.fcmTokens` arrayUnion (fcm_service.dart:163-166) |
| Token refresh | **CODE VERIFIED** | `_messaging.onTokenRefresh.listen(saveToken)` (fcm_service.dart:60) |
| Token invalidation on logout | **NOT IMPLEMENTED** | `removeToken()` exists (fcm_service.dart:178) but is never called — grepped every `signOut()` call site (main.dart:347,2967,3027,4587; pending_approval_screen.dart:110; profile_tab.dart:282) — none call it. See Finding N-06. |
| Permission request | **CODE VERIFIED** | `requestPermission(alert:true, badge:true, sound:true)` (fcm_service.dart:51) |
| Notification permission state | **Not surfaced to UI** | no code path reads/displays whether permission was denied; app doesn't detect or warn a customer who denied notifications |
| Foreground handling | **CODE VERIFIED** | `FirebaseMessaging.onMessage.listen(_onForeground)` → custom SnackBar banner |
| Background handling | **CODE VERIFIED (registration) / not device-confirmed** | top-level `firebaseMessagingBackgroundHandler` registered (main.dart:104); actual OS display depends on the Android-channel gap, Finding N-03 |
| Terminated-app handling | **CODE VERIFIED (registration) / not device-confirmed** | `getInitialMessage()` (fcm_service.dart:65-66) handles a notification tapped from a killed state; same channel-gap caveat applies |
| Notification tap handling | **CODE VERIFIED** | `_onTap`/`_navigate` route by `data.type` for `new_booking`, `booking_update`, `additional_charges`, `chat`, `payment` |
| Deep-link navigation | **PARTIAL** | works for the 5 internally-generated types; **not implemented for `admin_broadcast`** (Finding N-07) |
| Notification badge | **Partial** | `apns:{payload:{aps:{badge:1}}}` is hardcoded to `1` for every push (functions/index.js:95) — not an incrementing unread count; no equivalent Android badge logic |
| Notification history | **NOT IMPLEMENTED** | `notification_screen.dart` (the bell-icon screen) has no notification list at all — see Finding N-08 |

**Would the correct Customer receive an Admin → Customer notification?** CODE VERIFIED for the resolution/dispatch path (correct `users/{uid}` doc queried, correct tokens read, correct FCM call made). Actual on-device receipt is **NOT TESTABLE** in this audit (no device/emulator available) and is further put at risk by Finding N-03.

---

## 4. Provider Notification Result

| Item | Status | Evidence |
|---|---|---|
| FCM registration / device token | **CODE VERIFIED** | identical `FCMService.init()` path — single codebase, role-agnostic |
| Token storage | **CODE VERIFIED** | mirrored to `providers/{uid}.fcmTokens` in addition to `users/{uid}.fcmTokens` (fcm_service.dart:170-175) |
| Token refresh | **CODE VERIFIED** | same `onTokenRefresh` listener, same `saveToken()` |
| Notification permission | **CODE VERIFIED** | same `requestPermission()` call |
| Foreground/background/terminated handling | **Same as Customer** — see §3, and Finding N-03 caveat |
| Notification tap | **CODE VERIFIED** | `new_booking` → `JobWorkflowScreen`; `payment` → `ProviderDashboard` earnings tab (index 2) |
| Deep-link navigation | **PARTIAL** | same `admin_broadcast` gap as Customer (Finding N-07) |
| Notification history | **NOT IMPLEMENTED** | same shared screen as Customer, no history list |
| Badge/count | **Same hardcoded `badge:1`** as Customer |

**Would the correct Provider receive an Admin → Provider notification?** CODE VERIFIED for the resolution/dispatch path. **Admin → Specific Provider** additionally carries the role-mislabeling bug (Finding N-04): the queued record says `targetRole:'customer'`, and delivery only still works today because `saveToken()` happens to write the same tokens into both `users/{uid}` and `providers/{uid}` for a provider account — an incidental, not designed, safety net.

---

## 5. FCM Result

- **Server call:** `admin.messaging().sendEachForMulticast(...)` — correct, current (non-deprecated) Admin SDK method, called with `android:{priority:'high', notification:{sound:'default', channelId:...}}` and `apns:{payload:{aps:{sound:'default', badge:1}}}`. **CODE VERIFIED**.
- **Result handling:** `result.successCount` is captured but `result.responses` (per-token success/failure detail) is **never inspected** — no per-token failure is ever detected, logged, or acted on. **Finding N-09.**
- **Token limit:** `sendEachForMulticast` caps at 500 tokens per call; since tokens are never pruned (Finding N-09/N-06), a long-lived account with many device installs/reinstalls could theoretically exceed this — low probability, not observed, flagged for completeness.
- **Multiple devices per user:** supported by design — `fcmTokens` is an array, and the call passes all tokens to a single multicast send. **PASS.**
- **Multiple tokens / duplicate token prevention:** `FieldValue.arrayUnion` prevents literal duplicate token strings. **PASS** for de-duplication; **FAIL** for staleness (see N-06/N-09).

---

## 6. Backend (Cloud Functions) Result

- `processFCMQueue` is a Firestore `onCreate` trigger — fires once per `fcm_queue` doc, at-least-once semantics (standard Cloud Functions guarantee). Idempotency for *server-originated* notifications (booking events) is handled via `queueNotification()`'s optional `dedupeKey` → deterministic doc ID (functions/index.js:52-76), which was a prior audit fix (BE-2). **PASS** for those paths.
- Admin-broadcast and client-side `NotificationSender` writes do **not** use a `dedupeKey` (`useSendNotification` calls `batch.set(doc(collection(db,'fcm_queue')))` with an auto-ID; `NotificationSender._send()` uses `.add()`) — these are one-shot, user/admin-initiated actions where duplicate delivery from function retries is a low-probability edge case, not a routine one. Acceptable risk, noted for completeness.
- Retry/error handling in `processFCMQueue`: on any thrown error, the function catches it and marks `sent:true, error: err.message` (functions/index.js:99-100) rather than leaving the doc `sent:false` for an automatic retry. This means **a transient FCM outage or token-lookup failure permanently drops that notification** — it will never be retried. This is a deliberate-looking choice (avoids duplicate sends on retry) but trades away reliability for transient failures. **Finding N-10.**
- `cleanupOldFcmQueue` (daily, deletes `sent:true` docs >7 days old) provides reasonable outbox retention. **PASS.**

---

## 7. Findings

### CRITICAL

**Issue ID:** N-01 — ✅ **FIXED 2026-08-08** (see note at end of this entry)
**Severity:** Critical
**System:** Security / Firestore Rules / Cloud Functions
**Exact file:** `lintho-app/firestore.rules` lines 947-952; `lintho-app/functions/index.js` lines 78-102 (`processFCMQueue`)
**Function:** `match /fcm_queue/{queueId}` create rule; `exports.processFCMQueue`
**Evidence:**
```
match /fcm_queue/{queueId} {
  allow create: if isAuth() &&
    request.resource.data.sent == false &&
    request.resource.data.targetUserId is string;
  allow read, update, delete: if false;
}
```
This rule has **no `isAdmin()` check and no check that `targetUserId` belongs to, or has any relationship with, `request.auth.uid`.** Any authenticated Customer or Provider can write a document such as:
```js
db.collection('fcm_queue').add({
  targetUserId: '<any other user's uid>',
  targetRole: 'customer',       // or 'provider'
  type: 'admin_broadcast',      // or any type
  title: 'LinTho Admin',
  body: 'Your account will be suspended — verify now: <phishing link text>',
  data: { type: 'admin_broadcast' },
  sent: false,
})
```
`processFCMQueue` (server-side, Admin SDK — bypasses all rules) unconditionally trusts this document: it looks up `targetUserId`'s real tokens and calls `sendEachForMulticast` with the attacker-supplied `title`/`body`. The resulting push is **indistinguishable from a genuine admin broadcast** to the recipient.
**Expected:** Only an authenticated admin (or a trusted server-side actor) should be able to enqueue a notification targeting an arbitrary other user; a regular user should only be able to trigger notifications tied to their own bookings/chats, to the actual counterparty of that booking.
**Actual:** Any authenticated user can target any other user with arbitrary title/body/type content.
**Root Cause:** The `fcm_queue` create rule was written to unblock the app's legitimate client-side `NotificationSender` calls (chat/review/additional-charges — see the `FOLLOWUP-5` comment directly above this rule) but was scoped far too broadly — it validates document *shape*, not sender *authority* or *relationship to the target*.
**Recommended Fix:** Require either (a) `isAdmin()`, or (b) proof the sender is a party to the booking referenced by `bookingId` (e.g. `get(/databases/$(database)/documents/bookings/$(request.resource.data.bookingId)).data.customerId == request.auth.uid || ...providerId == request.auth.uid`) before allowing `create`. Reject `type == 'admin_broadcast'` from non-admin writers explicitly.

**Fix applied (2026-08-08):** `firestore.rules` — added `fcmBookingAuthorized(bookingId, targetUserId)` (new function, placed after `isVerifiedProvider()`) and rewrote the `fcm_queue` create rule to require `isAdmin()` **or** (`type` in `['chat','review','additional_charges']` **and** `fcmBookingAuthorized(...)` — i.e. the caller and the target must both be the customer/provider of the referenced `bookingId`, and the caller can't target themselves). This closes the spoofing hole while preserving the 3 real client-side call sites (`NotificationSender.chatMessage`/`reviewReceived`/`additionalCharges`). Verified with `firebase deploy --only firestore:rules --dry-run` — compiles successfully. **Not yet deployed to production** — pending explicit go-ahead. One known edge case: `chatMessage`'s `bookingId` argument falls back to `_chatId` (chat_screen.dart:487) if the async-loaded `_bookingId` hasn't resolved yet when a message is sent very quickly after opening a chat; in that rare race, the push silently won't be enqueued (permission-denied) — this is already wrapped in a try/catch treating the push as best-effort (chat_screen.dart:480-493), so the chat message itself is unaffected, only that one push notification.

---

### HIGH

**Issue ID:** N-02 — ✅ **FIXED 2026-08-08**
**Severity:** High
**System:** Customer/Provider App
**Exact file:** `lintho-app/lib/fcm_service.dart` lines 71-106 (`_watchFCMQueue`); `lintho-app/firestore.rules` lines 947-952
**Function:** `FCMService._watchFCMQueue()`
**Evidence:** `_watchFCMQueue()` opens a live snapshot listener: `.collection('fcm_queue').where('targetUserId', isEqualTo: uid).where('sent', isEqualTo: false).snapshots().listen(...)`. The Firestore rule for this collection is `allow read, update, delete: if false;` — reads are unconditionally denied for every client, including the doc's own target. Every invocation of this listener fails with `permission-denied`, caught only by `onError` and logged via `debugPrint` (line 104) — invisible in production, no user-facing effect, no crash.
**Expected:** This listener (per its own purpose — driving `_showInAppBanner` from queued docs) should receive snapshots for the current user's pending notifications.
**Actual:** It never receives a single snapshot; it is permanently broken by design conflict with the security rules.
**Root Cause:** The rule change that closed `fcm_queue` reads to everyone (a correct, security-motivated decision — the collection can contain another user's queued title/body while `sent:false`) was made without removing or reworking this now-dead client listener.
**Recommended Fix:** Delete `_watchFCMQueue()` and its call site (fcm_service.dart:68) entirely — it serves no function today. Actual foreground delivery is correctly and independently handled via `FirebaseMessaging.onMessage` (`_onForeground`, line 188), which does not depend on Firestore reads. If in-app-banner-before-FCM-round-trip latency was the original intent, that would need a different mechanism (e.g. a Cloud Function callable/return value), not a client read of `fcm_queue`.

**Fix applied (2026-08-08):** Removed `_watchFCMQueue()`, its call site in `init()`, and the now-unused `StreamSubscription? _queueSub` field from `fcm_service.dart`. Verified with `flutter analyze lib/fcm_service.dart` — no issues found.

---

**Issue ID:** N-03 — ✅ **FIXED 2026-08-08** (code-level; still needs a live-device confirmation — see note)
**Severity:** High
**System:** FCM / Android delivery
**Exact file:** `lintho-app/functions/index.js` lines 19-23, 94; `lintho-app/android/app/src/main/AndroidManifest.xml` (entire file); `lintho-app/pubspec.yaml`
**Function:** `_getChannelId()`, `processFCMQueue`
**Evidence:** Every push sent via `processFCMQueue` specifies `android: { notification: { channelId: _getChannelId(data.type) } }`, where `_getChannelId` returns one of `'lintho_chat'`, `'lintho_payment'`, or `'lintho_jobs'` (functions/index.js:19-23). Searched the entire Android project (`AndroidManifest.xml`, all `.kt`/`.java` files) for any `NotificationChannel` creation or a `com.google.firebase.messaging.default_notification_channel_id` manifest `<meta-data>` entry — **none exists**. `pubspec.yaml` does not include `flutter_local_notifications` or any other plugin capable of creating a channel (only `firebase_messaging: ^15.1.3`, confirmed by grep). `MainActivity.kt` is a bare `FlutterActivity` subclass with no notification setup.
**Expected:** Every Android notification channel referenced in an outgoing FCM payload should exist on the device before the message arrives.
**Actual:** None of `lintho_chat`/`lintho_payment`/`lintho_jobs` is ever created anywhere in the app.
**Root Cause:** The comment at the top of `fcm_service.dart` ("NO flutter_local_notifications — use FCM directly") reflects a deliberate choice to skip the local-notifications plugin, but channel creation was not replaced with an equivalent native implementation.
**Recommended Fix:** Create the three channels natively (e.g., in `MainActivity.onCreate` or `Application.onCreate` via `NotificationManager.createNotificationChannel`) before any push can arrive, or add `flutter_local_notifications` and create them at Dart-side app startup. This is the single highest-priority item to verify on a real Android device — behavior can vary by OEM/Android version, hence why this is not marked LIVE DEVICE VERIFIED here.
**Verification note:** This is CODE VERIFIED as a gap (no channel-creation code exists anywhere). Whether it actually suppresses notifications on a given Android/OEM combination requires a real device test (§14) — flagged High rather than Critical specifically because I could not confirm actual on-device suppression, only the code-level absence of any channel registration.

**Fix applied (2026-08-08):** `android/app/src/main/kotlin/com/lintho/app/lintho/MainActivity.kt` now overrides `onCreate()` and calls `createNotificationChannels()`, creating `lintho_jobs`, `lintho_chat`, and `lintho_payment` as `IMPORTANCE_HIGH` channels via `NotificationManager.createNotificationChannel()` (guarded by `Build.VERSION.SDK_INT >= Build.VERSION_CODES.O`). Since an FCM token can only ever be registered after the Flutter engine has started at least once (`FCMService.instance.init()` runs from `RoleRouter`, which only exists inside the running app), `MainActivity.onCreate()` is guaranteed to have already run — and the channels to already exist — by the time this device could receive any push. Verified with `./gradlew.bat :app:compileDebugKotlin` — **BUILD SUCCESSFUL**. Not yet verified on a physical/emulated device (still NOT TESTABLE in this environment — see §14); this closes the code-level gap but the original request's live-device confirmation is still outstanding.

---

**Issue ID:** N-04 — ✅ **FIXED 2026-08-08**
**Severity:** High
**System:** Admin Panel / Role Targeting
**Exact file:** `lintho-admin/src/lib/hooks/index.ts` lines 917-926
**Function:** `resolveNotificationTargets()`, `'specific'` branch
**Evidence:**
```ts
const resolved = await Promise.all(specificIds.map(async (id) => {
  const userSnap = await getDoc(doc(db, 'users', id))
  if (userSnap.exists()) return { id, role: 'customer' as const }   // <- existence only, role field never read
  const providerSnap = await getDoc(doc(db, 'providers', id))
  if (providerSnap.exists()) return { id, role: 'provider' as const }
  return null
}))
```
Every Provider account also has a mirrored doc in `users/{uid}` with `role:'provider'` (written at registration — `technician_register_screen.dart:500`; also touched by `fcm_service.dart`'s `saveToken()`). Because this function checks only *document existence* in `users`, not the `role` field's actual value, **any Provider UID passed as a "specific" target is misclassified as `role:'customer'`.**
**Expected:** Section 5 of this audit explicitly requires "Admin → Specific Provider MUST notify only that Provider" with correct role metadata.
**Actual:** `resolveNotificationTargets` returns `{id, role:'customer'}` for a Provider's UID; the `fcm_queue` doc is written with `targetRole:'customer'`; `processFCMQueue` then reads tokens from `users/{targetUserId}` instead of `providers/{targetUserId}`.
**Why delivery still (accidentally) works today:** `saveToken()` (fcm_service.dart:159-176) writes the same tokens into **both** `users/{uid}.fcmTokens` and `providers/{uid}.fcmTokens` for a provider — so `processFCMQueue` reading from the wrong collection still finds the right tokens, purely by coincidence of that mirroring choice. This is not a designed safety net and would silently break if that mirroring logic ever changes.
**Root Cause:** Existence check substituted for an actual role-field check.
**Recommended Fix:** Read `userSnap.data()?.role` and only return `role:'customer'` if it equals `'customer'`; otherwise fall through to check `providers/{id}`.

**Fix applied (2026-08-08):** `lintho-admin/src/lib/hooks/index.ts` — the 'specific' branch of `resolveNotificationTargets` now reads `userSnap.data().role` (defaulting to `'customer'` when absent, matching `firestore.rules`' own `getRole()` fallback) and only returns `role:'customer'` when that field is genuinely `'customer'`; a `role:'provider'` value now correctly returns `{id, role:'provider'}` without needing the `providers` doc lookup at all. Verified with `npx tsc --noEmit` — no type errors.

---

### MEDIUM

**Issue ID:** N-05 — ✅ **FIXED 2026-08-08**
**Severity:** Medium
**System:** Admin Panel / Role Targeting
**Exact file:** `lintho-admin/src/lib/hooks/index.ts` lines 906-908
**Function:** `resolveNotificationTargets('providers')`
**Evidence:** `return snap.docs.map(d => ({ id: d.id, role: 'provider' as const }))` over the entire unfiltered `providers` collection — no check of `kycStatus`, `status`, `isVerified`, or `suspendReason`.
**Expected:** UI copy for this target explicitly says "All **active** providers."
**Actual:** Pending, rejected, and suspended provider accounts all receive the broadcast identically to active ones.
**Root Cause:** Missing filter clause.
**Recommended Fix:** Filter to `kycStatus === 'verified'` (and/or exclude suspended) to match the UI's stated scope, or relabel the UI to "All providers" if broadcasting to everyone is intentional.

**Fix applied (2026-08-08):** `lintho-admin/src/lib/hooks/index.ts` — `resolveNotificationTargets('providers')` now filters `d.data().kycStatus === 'verified'` before mapping. This naturally excludes `'none'`/`'pending'`/`'rejected'` and `'suspended'` (the value `useSuspendProvider` sets) in one filter, matching the same "active" definition already used elsewhere in this file (the leaderboard query). Verified with `npx tsc --noEmit` — exit 0, no errors.

---

**Issue ID:** N-06 — ✅ **FIXED 2026-08-08** (5 of 6 call sites — see note)
**Severity:** Medium
**System:** Customer/Provider App — Token lifecycle
**Exact file:** `lintho-app/lib/fcm_service.dart` lines 178-186; every `signOut()` call site (`main.dart:347,2967,3027,4587`, `pending_approval_screen.dart:110`, `profile_tab.dart:282`)
**Function:** `FCMService.removeToken()`
**Evidence:** `removeToken()` is fully implemented (removes the current token from `fcmTokens` and calls `_messaging.deleteToken()`) but a repo-wide grep for its call sites returns none — it is dead code. Every logout path calls `FirebaseAuth.instance.signOut()` directly.
**Expected:** Section 8 explicitly requires verifying "User logged out" as a failure-mode scenario.
**Actual:** A logged-out user's FCM token remains in `fcmTokens` indefinitely. On a shared or resold device, this can mean the token stays bound to a previous account and continues to trigger local `onMessage`/tray delivery for that stale account's notifications, since FCM tokens are device-instance-scoped, not account-scoped, and nothing invalidates the association server-side.
**Root Cause:** `removeToken()` was written but never wired into the logout flow.
**Recommended Fix:** Call `FCMService.instance.removeToken()` before `FirebaseAuth.instance.signOut()` at every logout call site.

**Fix applied (2026-08-08):** Added `await FCMService.instance.removeToken();` immediately before `signOut()` at `main.dart:347`, `main.dart:2967`, `main.dart:4587`, `pending_approval_screen.dart:110` (new `import 'fcm_service.dart';` added), and `profile_tab.dart:282` (new import added). **Deliberately left unwired at `main.dart:3027`** (the delete-own-account flow): the `deleteOwnAccount` Cloud Function (`functions/index.js:1015`) already deletes the `users/{uid}` doc server-side before this client code runs `signOut()`, so calling `removeToken()` there would `update()` a document that no longer exists and throw — the token becomes moot anyway once the account and its Firestore doc are gone. `removeToken()` itself was also hardened as part of the N-11 fix below to best-effort clean up any legacy token still sitting on `providers/{uid}` from before that fix. Verified with `flutter analyze` — 0 errors (only pre-existing, unrelated info-level lints).

---

**Issue ID:** N-07 — ✅ **FIXED 2026-08-08**
**Severity:** Medium
**System:** Customer/Provider App — Deep linking
**Exact file:** `lintho-app/lib/fcm_service.dart` lines 213-278 (`_navigate`); `lintho-admin/src/lib/hooks/index.ts` line 987
**Function:** `FCMService._navigate()`
**Evidence:** The `if/else if` chain in `_navigate()` handles exactly `new_booking`, `booking_update`, `additional_charges`, `chat`, `payment`. Admin-composed notifications are always written with `type: 'admin_broadcast'` (lintho-admin/src/lib/hooks/index.ts:987). No branch matches this type, and there is no default/else case — tapping an admin notification does nothing at all (no navigation, no error, no feedback).
**Expected:** Section 2 explicitly asks whether the admin panel can "send deep-link/action if supported."
**Actual:** Admin broadcasts have no possible deep-link destination in the current implementation — the feature doesn't exist yet, not merely misconfigured.
**Root Cause:** `useSendNotification` never collects a target screen/deep-link from the admin composer, and `_navigate` has no fallback branch.
**Recommended Fix:** Either add an optional "destination" field to the admin composer (mapped to an existing screen) or, at minimum, add a default branch that opens the Notification/Home screen so tapping isn't a dead end.

**Fix applied (2026-08-08):** `lintho-app/lib/fcm_service.dart` — `_navigate()` now has a trailing `else` branch that calls `nav.popUntil((route) => route.isFirst)`, returning the user to the app's home screen instead of doing nothing. This covers `admin_broadcast` and any other future/unrecognized type. The admin-composer "destination" field option was not built — out of scope for a bug fix, left as a possible future enhancement. Verified with `flutter analyze` — 0 errors.

---

**Issue ID:** N-08 — ⏸️ **DEFERRED, not fixed** — product/feature decision, see note
**Severity:** Medium
**System:** Customer/Provider App — Notification history
**Exact file:** `lintho-app/lib/notification_screen.dart` (entire file)
**Function:** `NotificationScreen.build()`
**Evidence:** The screen reached from the bell icon (per its own header comment) has exactly 3 tabs: Chat (`ChatListBody`), News (`CouponListBody` — real promotions/coupons, not a notification feed), and Customer Service (FAQ/phone/WhatsApp/email). There is no list, stream, or query of past notifications anywhere in this file, and (per N-02) even the `fcm_queue` collection this could theoretically read from is read-denied to clients.
**Expected:** Section 3/4 explicitly ask to verify "notification history" for both Customer and Provider.
**Actual:** No such feature exists. Once an OS notification is dismissed or an in-app SnackBar banner disappears (4-second auto-dismiss, fcm_service.dart:142), there is no way to review it again inside the app.
**Root Cause:** Feature not built; the bell icon was repurposed for chat/promo/support instead.
**Recommended Fix:** Product decision — if a real history is wanted, it needs a readable, per-user notification collection (the existing `notifications/{notifId}` collection with a `toUid` field is already scaffolded for exactly this in firestore.rules lines 918-930, and is explicitly commented "not used by any client code currently" — it appears to be unfinished, abandoned infrastructure for this exact feature).

**Not fixed in this pass (2026-08-08) — deliberately deferred, not skipped:** unlike N-05/06/07/09/10/11, this isn't a bug with a clear correct behavior to restore — it's a missing feature. Building it for real requires: (1) the Cloud Function writing a per-recipient doc into the already-rules-scaffolded `notifications/{notifId}` collection (with `toUid`, `title`, `body`, `type`, `bookingId`, `read`) for every dispatched push, and (2) a new Flutter screen/tab with read/unread state, which means deciding what happens to the bell icon's current Chat/Promotions/Support tabs (replace one, add a 4th, redesign the IA) — an information-architecture and scope decision, not something to auto-build under a "fix medium bugs" instruction. Flagging explicitly rather than silently skipping, consistent with this project's established pattern of deferring product/policy decisions (see the 2026-08-06 full re-audit's deferred items).

---

**Issue ID:** N-09 — ✅ **FIXED 2026-08-08**
**Severity:** Medium
**System:** Backend / Cloud Functions
**Exact file:** `lintho-app/functions/index.js` lines 91-98
**Function:** `processFCMQueue`
**Evidence:** `const result = await messaging.sendEachForMulticast({...}); return snap.ref.update({ sent: true, successCount: result.successCount });` — `result.responses` (which contains a per-token success/failure/error-code breakdown, including `messaging/registration-token-not-registered` for dead tokens) is never read.
**Expected:** Section 6 explicitly asks about "invalid token handling," "expired token handling," and "token cleanup."
**Actual:** No invalid token is ever detected or removed from `fcmTokens`. Combined with N-06 (no removal on logout), tokens only ever accumulate.
**Root Cause:** Minimal implementation of the multicast result handling.
**Recommended Fix:** Iterate `result.responses`, and for each failure with code `messaging/registration-token-not-registered` or `messaging/invalid-registration-token`, remove that specific token from the corresponding user/provider doc via `FieldValue.arrayRemove`.

**Fix applied (2026-08-08):** `functions/index.js` — dispatch logic was extracted into a shared `attemptFcmDelivery(ref, data)` helper (used by both `processFCMQueue` and the new `retryFailedFcmQueue`, see N-10). It now iterates `result.responses`, collects tokens whose error code is `messaging/registration-token-not-registered` or `messaging/invalid-registration-token`, and removes them via `FieldValue.arrayRemove(...deadTokens)`. Bundled with the N-11 fix below, this now prunes from `users/{targetUserId}.fcmTokens` (the single, always-authoritative location — see N-11). Verified with `node -c index.js` (syntax OK); full runtime behavior not testable without a live FCM send (no device/emulator available — same limitation noted in §14 of this report).

---

**Issue ID:** N-10 — ✅ **FIXED 2026-08-08**
**Severity:** Medium
**System:** Backend / Reliability
**Exact file:** `lintho-app/functions/index.js` lines 99-100
**Function:** `processFCMQueue` catch block
**Evidence:** `catch (err) { return snap.ref.update({ sent: true, error: err.message }); }` — marks the doc `sent:true` even when the send **failed**.
**Expected:** A transient failure (FCM outage, temporary permission issue, network blip in the function) should be retryable.
**Actual:** Any error — transient or permanent — permanently drops that notification; `sent:true` with an `error` field looks identical, from a query standpoint, to a successful send (both have `sent:true`), so nothing downstream distinguishes them.
**Root Cause:** Marking `sent:true` unconditionally in the catch block, presumably to avoid the trigger re-firing forever on a permanently-broken doc, but this also swallows genuinely transient failures.
**Recommended Fix:** Distinguish transient vs. permanent errors; for transient ones, leave `sent:false` (or a `retryCount`-bounded state) so a scheduled sweep can retry, rather than a blanket "mark done."

**Fix applied (2026-08-08):** `functions/index.js` — the shared `attemptFcmDelivery()` catch block now writes `{ sent: false, error, retryCount }` (instead of `sent:true`) when `retryCount < MAX_FCM_RETRIES` (5). A new scheduled function, `exports.retryFailedFcmQueue` (pubsub, every 10 minutes), queries `fcm_queue` where `sent==false && retryCount>0` and re-attempts delivery via the same helper — the `retryCount>0` filter is what keeps it from racing a freshly-created doc `processFCMQueue` hasn't attempted yet (those always have `retryCount` unset). After 5 failed attempts the doc is finally marked `{ sent: true, error, retryCount, giveUp: true }` so it doesn't retry forever or block `cleanupOldFcmQueue`'s existing 7-day purge. Added a new composite index (`sent` ASC, `retryCount` ASC) to `firestore.indexes.json` for the retry sweep's query — **not yet deployed** (index deploys require `firebase deploy --only firestore:indexes`, separate from the rules dry-run already run). Verified with `node -c index.js` (syntax OK) and validated the indexes JSON parses correctly; the new scheduled function itself is not testable without deploying to a live Cloud Functions environment.

---

**Issue ID:** N-11 — ✅ **FIXED going forward** (historical leaked tokens not purged — see note)
**Severity:** Medium
**System:** Security / Data exposure
**Exact file:** `lintho-app/firestore.rules` lines 653-654; `lintho-app/lib/fcm_service.dart` lines 170-175
**Function:** `match /providers/{providerId}` read rule; `FCMService.saveToken()`
**Evidence:** `providers/{providerId}` is readable by any authenticated user (`allow read: if isAuth();` — required so customers can browse providers), and `fcmTokens` is stored directly on that same document with no field-level exclusion (unlike `phone`, `kycDocUrl`, `kycIdUrl`, `kycSelfieUrl`, which the rules explicitly forbid on this doc per the KYC-1/SEC-3 audit comments at lines 665-671).
**Expected:** Section 10 explicitly asks to verify "FCM tokens are never exposed to users."
**Actual:** Any logged-in Customer or Provider can read every Provider's raw FCM device tokens by querying the public `providers` collection.
**Root Cause:** `fcmTokens` was never added to the field-exclusion pattern already established for other sensitive fields on this document.
**Recommended Fix:** Move `fcmTokens` off the publicly-readable `providers/{uid}` doc (e.g. into a `providers/{uid}/private/tokens` subcollection readable only by the owner and Cloud Functions), matching the pattern already used for `kyc/{uid}`.
**Note on exploitability:** A leaked token alone cannot be used to send FCM messages without the project's Admin SDK/server credentials (which are never exposed — see §1), so this is a confidentiality/PII-hygiene issue rather than a directly exploitable takeover path on its own.

**Fix applied (2026-08-08) — simpler than the originally recommended subcollection:** Investigation during the fix found `users/{uid}.fcmTokens` is *already* unconditionally written for every account regardless of role (`saveToken()`, fcm_service.dart) and is *already* private (Firestore rule: owner-or-admin read only) — the `providers/{uid}.fcmTokens` mirror was pure redundant duplication that existed only to support a role-based branch in `processFCMQueue`, and was the sole source of this leak. Rather than adding a new subcollection, `saveToken()` no longer writes the mirror at all, and `processFCMQueue`/`retryFailedFcmQueue` (`functions/index.js`) now always read tokens from `users/{targetUserId}` regardless of `targetRole` — this also makes the N-04 fix's correctness independent of any token-mirroring coincidence, since there's no mirroring left to coincide with. `removeToken()` was additionally hardened to best-effort strip any legacy token still sitting on `providers/{uid}` from before this fix (wrapped in try/catch since most callers aren't providers and/or the doc may not have the field). **Caveat: this stops *new* tokens from being exposed but does not retroactively purge `fcmTokens` already written to `providers/{uid}` docs before this fix** — those remain readable until each affected provider naturally logs out (triggering the best-effort cleanup in `removeToken()`) or a one-off admin migration script strips the field from all `providers/*` docs. That migration was not run as part of this fix — it's a data cleanup, not a code change, and touches every provider doc in production. Verified with `flutter analyze` (0 errors) and `node -c index.js` (syntax OK).

---

### LOW

**Issue ID:** N-12 — ✅ **FIXED 2026-08-08**
**Severity:** Low
**System:** Admin Panel / Auditability
**Exact file:** `lintho-admin/src/lib/hooks/index.ts` lines 998-1013, 817-839
**Function:** `useSendNotification`, `writeAuditLog`
**Evidence:** The `notifications` history doc itself has no `senderId`/actor field; identifying which admin sent a broadcast requires cross-referencing the separate `auditLogs` collection, whose `adminId`/`adminName`/`adminRole` fields are populated client-side from `useAuthStore.getState().user` (local/unverified state), consistent with the already-documented ADM-5 pattern in this codebase (admin tier enforcement is UI-level, not re-verified server-side).
**Expected:** Section 9 asks to verify `senderId` is recorded on the notification.
**Actual:** Not on the notification doc; only indirectly via a separately-queried, client-trusted audit log.
**Root Cause:** Schema omission.
**Recommended Fix:** Add `sentBy: { id, name, role }` directly onto the `notifications` doc at write time (still client-asserted unless moved server-side, but at least co-located with the record it describes).

**Fix applied (2026-08-08):** `useSendNotification` (lintho-admin/src/lib/hooks/index.ts) now reads `useAuthStore.getState().user` (same source `writeAuditLog` already uses) and writes `sentBy: { id, name, role }` onto the `notifications` doc; `useNotificationHistory`'s read mapping and the `NotificationTemplate` type (`src/types/index.ts`) were updated to carry it through, and the history list (`notifications/page.tsx`) now shows "by {name}" next to each entry. Still client-asserted, not server-verified — same known limitation as `writeAuditLog`, not a new gap introduced here. Verified with `npx tsc --noEmit` (exit 0) and a clean `next dev` boot with no compile errors.

---

**Issue ID:** N-13 — ✅ **FIXED 2026-08-08**
**Severity:** Low
**System:** Customer/Provider App — iOS
**Exact file:** `lintho-app/lib/fcm_service.dart` lines 54-57, 188-197
**Function:** `FCMService.init()`, `_onForeground()`
**Evidence:** `setForegroundNotificationPresentationOptions(alert:true, badge:true, sound:true)` causes iOS to show its own native foreground banner, while `_onForeground` independently shows a custom in-app SnackBar for the same message.
**Expected:** One visible notification per incoming push while the app is foregrounded.
**Actual (likely, not device-confirmed):** iOS users may see both the native banner and the custom SnackBar simultaneously; Android does not have this issue (no native foreground banner by default).
**Root Cause:** Both presentation paths are enabled without disabling one for iOS specifically.
**Recommended Fix:** Set `alert:false` in `setForegroundNotificationPresentationOptions` on iOS (keep badge/sound) so only the in-app banner shows while foregrounded, matching Android's behavior.

**Fix applied (2026-08-08):** `lib/fcm_service.dart` — `setForegroundNotificationPresentationOptions` now passes `alert: false` (kept `badge: true, sound: true`). No platform check was needed: this API is iOS/macOS-only and is a documented no-op on Android, so the same call already safely covers both platforms. Verified with `flutter analyze` — no issues found. Still not live-device-confirmed (no iOS device/simulator with APNs available in this environment).

---

**Issue ID:** N-14 — ✅ **PARTIALLY FIXED 2026-08-08** — see note (real fix still blocked on N-08)
**Severity:** Low
**System:** Backend
**Exact file:** `lintho-app/functions/index.js` line 95
**Function:** `processFCMQueue`
**Evidence:** `apns:{payload:{aps:{sound:'default', badge:1}}}` — the badge count is hardcoded to `1` for every single push, never reflecting an actual accumulating unread count.
**Expected:** iOS app badge should reflect a real unread count (or the feature should be omitted rather than fixed at 1).
**Actual:** Badge always resets/shows `1` regardless of how many unread notifications exist.
**Root Cause:** Static value, no unread-count tracking exists anywhere in the system (consistent with N-08 — there is no notification history/read-state model at all).
**Recommended Fix:** Low priority given N-08 is unresolved; would need an actual unread-count source to fix meaningfully.

**Fix applied (2026-08-08):** `functions/index.js` — removed the hardcoded `badge: 1` from the `apns.payload.aps` object entirely rather than replacing it with a real count (no real count exists to compute — see N-08). Omitting the `badge` key leaves iOS's existing app-icon badge untouched instead of actively overwriting it to `1` on every push (which could visibly *undercount*, e.g. resetting a real backlog of 5 down to 1). This closes the "actively lying" half of the finding; a real incrementing/accurate badge still needs N-08's unread-tracking model to exist first — that part remains open by design. Verified with `node -c index.js` — syntax OK.

---

## 8. Notification Data Consistency (§9 of the request)

| Field | Present in `notifications` (admin history) | Present in `fcm_queue` (dispatch record) |
|---|---|---|
| senderId | No (see N-12) | No |
| recipientId | No — only an aggregate `sentCount`, not a per-recipient list | Yes (`targetUserId`) |
| recipientRole | No | Yes (`targetRole`) — **can be wrong, see N-04** |
| title / body | Yes | Yes |
| timestamp | Yes (`createdAt`, `sentAt`) | Yes (`createdAt`) |
| notification type | Only implicitly via `channel` (always `'push'` today) | Yes (`type`) |
| read/unread | N/A — no per-recipient record exists | N/A (`sent` tracks dispatch, not read) |
| target (audience selector) | Yes (`target`: all/customers/providers/specific) | N/A per-doc (each doc is one recipient) |
| deep link | No field | No field — deep link is inferred client-side from `type`+`bookingId`, and doesn't exist for `admin_broadcast` (N-07) |
| delivery status | No (`status` is always `'sent'` the instant the queue write succeeds — see §2) | Partial (`sent`, `successCount`/`error` — but never surfaced back to the admin UI) |

The two collections are **not linked** — there is no `notifications.{id}` reference stored on the corresponding `fcm_queue` docs or vice versa, so reconstructing "which individual fcm_queue sends resulted from admin broadcast X" is not possible from stored data alone (only approximately, by matching `createdAt` timestamp and `title`/`body`).

---

## 9. Security Result (§10 of the request)

| Check | Result |
|---|---|
| Only authorized Admins can send notifications | **FAIL at the `fcm_queue` layer** — see N-01 (Critical). The `notifications` history collection itself is admin-gated correctly (Firestore blanket-bypass rule requires `role=='admin'`), but the actual dispatch mechanism (`fcm_queue`) is not. |
| Customer cannot send Admin notifications | **FAIL** — a Customer can write a `fcm_queue` doc with `type:'admin_broadcast'` targeting anyone (N-01) |
| Provider cannot send Admin notifications | **FAIL** — same as above |
| Customer cannot access another user's notification records | **PASS** — `fcm_queue` denies all reads to everyone including the doc's own target (over-corrected, in fact — see N-02); `notifications/{notifId}` (the unused, per-user-shaped collection) restricts read to `toUid == request.auth.uid` |
| Provider cannot access another provider's notification records | **PASS** — same mechanism |
| Admin cannot accidentally expose FCM tokens to users | **FAIL for Providers** — see N-11 (Medium); tokens are not rendered anywhere in the Admin UI itself (grepped `lintho-admin/src` for `fcmTokens` — only appears in the notification-dispatch backend logic described above, never in a component), so the Admin Panel itself does not leak tokens; the leak is via the app's own `providers/{uid}` read rule, not via the admin panel. |
| FCM server credentials are never exposed to Flutter/client code | **PASS** — `admin.initializeApp()` with no explicit credentials, runs only in Cloud Functions; no service-account material found in either repo's client code |

---

## 10. Role Targeting Result (§5 of the request)

| Scenario | Result |
|---|---|
| Admin → Customer must not accidentally notify Provider | **PASS** — `resolveNotificationTargets('customers')` correctly filters `users` by `role==='customer'` |
| Admin → Provider must not accidentally notify Customer | **PASS** for the bulk case; role field is written correctly at registration and read correctly here |
| Admin → Specific Customer notifies only that Customer | **PASS** |
| Admin → Specific Provider notifies only that Provider | **PARTIAL** — correct device is reached today, but role metadata is wrong (N-04, High) |
| Admin → All Customers notifies Customers only | **PASS** |
| Admin → All Providers notifies Providers only | **PASS** in terms of role, **FAIL** in terms of the "active" qualifier the UI claims (N-05, Medium) |
| Wrong UID / wrong token / wrong Firestore query | Not observed elsewhere beyond N-04 |
| Token leakage | See N-11 |
| Duplicate tokens | Prevented via `arrayUnion` (PASS) |
| Cross-user notification (unauthorized) | **FAIL** — see N-01, the Critical finding; this is the most direct instance of "cross-user notification" the audit was asked to check for |

---

## 11. Real Device Test Result (§7/§14 of the request)

**NOT TESTABLE in this session.** This audit was performed via source-code analysis only, using terminal/file tools against the two repositories on disk. There is no connected Android/iOS device or emulator with Google Play services, no test Firebase accounts (`CUSTOMER_TEST`/`PROVIDER_TEST`/`ADMIN_TEST`) provisioned, and no way to observe an actual OS notification tray or app foreground/background/terminated state transition from this environment — the available browser-preview tooling renders web pages, not native mobile app UI or OS-level push notifications. TEST 1 through TEST 10 as specified in the request cannot be executed here.

**What would be needed to run them:** a physical device or emulator with Google Play Services for Android (and/or a real iOS device — the iOS Simulator does not support APNs/FCM push), the app built and installed, three seeded test accounts (customer, verified provider, admin), and a human or automation harness able to observe the notification shade / app state and tap notifications. This should be the immediate next step given the Critical (N-01) and High (N-02, N-03, N-04) findings above — in particular N-03 (Android channels) can only be conclusively confirmed or ruled out on a real Android device.

---

## 12. Verdict Classification Summary

| Pipeline Stage | Classification |
|---|---|
| Admin composes & clicks Send | CODE VERIFIED |
| Admin UI reports "Sent" | CODE VERIFIED — proven to mean "Firestore write accepted," not delivery (§2) |
| Correct `fcm_queue` docs are created with correct target | CODE VERIFIED (customers/all/specific-customer/all-providers correct; specific-provider role field wrong — N-04) |
| Cloud Function dispatches to real FCM | CODE VERIFIED (`sendEachForMulticast` call is real and correctly wired) |
| FCM accepts the request | CODE VERIFIED (API call is correct); not independently confirmed against live FCM in this session |
| Correct device token is targeted | CODE VERIFIED, with the N-04 metadata caveat and N-11 exposure caveat |
| Device actually receives/displays the notification | **PARTIALLY VERIFIED at best** — foreground path (`onMessage`) is CODE VERIFIED and should work; background/terminated display is put at risk by N-03 (Android channel gap), and cannot be confirmed without a live device (NOT TESTABLE here) |
| Tapping opens the correct destination | CODE VERIFIED for the 5 internally-generated types; **FAILS by design** for admin broadcasts (N-07) |
| Security boundary between "authorized admin" and "any user" for sending | **FAILS** — N-01, Critical |

**No stage of this pipeline reaches "LIVE DEVICE VERIFIED" in this audit.** The strongest honest claim supportable from code alone is: *the happy-path architecture is real and mostly correctly wired, gated by one Critical authorization gap (N-01) and one High delivery-reliability gap (N-03) that both need to be closed, and neither of which the Admin Panel's "Sent" indicator would ever surface to an operator.*

---

## 13. Recommended Fix Priority

1. **N-01 (Critical)** — lock down `fcm_queue` create rule to admin-only or booking-relationship-verified writers. This is a live spoofing/harassment vector against real users today.
2. **N-03 (High)** — create the three Android notification channels natively before shipping any further reliance on background push; verify on a real device.
3. **N-04 (High)** — fix `resolveNotificationTargets`'s specific-ID role resolution to read the actual `role` field.
4. **N-02 (High, cheap fix)** — delete the dead, always-failing `_watchFCMQueue` listener.
5. **N-06 (Medium)** — wire `removeToken()` into every logout call site.
6. **N-09 (Medium)** — prune invalid tokens using `sendEachForMulticast`'s per-token response.
7. **N-05, N-07, N-10, N-11 (Medium)** — as time allows, in roughly that order.
8. **N-08 (Medium/product)** — decide whether a real in-app notification history is wanted; the scaffolding (`notifications/{notifId}` with `toUid`) already exists in the rules but nothing writes to it per-recipient today.
9. **N-12, N-13, N-14 (Low)** — polish items.

No code was changed as part of this audit, per the request's explicit instruction.
