# LINTHO — PHASE 2 BATCH C AUDIT

Customer Account Migration — companion to `LINTHO_PHASE2_MIGRATION_PLAN.md`,
`LINTHO_PHASE2_BATCH_A_AUDIT.md`, `LINTHO_PHASE2_BATCH_B_AUDIT.md`.

Status: **Batch C complete, verified, committed. Stopped per instruction —
awaiting review before Batch D. ProfileScreen received a bounded, honestly-
scoped pass, not full convergence — see §15.**

---

## 1. Files changed

- `lib/main.dart` — `ProfileScreen` (bounded scope, see §5, §15)
- `lib/review_screen.dart` — full pass (localization regression fixed, CTA
  hierarchy, typography, radius)
- `lib/notification_screen.dart` — full pass
- `lib/rewards_screen.dart` — full pass (money-adjacent, extra scrutiny)
- `lib/referral_screen.dart` + `lib/referral_provider.dart` — full pass
  (money-adjacent; provider touched only for the display strings it hands
  back to this screen, no logic change)
- `lib/chat_screen.dart` — full pass on UI/localization/design-system;
  backend/schema untouched per instruction
- `lib/support_help.dart` — full pass (was already close to compliant)
- `lib/app_locale.dart` — new keys only (all 4 locales); 6 pre-existing but
  stale/unused keys corrected to match currently-shipped text (see §6)

`git diff --stat`: 9 files changed, 618 insertions(+), 299 deletions(-).

No Firestore schema, Cloud Function, Firebase rule, payment/reward/referral
calculation, chat backend/message schema, authentication architecture, or
navigation architecture was changed anywhere in this batch.

---

## 2. Baseline

Captured before any Batch C edit, and confirmed to match the expected
Batch B end-state exactly (per this batch's STOP-if-different instruction):

- `flutter analyze`: **0 errors, 2 known warnings, 70 total issues.**
- `flutter test`: **236 passed, 12 failed** (same pre-existing set as
  `OUT_OF_SCOPE_FINDINGS.md` OOS-1).

No deviation — proceeded without needing to report a baseline mismatch.

## 3. Final `flutter analyze`

**0 errors, 2 known warnings (unchanged), 65 total issues** — 5 *fewer*
than baseline (some redundant `shape:`/style overrides that duplicated
theme defaults were removed rather than replaced, eliminating a few
`prefer_const_constructors` hints along the way). No new lint categories.
One duplicate-map-key warning was introduced and caught mid-batch (see §6)
before the final run — not present in the number above.

## 4. Final `flutter test`

**236 passed, 12 failed** — identical to baseline, same test names in the
same order (verified via full failing-list diff, not just the count).
Zero regressions.

---

## 5. Changes per file

### `review_screen.dart` (§4 of the master prompt — investigated first)

Full localization-regression investigation performed before any edit (see
§6 for the finding and correction process). Beyond localization:
- Success dialog: dropped an explicit `radius(20)` override — the app's
  `dialogTheme` already applies `AppRadius.card` automatically.
- Book Again: was `OutlinedButton` styled **green** (`C.primary` border/
  text) — converted to `AppButton.outline` (navy), since Submit Review
  above it is this screen's actual primary action; Book Again is
  secondary. Navigation logic (Phase 0 P0-1 fix) preserved exactly — see
  §11.
- View History: was a `TextButton` styled muted-gray — converted to
  `AppButton.ghost` (navy, per the shared component's default). Navigation
  unchanged.
- Submit Review: kept as a raw `ElevatedButton` (not `AppButton`) —
  already correctly green; not converted because doing so would lose its
  `_BtnLoadingSkeleton` (a `PulsingFade`-based loading pattern already
  better than `AppButton`'s plain spinner). Only its radius was converged
  to the token. Documented inline as an intentional exception, matching
  the same judgment call Phase 1 made for `booking_form_screen.dart`'s
  bottom-bar button.
- Star-rating emoji faces (😞😐🙂😊🤩) → Material icons
  (`sentiment_very_dissatisfied` … `sentiment_very_satisfied`), paired
  with the (now-localized) text label — same emoji-to-icon migration
  pattern used elsewhere in the app.
- Confetti/celebration emoji (🎉🎊✨⭐) in the header and success dialog
  — left as-is; decorative/celebratory content, not functional icons
  (explicit exemption in the app's own iconography rule).
- 7 raw `TextStyle`s migrated to `AppTypography.<role>` where the size
  matched a role exactly (AppBar title, section headings, service-name
  row, rating badge, header title/subtitle).

### `notification_screen.dart`

Already close to compliant (no hardcoded strings found). AppBar title and
TabBar label styles converged to `AppTypography` (exact size matches).
`_ServiceActionCard`'s three separate `BorderRadius.circular(16)` literals
(Material/InkWell/Container — a legitimate multi-layer pattern, not a
mistake) converted to the `AppRadius.card` token. No state-handling gap
found — `_CustomerServiceTab` reads static, admin-configured contact info
with a safe empty-default fallback; not the same class of defect as Batch
A's `PaymentHistoryScreen` (which silently froze on a real stream error).

### `rewards_screen.dart` (money-adjacent — extra scrutiny per §7)

- **CTA color fixed**: the Redeem buttons were `C.navy` — this is the one
  concrete money-converting action on the screen, now `AppButton.primary`
  (green), consistent with the plan's flagged "navy-vs-green CTA drift on
  money screens" finding.
- **Missing error+retry fixed**: the reward-settings `error:` branch showed
  a raw `'ໂຫລດເງື່ອນໄຂບໍ່ໄດ້: $e'` string with no retry — its sibling
  section (points history, 2 lines below) already used `ErrorStateView`
  per a prior audit (🔒 M-9) that evidently missed this branch. Now uses
  `ErrorStateView` with a real `ref.invalidate(rewardSettingsProvider)`
  retry.
- Redeemed-coupon success dialog: hardcoded strings restored to `tr()`,
  redundant radius override dropped.
- Transaction-type labels (`_HistoryRow`) and balance/rate copy restored
  to `tr()`.
- Balance-card navy background **kept** — hero/header surface, not a CTA
  (explicitly correct per the color-hierarchy rule's brand-surface
  carve-out).

### `referral_screen.dart` + `referral_provider.dart` (money-adjacent)

- **CTA color fixed**: "Use Code" (redeem) button was `C.navy` → `AppButton.primary`.
  The Share button was deliberately **not** converted — it's a white-fill/
  navy-text style specific to sitting on the navy hero card, which none of
  `AppButton`'s variants express (its "secondary" is a solid navy fill);
  documented inline.
- **Real bug fixed**: the `info == null` empty state showed
  `tr('fill_all')` ("please fill in all fields") — a form-validation
  string that made no sense for "no referral info" (which only happens
  when there's no signed-in user, per `referralInfoProvider`). Replaced
  with a correct `EmptyStateView` + the login-required message.
- 6 hardcoded error strings in `referral_provider.dart`
  (`redeemReferralCode()`, `_ensureReferralCode()`) were routed through
  `tr()` — this file is a supporting provider whose return values are
  directly displayed by `referral_screen.dart`, in scope per this batch's
  "localization keys used by these screens" allowance. No calculation or
  Firestore-write logic touched.
- Copy-code `IconButton` tooltip restored to `tr()` (was already present,
  just hardcoded).
- QR container / stat-card / code-card radii converged to tokens.

### `chat_screen.dart` (heaviest hardcoding in the batch, per the plan)

- Hardcoded strings restored to `tr()`: technician/customer name fallbacks
  in the chat list, message-input hint, send-failure message, the "Live"
  badge, and both empty-state variants' text.
- **Not** converted to `EmptyStateView` — `_ChatIllustration` (a richer,
  branded gradient illustration reused for both empty states) stays;
  documented as an intentional exception.
- AppBar title and several container radii converged to tokens.
- Back-button `tooltip` added (was missing).
- **Two hardcoded strings deliberately left untouched, flagged not
  fixed**: the `'User'` fallback for `senderName` and the `'ເລີ່ມການສົນທະນາ'`
  initial `lastMessage` value in `ChatService.createOrGetChat()` — both are
  values **persisted** into Realtime Database / Firestore records (not
  re-rendered per-viewer), so localizing them would mean the stored text
  depends on the *sender's* locale at write time, not the *reader's* locale
  at render time — a real behavior change to how chat data is recorded,
  which this batch's explicit "do not modify chat backend/schema" instruction
  told me to avoid touching without first reporting it. Flagged here rather
  than silently fixed or silently skipped.
- No realtime listener, message schema, or RTDB/Firestore write shape was
  changed anywhere in this file.

### `support_help.dart`

Smallest, cleanest file in the batch. Fixed: `'FAQ'` hardcoded title →
`tr('faq_title')` (a matching key already existed, unused); bottom-sheet
`shape` replaced with the existing `AppRadius.sheetTop` constant (was
hand-rolled to the identical shape); drag-handle radius converged;
category-header and FAQ-answer text converged to `AppTypography` roles.

### `main.dart` — `ProfileScreen` (bounded scope — see §15 for what's not done)

- **CTA color hierarchy fixed** on every navy "Save"/"Confirm" button that
  is the primary action of its own focused bottom sheet: Security-password
  save, OTP-confirm, Reset-password save, Edit-profile save, Points-sheet
  "view history & redeem" — all `C.navy` → `C.primary`. This is the exact
  violation class the migration plan flagged ("profile_tab.dart all-but-
  logout navy CTA drift").
- **Destructive actions**: logout-confirm and delete-account-confirm
  buttons converted from raw `ElevatedButton(backgroundColor: C.red)` to
  `AppButton.destructive` (delete-account's loading-spinner state now uses
  `AppButton`'s built-in `loading:` param instead of a hand-rolled
  `SizedBox`+`CircularProgressIndicator`).
- Hardcoded strings fixed on the **main page body and its two confirmation
  dialogs** (the most-visible surface): photo-picker sheet options, photo
  upload success/failure messages, default display name, logout dialog
  (title/body/buttons), delete-account dialog (title/body/error/buttons),
  points-sheet subtitle and button.
- One duplicate locale key introduced then caught: `choose_from_gallery`
  already existed (different call site, slightly different Lao wording,
  `'ເລືອກຈາກຄັງຮູບ'` vs. this screen's `'ເລືອກຈາກຄັງຮູບພາບ'`) — renamed to
  `profile_choose_from_gallery`/`profile_take_new_photo` to avoid silently
  merging two different existing texts. Caught via `flutter analyze`'s
  `equal_keys_in_map` warning before commit, not left in.

---

## 6. Localization changes

### The `review_screen.dart` regression (investigated per §4 of the prompt)

Confirmed via direct code inspection (not git history, which wasn't
needed — the file's own comments document exactly what was removed, e.g.
`// ✅ [FIX-2] Lao string ໂດຍກົງ ແທນ tr('select_star')`) that a prior pass
had deliberately replaced ~15 `tr()` calls with hardcoded Lao strings.

Several of the original keys those comments named (`select_star`,
`review_thanks`, `review_hint`, `submit_review`, `star_1`, `star_2`) still
existed in `app_locale.dart` — **but their stored values no longer matched
the Lao text actually shipping** (e.g. `select_star` held `'ກະລຸນາເລືອກດາວ'`
while the live hardcoded string was `'ກະລຸນາເລືອກດາວກ່ອນ'` — an added word;
`review_thanks` held a short one-line `'ຂອບໃຈສຳລັບລີວິວ! 🙏'` while the live
text was a different, longer two-line message entirely). Per this batch's
explicit "compare old Lao output with new Lao output, don't blindly reuse
a key because the English meaning looks similar" instruction, these 6 keys
were **updated to match the currently-shipping text** (confirmed unused
anywhere else first, so updating them changes nothing for any other call
site) rather than reused as-is or left mismatched. `book_again` and
`view_history` matched exactly and were reused directly with no change.

12 new dedicated keys were added for strings that had no matching key at
all (default customer name, duplicate-review error, comment-field label,
"out of 5 stars" semantics suffix, job-completed header title/subtitle).

**Verification**: for every one of these, the final `lo` value was
diffed against the pre-edit hardcoded string before committing — Lao
output is unchanged for every status/label except the 6 explicitly listed
above, where the change is a documented, deliberate correction (fixing a
stale key back to match reality), not a silent wording drift.

### Cross-file total

~60 new locale keys added across `app_locale.dart` this batch (all 4
locales each) covering: review screen (18), rewards screen (17), referral
screen + provider (16), chat screen (8), profile screen (12), support
(0 new — reused existing `faq_title`). One duplicate key
(`choose_from_gallery`) was caught and renamed before commit (§5).

---

## 7. Design-system migration

| Pattern | Before → After |
|---|---|
| Raw `TextStyle` matching an `AppTypography` role exactly | Migrated in review/notification/rewards/referral/chat/support screens (~25 sites) — same rule as Batch B: size match required, only color/weight as the delta |
| `BorderRadius.circular(N)` off-token or literal-but-matching | Converged to `AppRadius.chip/card/sheet` tokens across all 7 files |
| Navy CTA on the primary action of its screen/sheet | Fixed: rewards redeem, referral redeem, ProfileScreen's 5 bottom-sheet Save/Confirm buttons |
| Raw destructive `ElevatedButton(backgroundColor: C.red)` | `AppButton.destructive` — ProfileScreen logout + delete-account |
| Emoji as a functional (non-decorative) icon | Fixed: review screen's 5 star-rating faces → Material icons |
| Ad hoc error state with no retry | Fixed: rewards screen's settings-load branch |
| Ad hoc empty state where a real bug (not just style) was hiding underneath | Fixed: referral screen's `info == null` state, previously showing the wrong message entirely |

**Not converted, documented as intentional exceptions**: Submit Review's
raw `ElevatedButton` (better loading pattern, matches Phase 1 precedent),
referral's Share button (color scheme `AppButton` doesn't express),
`_ChatIllustration`-based empty states (richer than `EmptyStateView`),
ProfileScreen's "Add address" outline button (genuinely secondary, kept
navy-outline correctly).

No new colors, spacing tokens, radius tokens, or typography tiers were
introduced anywhere in this batch.

---

## 8. Accessibility findings

- Fixed: `referral_screen.dart`'s copy-code tooltip (was hardcoded, not
  missing — restored to `tr()`); `chat_screen.dart`'s back button (was
  genuinely missing a tooltip, added).
- Swept `IconButton(` usage in review/notification/rewards/support screens
  — **zero** bare icon-only buttons found needing a tooltip fix in those
  four files (confirmed by direct grep, not assumed).
- **Not swept**: `ProfileScreen`'s ~15 bottom sheets may contain
  icon-only controls (e.g. the `PopupMenuButton` on address list items,
  which already has an implicit accessible label via Flutter's default
  `PopupMenuButton` semantics) that weren't individually audited in this
  pass — flagged in §15, not silently claimed as covered.
- No touch-target regressions introduced; `AppButton`/`AppIconButton`
  conversions all meet or exceed 44dp by construction.

---

## 9. UX findings

- **`review_screen.dart` §11 special check — Book Again / View History
  verified intact**: read both `onPressed` callbacks after conversion to
  `AppButton.outline`/`AppButton.ghost` and confirmed the exact Phase 0
  P0-1 logic is unchanged — Book Again still does
  `ref.read(mainShellTabIndexProvider.notifier).state = 0` →
  `popUntil(isFirst)` → push `ProviderDetailsScreen(providerId: ...)` (not
  a bare pop to Home); View History still calls `goToBookingTab(context, ref)`.
  Neither button's navigation logic was touched, only the widget wrapping it.
- Referral screen's wrong-message bug (§5) is the one concrete "misleading
  UI" defect found and fixed this batch.
- Rewards settings' missing retry (§5) is the one concrete "missing error
  state" defect found and fixed.
- No dead buttons found in any fully-audited file (review, notification,
  rewards, referral, chat, support).
- Money-adjacent screens (rewards, referral — §7 of the master prompt)
  received the extra scrutiny requested: both had a genuine navy-CTA
  trust-color issue, both are now fixed.

---

## 10. Business logic verification

Confirmed unmodified by direct inspection of every touched file:
- `review_screen.dart`'s `_submit()` transaction (doc-ID-as-bookingId,
  duplicate-check, Cloud-Function-driven rating aggregation) — read, not
  edited beyond the exception message's text value.
- `rewards_provider.dart` — not touched at all; only the screen's
  `.when()` branches changed.
- `referral_provider.dart` — `redeemReferralCode()`'s control flow
  (validation order, transaction, Firestore writes) is byte-identical;
  only the literal string values returned changed.
- `chat_screen.dart` — every RTDB/Firestore read/write, timeout, and
  retry-timer mechanism is unchanged; confirmed by diffing that only
  `style:`/`Text(...)` /`tr(...)` lines changed.
- `main.dart` `ProfileScreen` — Firestore writes in `_editProfile()`,
  `_showSecurity()`'s password-change flow, `_confirmDeleteAccount()`'s
  Cloud Function call, and the address `WriteBatch` logic are all
  unchanged; only button widgets/colors and dialog strings changed.

---

## 11. Known exceptions (intentional, documented inline in code)

1. `review_screen.dart` Submit Review button — kept as raw `ElevatedButton`
   for its `_BtnLoadingSkeleton`.
2. `referral_screen.dart` Share button — kept as raw `ElevatedButton` for
   its white-on-navy-card color scheme.
3. `chat_screen.dart` empty states — kept `_ChatIllustration` over
   `EmptyStateView`.
4. `chat_screen.dart`'s `'User'` sender-name fallback and the initial
   `'ເລີ່ມການສົນທະນາ'` chat `lastMessage` value — **not localized**,
   because both are values persisted into RTDB/Firestore records rather
   than re-rendered per-viewer; flagged for a future explicitly-scoped
   decision rather than touched under this batch's "don't modify chat
   backend" constraint.
5. `main.dart`'s "Add new address" outline button — correctly stays navy
   (genuinely secondary action).
6. Rewards/referral balance-card and code-card navy backgrounds — correct
   brand-surface usage, not CTAs.

## 12. Out-of-scope findings

None discovered this batch requiring a new `OUT_OF_SCOPE_FINDINGS.md`
bug entry. Exception #4 above is a design/data-modeling question, not a
bug, so it's logged in this audit rather than that file.

## 13. Regression assessment

**Zero regressions.** `flutter analyze` (0 errors, same 2 warnings, issue
count *decreased*) and `flutter test` (236/12, identical failing-test
list) both confirm this against the recorded Batch C baseline. The one
in-flight mistake (duplicate `choose_from_gallery` locale key) was caught
by `flutter analyze` itself before commit, not left for review to find.

## 14. Commit

One commit for all of Batch C. See git log for the hash.

---

## 15. Remaining issues — read before assuming ProfileScreen is "done"

`ProfileScreen` (`main.dart`, ~1780 lines) is the largest single screen in
the app and contains **~15 separate `showModalBottomSheet`/`showDialog`
flows** (edit profile, security/change-password, forgot-password OTP,
reset-password, address management, payment methods, notification
preferences, help, terms & privacy, points, photo picker, logout, delete
account). This batch fixed:
- Every navy-CTA-on-a-primary-action color violation (the specific,
  concretely-flagged issue from the migration plan).
- Both destructive-action buttons.
- Hardcoded strings on the main page body and the two confirmation
  dialogs directly reachable from it.

It did **not** do a full hardcoded-string/typography/radius sweep of the
remaining ~10 bottom sheets (edit-profile field labels, security-sheet
labels, address-management dialog/menu strings, payment-methods sheet,
notification-preferences labels, help sheet, terms/privacy sheet, the
`_stat`/`_group`/`_tile`/`_legalSection` helper widgets' typography). Most
of these still contain hardcoded Lao text and off-token `TextStyle`/
`BorderRadius` literals. This is the same honest scope decision Phase 1
made for `booking_form_screen.dart` (also its era's largest file) —
documented here explicitly rather than claimed as done. **A full
ProfileScreen convergence pass, sized similarly to this entire Batch C
session, is the natural candidate for a dedicated future pass** — it
should not be assumed included in "Batch C complete."

The 3 category-C (ambiguous, unresolved) `TextStyle` sites already logged
in `LINTHO_PHASE2_BATCH_B_AUDIT.md` are unrelated to this batch and remain
open from Batch B.

## 16. Recommendation for Batch D

Batch D (Provider Core: `provider_dashboard.dart`, `home_tab.dart`,
`jobs_tab.dart`, `job_workflow_Screen.dart`, `earnings_tab.dart`,
`profile_tab.dart`) can proceed once this audit is reviewed. Two open
questions from the original migration plan remain relevant there and
should be resolved before or at the start of Batch D:
- `job_workflow_Screen.dart`'s intentional per-step button colors (verify
  they resolve from `AppStatus`/existing semantic tokens, not new
  hardcoded hex, per the approved instruction).
- `StatCard`'s stale "wallet/earnings" doc-comment vs. `earnings_tab.dart`'s
  actual hand-rolled implementation.

Given `profile_tab.dart` (provider-side) is a **different, larger** file
than the `ProfileScreen` covered here (customer-side, in `main.dart`), and
this batch's experience shows a ~1800-line profile-style screen consumes
a full batch's worth of effort to do properly, recommend treating
`profile_tab.dart` with the same bounded-scope expectation set in §15
rather than assuming it will get full convergence within Batch D
alongside the other 5 provider files.
