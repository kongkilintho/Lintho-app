const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');
const { defineSecret } = require('firebase-functions/params');
admin.initializeApp();

// 🔒 [Security fix] Cloudinary API secret — ຕ້ອງຕັ້ງຄ່າກ່ອນ deploy:
//   firebase functions:secrets:set CLOUDINARY_API_SECRET
//   firebase functions:secrets:set CLOUDINARY_API_KEY
// (ຫາໄດ້ຢູ່ Cloudinary Dashboard → Settings → API Keys — ຫ້າມ hardcode
// ຫຼືສົ່ງໃຫ້ client ໂດຍກົງ, ບໍ່ຄືກັນກັບ cloud name ທີ່ບໍ່ແມ່ນຄວາມລັບ)
const CLOUDINARY_API_SECRET = defineSecret('CLOUDINARY_API_SECRET');
const CLOUDINARY_API_KEY = defineSecret('CLOUDINARY_API_KEY');
const CLOUDINARY_CLOUD_NAME = 'duznxeuny';

const db = admin.firestore();
const messaging = admin.messaging();

function _getChannelId(type) {
  if (type === 'chat') return 'lintho_chat';
  if (type === 'payment') return 'lintho_payment';
  return 'lintho_jobs';
}

// 🔒 [AUDIT CUST-4 / 2026-08-02 — Medium, fresh re-audit] users/{uid}.notifPrefs
// (written by the "ການແຈ້ງເຕືອນ" settings sheet in main.dart — keys
// 'newBooking'/'status'/'promo'/'news', all default true except promo/news)
// was never read by ANY server-side notification path — toggling a
// preference off had zero effect, since onBookingStatusChange/onNewBooking/
// cleanupExpiredBookings all wrote directly to fcm_queue unconditionally.
// Maps the fcm_queue `type` values this file actually sends to the
// preference key that should gate them; a type with no mapping (e.g. 'chat')
// is never preference-gated. Defaults to enabled if the user has never
// touched the toggle or the doc/field doesn't exist, matching the same
// default the client itself uses.
const NOTIF_PREF_KEY_BY_TYPE = {
  new_booking: 'newBooking',
  booking_update: 'status',
  payment: 'status',
};

// 🔒 [AUDIT BE-2 / 2026-08-02 — High, fresh re-audit] ທຸກ fcm_queue write ໃນ
// ໄຟລ໌ນີ້ໃຊ້ .add() (random doc ID) — ຖ້າ Cloud Functions redeliver event ດຽວກັນ
// ຊ້ຳ (documented at-least-once behavior), ແຕ່ລະ invocation ຂຽນ doc ໃໝ່ໆ
// ຢູ່ສະເໝີ, ໄດ້ push ຊ້ຳ (ເຊັ່ນ "✅ ຊ່າງຮັບງານແລ້ວ!" 2-3 ຄັ້ງ). ຕອນນີ້
// queueNotification() ຮັບ `dedupeKey` ເລືອກໄດ້ — ຖ້າມີ, ໃຊ້ເປັນ doc ID ແທນ
// random (ບໍ່ຂຽນຊ້ຳຖ້າ doc ນັ້ນມີແລ້ວ). ຄ່າ dedupeKey ຕ້ອງເປັນສິ່ງທີ່ບົ່ງບອກ
// "ເຫດການດຽວກັນ" ຢ່າງແທ້ຈິງ (ບໍ່ແມ່ນ "ປະເພດດຽວກັນ" ເປົ່າໆ — booking ໜຶ່ງອາດມີ
// ຫຼາຍ 'booking_update' notification ຄົນລະ status ກັນ, ຈຶ່ງຕ້ອງລວມ status ເຂົ້າ
// ໄປໃນ key ນຳ, ບໍ່ດັ່ງນັ້ນ notification ທີ່ 2 ຈະຖືກເຂົ້າໃຈຜິດວ່າເປັນ retry
// ຂອງອັນທຳອິດ ແລະ ຖືກຂ້າມໄປ).
async function queueNotification({ targetUserId, targetRole, type, bookingId, title, body, dedupeKey }) {
  const prefKey = NOTIF_PREF_KEY_BY_TYPE[type];
  if (prefKey) {
    const userSnap = await db.collection('users').doc(targetUserId).get();
    const enabled = userSnap.data()?.notifPrefs?.[prefKey];
    if (enabled === false) return null; // user explicitly opted out
  }
  const payload = {
    targetUserId, targetRole, type, bookingId,
    title, body, data: { type, bookingId },
    createdAt: admin.firestore.FieldValue.serverTimestamp(), sent: false,
  };
  if (!dedupeKey) return db.collection('fcm_queue').add(payload);

  // targetUserId is part of the key too — a single event can legitimately
  // notify two different people (e.g. both parties on a cancellation) with
  // the same type/dedupeKey, and those must not collide with each other.
  const docId = `${bookingId || 'na'}_${type}_${dedupeKey}_${targetUserId}`
    .replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 300);
  const ref = db.collection('fcm_queue').doc(docId);
  const existing = await ref.get();
  if (existing.exists) return null; // already queued for this exact event
  await ref.set(payload);
  return ref;
}

// 🔒 [AUDIT N-09/N-10/N-11 / 2026-08-08 — Medium, notification E2E audit]
// Shared by processFCMQueue (onCreate) and retryFailedFcmQueue (scheduled
// sweep) so both paths behave identically. Three fixes bundled here:
//   N-11: token lookup now always reads users/{targetUserId} regardless of
//   targetRole — saveToken() (fcm_service.dart) already writes every user's
//   token there unconditionally; the old providers/{uid} mirror this used to
//   read from is being retired because that document is world-readable
//   (needed for the job board), which was leaking every provider's raw FCM
//   tokens to any logged-in user.
//   N-09: sendEachForMulticast's per-token result is now inspected —
//   tokens FCM reports as dead (uninstalled/reinstalled/revoked) are pruned
//   from fcmTokens instead of being retried forever.
//   N-10: a thrown error (network/quota/auth-level failure — not a per-token
//   failure, those come back in `result.responses` without throwing) used to
//   be marked sent:true unconditionally, permanently dropping a notification
//   that may only have failed transiently. Now retried up to
//   MAX_FCM_RETRIES times by retryFailedFcmQueue before being given up on.
const MAX_FCM_RETRIES = 5;

async function attemptFcmDelivery(ref, data) {
  const { targetUserId, title, body } = data;
  const msgData = data.data || {};
  try {
    const userDoc = await db.collection('users').doc(targetUserId).get();
    if (!userDoc.exists) return ref.update({ sent: true });
    const tokens = userDoc.data().fcmTokens || [];
    if (tokens.length === 0) return ref.update({ sent: true });

    const result = await messaging.sendEachForMulticast({
      notification: { title, body },
      data: msgData,
      android: { priority: 'high', notification: { sound: 'default', channelId: _getChannelId(data.type) } },
      apns: { payload: { aps: { sound: 'default', badge: 1 } } },
      tokens,
    });

    const deadTokens = [];
    result.responses.forEach((resp, idx) => {
      const code = resp.error && resp.error.code;
      if (!resp.success && (code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token')) {
        deadTokens.push(tokens[idx]);
      }
    });
    if (deadTokens.length > 0) {
      await db.collection('users').doc(targetUserId)
        .update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(...deadTokens) });
    }

    return ref.update({ sent: true, successCount: result.successCount });
  } catch (err) {
    const retryCount = (data.retryCount || 0) + 1;
    if (retryCount >= MAX_FCM_RETRIES) {
      return ref.update({ sent: true, error: err.message, retryCount, giveUp: true });
    }
    return ref.update({ sent: false, error: err.message, retryCount });
  }
}

exports.processFCMQueue = functions.firestore
  .document('fcm_queue/{docId}')
  .onCreate(async (snap) => {
    const data = snap.data();
    if (!data || data.sent) return null;
    return attemptFcmDelivery(snap.ref, data);
  });

// retryCount > 0 restricts this to docs processFCMQueue already attempted
// and failed on (onCreate only fires once per doc, so it can never race a
// freshly-created doc that hasn't been attempted yet — those always have
// retryCount unset).
exports.retryFailedFcmQueue = functions.pubsub
  .schedule('every 10 minutes')
  .onRun(async () => {
    const snap = await db.collection('fcm_queue')
      .where('sent', '==', false)
      .where('retryCount', '>', 0)
      .get();
    if (snap.empty) return null;
    return Promise.all(snap.docs.map((doc) => attemptFcmDelivery(doc.ref, doc.data())));
  });

exports.onBookingStatusChange = functions.firestore
  .document('bookings/{bookingId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const bookingId = context.params.bookingId;
    const queue = [];

    // 🔒 [AUDIT BE-3/PROV-3 / 2026-07-30] match_screen.dart's _sendRequestToTop3()
    // ຂຽນ sentTo (top-3 provider ທີ່ຖືກເລືອກ) ໂດຍບໍ່ປ່ຽນ status ເລີຍ (ຍັງເປັນ
    // 'pending' ຄືເກົ່າ) — ຂຽນນີ້ຈຶ່ງບໍ່ເຄີຍຜ່ານ early-return ຂ້າງລຸ່ມ (before.status
    // === after.status), ໝາຍຄວາມວ່າ 3 ຊ່າງທີ່ຖືກເລືອກບໍ່ເຄີຍໄດ້ຮັບ push ເລີຍ (ມີ
    // // TODO ຄ້າງໄວ້ໃນ match_screen.dart ຢືນຢັນວ່າບໍ່ເຄີຍເຮັດສຳເລັດ). ຄິດໄລ່ uid
    // ໃໝ່ທີ່ຖືກເພີ່ມເຂົ້າ sentTo ໃນ write ນີ້ເທົ່ານັ້ນ (ບໍ່ແມ່ນທັງ array — retry ທີ່
    // ປ່ຽນ candidate ບໍ່ຄວນ notify ຄົນເກົ່າຊ້ຳ) ແລ້ວ queue notification ໃຫ້ແຕ່ລະຄົນ.
    // ຢູ່ນອກ early-return ຂ້າງລຸ່ມ ເພື່ອໃຫ້ firing ບໍ່ວ່າ status ຈະປ່ຽນຫຼືບໍ່.
    const beforeSentTo = before.sentTo || [];
    const afterSentTo = after.sentTo || [];
    const newlySent = afterSentTo.filter((id) => !beforeSentTo.includes(id));
    if (newlySent.length > 0) {
      const svcLabelForSentTo = after.serviceType || after.category || 'ບໍລິການ';
      newlySent.forEach((providerUid) => {
        queue.push(queueNotification({
          targetUserId: providerUid, targetRole: 'provider',
          type: 'new_booking', bookingId,
          title: '🔔 ງານໃໝ່!', body: `ມີວຽກ ${svcLabelForSentTo} ໃໝ່ໃຫ້ທ່ານ`,
          dedupeKey: 'sent', // each provider only ever added to sentTo once
        }));
      });
    }

    // 🔒 [AUDIT PROV-1 / 2026-07-30] ອະນຸມັດຄ່າໃຊ້ຈ່າຍເພີ່ມ *ຫຼັງ* booking completed
    // ໄປແລ້ວ (status ບໍ່ປ່ຽນຢູ່ໃນ write ນີ້) — block ຄິດໄລ່ payout ຫຼັກຂ້າງລຸ່ມ
    // (after.status === 'completed' ພາຍໃນ if (before.status !== after.status))
    // ບໍ່ເຄີຍຮອດເລີຍໃນກໍລະນີນີ້ ເພາະ early-return ຂ້າງເທິງ. ຢູ່ນອກ/ກ່ອນ early-return
    // ນັ້ນໂດຍເຈດຕະນາ — mutually exclusive ກັບ block ຫຼັກ (ອັນນັ້ນຮຽກກ່ອນ status
    // ປ່ຽນເປັນ completed ແທ້, ອັນນີ້ຮຽກກ່ອນ status ບໍ່ປ່ຽນ) ຈຶ່ງບໍ່ມີທາງຄິດໄລ່ຊ້ຳກັນ.
    const chargesJustApproved = !before.additionalChargesApproved && after.additionalChargesApproved;
    if (before.status === after.status && after.status === 'completed' && chargesJustApproved &&
        after.paymentStatus === 'paid' && after.additionalCharges > 0) {
      const svcLabelForCharges = after.serviceType || after.category || 'ບໍລິການ';
      queue.push(grantAdditionalChargesWalletCredit(
        after.providerId, bookingId, svcLabelForCharges, after.additionalCharges, change.after.ref,
        after.paymentMethod));
      queue.push(queueNotification({
        targetUserId: after.providerId, targetRole: 'provider',
        type: 'payment', bookingId,
        title: '💰 ລາຍຮັບເພີ່ມເຂົ້າ!', body: `₭${after.additionalCharges} ຄ່າໃຊ້ຈ່າຍເພີ່ມ`,
        dedupeKey: `charges_${after.additionalChargesRound || 1}`,
      }));
    }

    if (before.status === after.status) return Promise.all(queue);
    const { customerId, providerId, serviceType, category, price, additionalCharges, additionalChargesApproved } = after;
    // ✅ [FIX HI-4] serviceType ອາດຂາດຢູ່ໃນ booking ເກົ່າ (ຫຼືກໍລະນີບໍ່ຄາດຄິດ) —
    // fallback ໄປ category ເພື່ອບໍ່ໃຫ້ notification ສະແດງ "undefined"
    const svcLabel = serviceType || category || 'ບໍລິການ';
    const providerDoc = await db.collection('providers').doc(providerId).get();
    const providerName = providerDoc.data()?.displayName || 'ຊ່າງ';
    // 🔒 [AUDIT BE-2 / 2026-08-02] dedupeKey = after.status — each of the
    // if-blocks below fires for a distinct, one-time status transition
    // (booking status only moves forward), so keying on it dedupes retries
    // of the *same* transition without collapsing genuinely different ones.
    const notify = (targetUserId, targetRole, title, body, type) => {
      queue.push(queueNotification({ targetUserId, targetRole, type, bookingId, title, body, dedupeKey: after.status }));
    };
    if (after.status === 'accepted') notify(customerId, 'customer', '✅ ຊ່າງຮັບງານແລ້ວ!', `${providerName} ກຳລັງກຽມໄປ`, 'booking_update');
    if (after.status === 'onTheWay') notify(customerId, 'customer', '🚗 ຊ່າງກຳລັງໄປ!', `${providerName} ກຳລັງເດີນທາງ`, 'booking_update');
    if (after.status === 'arrived') notify(customerId, 'customer', '📍 ຊ່າງຮອດແລ້ວ!', `${providerName} ຢູ່ໜ້ານາງ`, 'booking_update');
    // 🔒 [AUDIT CUST-2 / 2026-07-30] ທຸກ transition ອື່ນ (accepted/onTheWay/
    // arrived/completed/rejected/cancelled) ມີ notify() ໝົດ — inProgress ຄົນ
    // ດຽວທີ່ບໍ່ເຄີຍແຈ້ງລູກຄ້າ (ຊ່າງເລີ່ມເຮັດວຽກແລ້ວແຕ່ລູກຄ້າບໍ່ຮູ້).
    if (after.status === 'inProgress') notify(customerId, 'customer', '🔧 ຊ່າງເລີ່ມເຮັດວຽກແລ້ວ!', `${providerName} ກຳລັງເຮັດວຽກ ${svcLabel}`, 'booking_update');
    if (after.status === 'completed') {
      notify(customerId, 'customer', '🎉 ວຽກສຳເລັດ!', `${svcLabel} ສຳເລັດ · ກະລຸນາໃຫ້ຄະແນນ`, 'booking_update');

      // 🔒 [AUDIT QA-1 / HI-1, HI-2] ກ່ອນໜ້ານີ້ wallet credit ອອກທັນທີເມື່ອ
      // status=='completed' ໂດຍບໍ່ກວດ paymentStatus ຢູ່ຝັ່ງ server ເລີຍ — ຖ້າ
      // firestore.rules ຖືກຫຼີກລ້ຽງ ຫຼື doc ຖືກແກ້ຈາກ console ໂດຍກົງ, ຊ່າງຈະໄດ້
      // ຮັບເງິນສຳລັບວຽກທີ່ບໍ່ເຄີຍຈ່າຍ. ຕອນນີ້ກວດ paymentStatus=='paid' ຢູ່ນີ້ນຳ
      // (ບໍ່ອີງໃສ່ Flutter client ຫຼື rules ຝ່າຍດຽວ) ກ່ອນອອກເງິນ/ໂບນັດໃດໆ.
      if (after.paymentStatus !== 'paid') {
        console.warn(`onBookingStatusChange: booking ${bookingId} status=completed but paymentStatus='${after.paymentStatus}' — skipping wallet credit/referral/reward payouts.`);
      } else {
        const total = (price || 0) + (additionalChargesApproved ? (additionalCharges || 0) : 0);
        notify(providerId, 'provider', '💰 ລາຍຮັບເຂົ້າ!', `₭${total} ຈາກ ${svcLabel}`, 'payment');

        // 🔒 [AUDIT QA-1 / HI-3] wallet increment ບໍ່ເຄີຍມີ idempotency guard
        // (ຕ່າງຈາກ referralRewardIssued/rewardPointsIssued ຂ້າງລຸ່ມ) — Cloud
        // Functions ອາດຖືກ trigger ຊ້ຳ (at-least-once) ແລ້ວຝາກເງິນຊ້ຳສອງເທື່ອ.
        // ຕອນນີ້ໃຊ້ walletCredited flag ໃນ transaction ດຽວກັນ (pattern ດຽວກັນ
        // ກັບ grantRewardPoints).
        queue.push(grantWalletCredit(providerId, bookingId, svcLabel, total, change.after.ref, after.paymentMethod));

        // ✅ Referral: ໝູ່ໃຊ້ບໍລິການສຳເລັດ → ຜູ້ແນະນຳໄດ້ voucher
        // referralRewardIssued ກັນ trigger ຍິງຊໍ້າ/ໂບນັດອອກຊໍ້າ
        if (after.referralCode && !after.referralRewardIssued) {
          queue.push(grantReferralReward(after.referralCode, customerId, bookingId, change.after.ref));
        }

        // ✅ Rewards: ໄດ້ແຕ້ມຈາກ booking ສຳເລັດ — ອັດຕາ % ຕັ້ງຢູ່ settings/rewards
        // (ປັບໄດ້ໂດຍ admin ບໍ່ຕ້ອງ deploy ໃໝ່). rewardPointsIssued ກັນຍິງຊໍ້າ.
        if (!after.rewardPointsIssued) {
          queue.push(grantRewardPoints(customerId, total, bookingId, change.after.ref));
        }
      }
    }
    if (after.status === 'rejected') notify(customerId, 'customer', '❌ ຖືກປະຕິເສດ', `${svcLabel} ຖືກປະຕິເສດ`, 'booking_update');
    if (after.status === 'cancelled') {
      // 🔒 [AUDIT PROV-2 / 2026-07-30] ຕອນນີ້ຊ່າງເອງກໍ່ຍົກເລີກໄດ້ (ຫຼັງຮັບງານໄປແລ້ວ
      // ແຕ່ເຮັດຕໍ່ບໍ່ໄດ້) — ຖ້າຍັງ notify() ໃສ່ providerId ຢ່າງດຽວຄືເກົ່າ ຈະກາຍເປັນ
      // ແຈ້ງຊ່າງເລື່ອງການຍົກເລີກຂອງຕົນເອງ (ບໍ່ມີປະໂຫຍດ) ໂດຍ *ບໍ່ເຄີຍ* ແຈ້ງລູກຄ້າເລີຍ
      // ວ່າຊ່າງຍົກເລີກ. ໃຊ້ cancelledBy (ຕັ້ງໂດຍ providerCancelBooking()/
      // cancelBooking()) ຕັດສິນວ່າຝ່າຍໃດຄວນຖືກແຈ້ງ.
      if (after.cancelledBy === 'provider') {
        notify(customerId, 'customer', '❌ ຊ່າງຍົກເລີກວຽກ', `${svcLabel} ຖືກຊ່າງຍົກເລີກ`, 'booking_update');
      } else if (providerId) {
        // 🔒 [AUDIT QA-1 / LO-6] providerId ອາດວ່າງເປົ່າ (booking ຍັງບໍ່ເຄີຍຖືກຮັບ
        // ເລີຍ ຕອນລູກຄ້າຍົກເລີກ) — notify() ຂຽນ fcm_queue doc ໄດ້ປົກກະຕິແມ້
        // targetUserId ວ່າງ, ແຕ່ບໍ່ຄວນ notify provider ທີ່ບໍ່ມີໂຕຕົນຈິງ
        notify(providerId, 'provider', '❌ ຍົກເລີກ', `${svcLabel} ຖືກຍົກເລີກ`, 'booking_update');
      }

      // 🔒 [AUDIT BE-5 / 2026-08-02 — Low, fresh re-audit] previously flagged
      // as an ambiguous, undocumented product decision — usedCount was never
      // reverted when a customer cancelled a coupon-discounted booking
      // before any provider accepted it (no service was ever rendered, so
      // charging the redemption permanently is the less defensible default).
      // Scoped to before.status === 'pending' only — once a provider has
      // accepted, the coupon is treated as spent regardless of a later
      // cancellation, matching how the cancellation-fee grace window itself
      // only applies pre-acceptance. Server-side (not a client Firestore
      // write) so it doesn't need a new client-writable rules branch on
      // coupons/{id} beyond the existing +1-on-redeem one.
      if (before.status === 'pending' && after.couponCode) {
        queue.push(revertCouponUsageIfPending(after.couponCode, bookingId, change.after.ref));
      }
    }

    // 🔒 [AUDIT H6] ກ່ອນໜ້ານີ້ providers/{id}.totalJobs/completionRate ຖືກ
    // ຄິດໄລ່ຝັ່ງ client (review_screen.dart) ຕອນສົ່ງ review ເທົ່ານັ້ນ — ຖ້າລູກຄ້າ
    // ບໍ່ເຄີຍສົ່ງ review, ຄ່ານີ້ບໍ່ເຄີຍອັບເດດເລີຍ ທັງໆທີ່ຄວນປ່ຽນທຸກຄັ້ງທີ່ວຽກ
    // completed/cancelled/rejected. ຕອນນີ້ຄິດໄລ່ຢູ່ນີ້ (ຈຸດແທ້ທີ່ status ປ່ຽນ),
    // ບໍ່ຕ້ອງອີງໃສ່ວ່າມີ review ຫຼືບໍ່. ບໍ່ຕ້ອງການ idempotency flag ເພາະ count()
    // ຄິດໄລ່ຄືນຈາກສູນທຸກຄັ້ງ — ຄ່າສຸດທ້າຍຄືກັນສະເໝີບໍ່ວ່າຈະຖືກ trigger ຊ້ຳຈັກເທື່ອ.
    if (providerId && ['completed', 'cancelled', 'rejected'].includes(after.status)) {
      queue.push(updateProviderJobStats(providerId));
    }
    return Promise.all(queue);
  });

async function updateProviderJobStats(providerId) {
  const bookingsRef = db.collection('bookings');
  const [completedSnap, cancelledSnap, rejectedSnap] = await Promise.all([
    bookingsRef.where('providerId', '==', providerId).where('status', '==', 'completed').count().get(),
    bookingsRef.where('providerId', '==', providerId).where('status', '==', 'cancelled').count().get(),
    bookingsRef.where('providerId', '==', providerId).where('status', '==', 'rejected').count().get(),
  ]);
  const completedCount = completedSnap.data().count || 0;
  const cancelledCount = cancelledSnap.data().count || 0;
  const rejectedCount = rejectedSnap.data().count || 0;
  const totalAttempted = completedCount + cancelledCount + rejectedCount;
  const completionRate = totalAttempted > 0
    ? Math.round((completedCount / totalAttempted) * 1000) / 10
    : 0;
  return db.collection('providers').doc(providerId).set({
    totalJobs: completedCount,
    completionRate,
  }, { merge: true });
}

// 🔒 [AUDIT H6/H9] ກ່ອນໜ້ານີ້ review_screen.dart ຄິດໄລ່ rating ສະເລ່ຍ +
// ຂຽນ providers/{id}.rating ໂດຍກົງຈາກ client (firestore.rules ອະນຸຍາດ
// customer ຂຽນ field ນີ້ໂດຍກົງ, ບໍ່ຕ້ອງມີ review ຈິງ) — ໄດ້ຖືກຮັບປິດແລ້ວຢູ່
// firestore.rules (providers update ຫ້າມ rating/totalJobs/completionRate, ແລະ
// reviews create ຕ້ອງອ້າງ booking ຈິງ/completed/ບໍ່ເຄີຍ review). ຕອນນີ້ຄິດໄລ່
// rating ສະເລ່ຍ+ຕັ້ງ reviewed:true ຢູ່ນີ້ແທນ — atomic ດ້ວຍ transaction, ໃຊ້
// FieldValue.increment() ແທນການອ່ານ reviews subcollection ທັງໝົດຄືນທຸກຄັ້ງ
// (ຍົກເວັ້ນເທື່ອທຳອິດຫຼັງ migration ທີ່ຍັງບໍ່ມີ ratingSum/reviewCount seed ໄວ້ —
// backfill ຄັ້ງດຽວຈາກ subcollection ຕອນນັ້ນ, ຫຼັງຈາກນັ້ນເປັນ O(1) ທຸກຄັ້ງ).
exports.onReviewCreated = functions.firestore
  .document('providers/{providerId}/reviews/{reviewId}')
  .onCreate(async (snap, context) => {
    const review = snap.data();
    const { providerId } = context.params;
    const bookingId = review?.bookingId;
    if (!review || !bookingId) return null;

    const bookingRef = db.collection('bookings').doc(bookingId);
    const providerRef = db.collection('providers').doc(providerId);

    return db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) return;
      const booking = bookingSnap.data();

      // ✅ Defense-in-depth — firestore.rules ໄດ້ກວດເງື່ອນໄຂເຫຼົ່ານີ້ຢູ່ແລ້ວ
      // ຕອນ create, ແຕ່ກວດຄືນຢູ່ນີ້ນຳ (ບໍ່ອີງໃສ່ rules ຝ່າຍດຽວ), pattern ດຽວກັນ
      // ກັບ onBookingStatusChange ທີ່ກວດ paymentStatus ຄືນຢູ່ server.
      if (booking.customerId !== review.customerId ||
          booking.providerId !== providerId ||
          booking.status !== 'completed' ||
          booking.reviewed === true) {
        console.warn(`onReviewCreated: review ${context.params.reviewId} failed server-side validation for booking ${bookingId} — skipping aggregate update.`);
        return;
      }

      const providerSnap = await tx.get(providerRef);
      const p = providerSnap.data() || {};
      let ratingSum = p.ratingSum;
      let reviewCount = p.reviewCount;

      if (ratingSum === undefined || reviewCount === undefined) {
        // ✅ ຄັ້ງທຳອິດຫຼັງ migration — provider ນີ້ຍັງບໍ່ມີ ratingSum/reviewCount
        // ມາກ່ອນ, backfill ຈາກ reviews subcollection ທັງໝົດຄັ້ງດຽວ (ບໍ່ນັບ
        // review ໃໝ່ນີ້ ເພາະຈະບວກແຍກຕ່າງຫາກຂ້າງລຸ່ມ)
        const existingReviews = await db.collection('providers').doc(providerId)
          .collection('reviews').get();
        ratingSum = 0;
        reviewCount = 0;
        existingReviews.forEach((d) => {
          if (d.id === context.params.reviewId) return; // review ໃໝ່ນີ້ນັບແຍກຕ່າງຫາກ
          ratingSum += (d.data().rating || 0);
          reviewCount += 1;
        });
      }

      ratingSum += (review.rating || 0);
      reviewCount += 1;
      const rating = Math.round((ratingSum / reviewCount) * 10) / 10;

      tx.set(providerRef, { ratingSum, reviewCount, rating }, { merge: true });
      tx.update(bookingRef, { reviewed: true });
    });
  });

// ✅ ບໍ່ມີ backend ກວດ expiresAt ມາກ່ອນ — booking ທີ່ບໍ່ມີຊ່າງຮັບເລີຍ
// ຄ້າງເປັນ 'pending' ຕະຫຼອດໄປ. ກວດທຸກ 5 ນາທີ ແລະ auto-cancel.
exports.cleanupExpiredBookings = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db.collection('bookings')
      .where('status', '==', 'pending')
      .where('expiresAt', '<', now)
      .get();
    if (snap.empty) return null;
    // 🔒 [AUDIT BE-5 / 2026-07-30] ບໍ່ມີການແບ່ງ chunk ມາກ່ອນ — batch ດຽວມີ
    // ຂອບເຂດສູງສຸດ 500 operations (ຂອບເຂດຂອງ Firestore), ຖ້າ backlog ໃຫຍ່ກວ່າ
    // ນີ້ (ໄຟຟ້າດັບ/downtime ດົນ ຫຼື cron ບໍ່ໄດ້ run ຫຼາຍຮອບ) batch.commit() ຈະ
    // throw ແລະ booking ໝົດອາຍຸແມ່ນຫນຶ່ງກໍ່ບໍ່ຖືກຍົກເລີກເລີຍໃນຮອບນັ້ນ. ແບ່ງເປັນ
    // chunk ລະ ≤500 ແລ້ວ commit ແຍກກັນແທນ.
    const CHUNK_SIZE = 500;
    const chunks = [];
    for (let i = 0; i < snap.docs.length; i += CHUNK_SIZE) {
      chunks.push(snap.docs.slice(i, i + CHUNK_SIZE));
    }
    const notifications = [];
    await Promise.all(chunks.map((chunk) => {
      const batch = db.batch();
      chunk.forEach((doc) => {
        batch.update(doc.ref, {
          status: 'cancelled',
          cancelReason: 'expired_no_provider',
          cancelledBy: 'system',
        });
        const { customerId, serviceType, category } = doc.data();
        if (customerId) {
          notifications.push(queueNotification({
            targetUserId: customerId, targetRole: 'customer',
            type: 'booking_update', bookingId: doc.id,
            title: '⏰ ບໍ່ມີຊ່າງຮັບງານ',
            body: `${serviceType || category || 'ການຈອງ'} ຖືກຍົກເລີກ · ບໍ່ມີຊ່າງຮັບໃນເວລາ`,
            dedupeKey: 'expired', // a booking can only ever match this cron's query once
          }));
        }
      });
      return batch.commit();
    }));
    return Promise.all(notifications);
  });

// 🔒 [AUDIT PROV-3 / 2026-08-02 — High, fresh re-audit] cleanupExpiredBookings
// ຂ້າງເທິງກວດແຕ່ status=='pending' (ຍັງບໍ່ຖືກຮັບ) — booking ທີ່ຊ່າງຮັບໄປແລ້ວ
// (accepted/onTheWay/arrived/inProgress) ແຕ່ຫາຍໄປງຽບໆ (ອອບໄລນ໌/ບໍ່ເປີດແອັບອີກ,
// ບໍ່ໄດ້ກົດຍົກເລີກຢ່າງເປັນທາງການ) ບໍ່ມີ safety net ໃດເລີຍ — booking ຄ້າງຢູ່
// status ນັ້ນຕະຫຼອດໄປ, ລູກຄ້າບໍ່ມີທາງຮູ້/ອອກຈາກສະຖານະນັ້ນນອກຈາກຍົກເລີກເອງ.
// ຕອນນີ້ກວດທຸກ 30 ນາທີ — booking ໃດຄ້າງຢູ່ status ບໍ່-terminal ໂດຍບໍ່ມີການ
// ອັບເດດ (updatedAt, ຕອນນີ້ຖືກຂຽນທຸກຄັ້ງທີ່ status ປ່ຽນ — ເບິ່ງ
// booking_repository.dart) ເກີນ 24 ຊົ່ວໂມງ ຈະຖືກຍົກເລີກອັດຕະໂນມັດ ພ້ອມແຈ້ງທັງ
// ລູກຄ້າ ແລະ ຊ່າງ. ບໍ່ມີ reassignment (feature ນີ້ບໍ່ມີຢູ່ໃນລະບົບເລີຍ, ຢືນຢັນແລ້ວ
// ຈາກ admin-panel audit — ນອກຂອບເຂດ fix ນີ້). ຮູບແບບ chunk/batch ດຽວກັນກັບ
// cleanupExpiredBookings ຂ້າງເທິງ.
exports.cleanupStaleActiveBookings = functions.pubsub
  .schedule('every 30 minutes')
  .onRun(async () => {
    const threshold = admin.firestore.Timestamp.fromMillis(
      Date.now() - 24 * 60 * 60 * 1000);
    const snap = await db.collection('bookings')
      .where('status', 'in', ['accepted', 'onTheWay', 'arrived', 'inProgress'])
      .where('updatedAt', '<', threshold)
      .get();
    if (snap.empty) return null;
    const CHUNK_SIZE = 500;
    const chunks = [];
    for (let i = 0; i < snap.docs.length; i += CHUNK_SIZE) {
      chunks.push(snap.docs.slice(i, i + CHUNK_SIZE));
    }
    const notifications = [];
    await Promise.all(chunks.map((chunk) => {
      const batch = db.batch();
      chunk.forEach((doc) => {
        batch.update(doc.ref, {
          status: 'cancelled',
          cancelReason: 'stale_no_progress',
          cancelledBy: 'system',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const { customerId, providerId, serviceType, category } = doc.data();
        const svcLabel = serviceType || category || 'ການຈອງ';
        if (customerId) {
          notifications.push(queueNotification({
            targetUserId: customerId, targetRole: 'customer',
            type: 'booking_update', bookingId: doc.id,
            title: '⏰ ການຈອງຖືກຍົກເລີກ',
            body: `${svcLabel} ຖືກຍົກເລີກ · ຊ່າງບໍ່ມີການເຄື່ອນໄຫວດົນເກີນໄປ`,
            dedupeKey: 'stale', // a booking can only ever match this cron's query once
          }));
        }
        if (providerId) {
          notifications.push(queueNotification({
            targetUserId: providerId, targetRole: 'provider',
            type: 'booking_update', bookingId: doc.id,
            title: '⏰ ວຽກຖືກລະບົບຍົກເລີກ',
            body: `${svcLabel} ຖືກຍົກເລີກອັດຕະໂນມັດ · ບໍ່ມີການອັບເດດດົນເກີນໄປ`,
            dedupeKey: 'stale',
          }));
        }
      });
      return batch.commit();
    }));
    return Promise.all(notifications);
  });

// 🔒 [AUDIT BE-4 / 2026-08-02 — Low, fresh re-audit] fcm_queue accumulates
// forever — processFCMQueue marks a doc sent:true but nothing ever deletes
// it, unlike every other collection in this file that has some lifecycle
// bound (bookings terminate, transactions are an intentional ledger). Runs
// daily, deletes sent:true docs older than 7 days (kept briefly for support/
// debugging, not indefinitely). Chat records are intentionally left alone —
// unlike a push-notification outbox, chat history has support/dispute value
// and deleting it is a product decision, not a cleanup bug; out of scope
// here.
exports.cleanupOldFcmQueue = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async () => {
    const threshold = admin.firestore.Timestamp.fromMillis(
      Date.now() - 7 * 24 * 60 * 60 * 1000);
    const snap = await db.collection('fcm_queue')
      .where('sent', '==', true)
      .where('createdAt', '<', threshold)
      .get();
    if (snap.empty) return null;
    const CHUNK_SIZE = 500;
    const chunks = [];
    for (let i = 0; i < snap.docs.length; i += CHUNK_SIZE) {
      chunks.push(snap.docs.slice(i, i + CHUNK_SIZE));
    }
    await Promise.all(chunks.map((chunk) => {
      const batch = db.batch();
      chunk.forEach((doc) => batch.delete(doc.ref));
      return batch.commit();
    }));
    return null;
  });

exports.onNewBooking = functions.firestore
  .document('bookings/{bookingId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const bookingId = context.params.bookingId;
    if (!data) return null;
    const { providerId, customerId, serviceType, category, referralCode } = data;
    const svcLabel = serviceType || category || 'ບໍລິການ';
    const queue = [];

    // 🔒 [AUDIT BE-2 / 2026-07-30] providerId ບໍ່ມີເລີຍ (undefined) ສຳລັບ auto-
    // match booking ທຸກອັນ (Quick Booking / ຟອມຫຼັກທີ່ບໍ່ໄດ້ເລືອກຊ່າງ) — Admin SDK
    // throw synchronously ຕອນ .add({targetUserId: undefined, ...}) (ยืนยัน jing
    // ຜ່ານ firebase-admin ຈິງ), function ນີ້ຈຶ່ງ crash ກ່ອນຮອດ referral logic
    // ຂ້າງລຸ່ມທຸກຄັ້ງ. ຕອນນີ້ notify ສະເພາະຖ້າມີ providerId ແທ້ (booking ທີ່ຈອງຊ່າງ
    // ສະເພາະຄົນໂດຍກົງ) — auto-match booking ຈະຖືກ notify ຜ່ານ onBookingStatusChange
    // ຕອນ sentTo ຖືກຂຽນແທນ (ເບິ່ງ [AUDIT BE-3] ຂ້າງລຸ່ມ).
    if (providerId) {
      const customerDoc = await db.collection('users').doc(customerId).get();
      const customerName = customerDoc.data()?.displayName || 'ລູກຄ້າ';
      queue.push(queueNotification({
        targetUserId: providerId, targetRole: 'provider',
        type: 'new_booking', bookingId,
        title: '🔔 ງານໃໝ່!', body: `${customerName} ຕ້ອງການ ${svcLabel}`,
        dedupeKey: 'created', // fires once, at document creation
      }));
    }

    // ✅ Referral: ໝູ່ໃໝ່ນຳໂຄ້ດໄປໃຊ້ ໃນການຈອງຄັ້ງທຳອິດ → ໄດ້ສ່ວນຫຼຸດທັນທີ
    if (referralCode) {
      const priorBookings = await db.collection('bookings')
        .where('customerId', '==', customerId)
        .limit(2).get();
      const isFirstBooking = priorBookings.size <= 1; // doc ນີ້ນັບລວມຢູ່ແລ້ວ
      if (isFirstBooking) {
        queue.push(grantSignupVoucher(referralCode, customerId, bookingId, snap.ref));
      }
    }

    return Promise.all(queue);
  });

const REFERRAL_SIGNUP_BONUS = 20000;
const REFERRAL_REWARD_BONUS = 20000;

// 🔒 [AUDIT H2] ກ່ອນໜ້ານີ້ function ນີ້ແມ່ນອັນດຽວໃນບັນດາ grant*() ທີ່ບໍ່ມີ
// idempotency guard — ໃຊ້ .add() ໂດຍກົງ ບໍ່ໄດ້ຢູ່ໃນ transaction, ບໍ່ໄດ້ກວດ flag
// ໃດໆກ່ອນຂຽນ. ຖ້າ onNewBooking ຖືກ Cloud Functions trigger ຊ້ຳ (at-least-once
// retry — ພຶດຕິກຳທີ່ເອກະສານໄວ້ຢ່າງເປັນທາງການ), isFirstBooking (ຄິດໄລ່ຈາກ count
// query, ບໍ່ໄດ້ປ່ຽນລະຫວ່າງ retry) ຍັງເປັນ true ຢູ່ດີ → voucher ໃບທີສອງຖືກອອກ
// ຊ້ຳ. ຕອນນີ້ໃຊ້ pattern ດຽວກັນກັບ grantWalletCredit/grantReferralReward —
// signupVoucherIssued flag ຖືກກວດ+ຕັ້ງ "ພາຍໃນ" transaction ດຽວກັນກັບ voucher.
//
// 🔒 [AUDIT M-2 / 2026-07-27] ກອງແກ້ຄັ້ງທຳອິດ (ຂ້າງເທິງ) ຕັ້ງ flag ໄວ້ຢູ່
// bookingRef ("this booking's" signupVoucherIssued) — ບໍ່ແມ່ນ ownerUid ຂອງ
// customer. ຖ້າ customer ຄົນທີ່ຖືກແນະນຳສ້າງ 2 booking ໄວແທບພ້ອມກັນ (B1, B2),
// ທັງສອງ onNewBooking invocation ອາດ count() ເຫັນ "ນີ້ແມ່ນ booking ທຳອິດ" ພ້ອມ
// ກັນ (race — ອີກ doc ອາດຍັງບໍ່ visible ຕໍ່ query ຂອງອີກ invocation) ແລ້ວທັງສອງ
// ຝ່າຍກວດ flag ຄົນລະ booking doc (B1.signupVoucherIssued ແລະ
// B2.signupVoucherIssued) — ບໍ່ມີຝ່າຍໃດເຫັນອີກຝ່າຍ, ທັງສອງຈຶ່ງອອກ voucher ໄດ້
// ສຳເລັດເປັນອິດສະຫຼະ ໄດ້ 2 ໃບແທນ 1. ຍ້າຍ flag ໄປໄວ້ users/{customerId} ແທນ —
// ນີ້ແມ່ນ document ດຽວກັນທີ່ທັງສອງ invocation ຈະຕ້ອງອ່ານ/ຂຽນຮ່ວມກັນ, Firestore
// transaction ຈຶ່ງບັງຄັບໃຫ້ອັນໜຶ່ງຊະນະ ອີກອັນໜຶ່ງ retry ແລ້ວເຫັນ flag ເປັນ true.
async function grantSignupVoucher(referralCode, customerId, bookingId, bookingRef) {
  const codeDoc = await db.collection('referralCodes').doc(referralCode).get();
  if (!codeDoc.exists) return null;
  const ownerUid = codeDoc.data().ownerUid;
  if (ownerUid === customerId) return null; // ຫ້າມໃຊ້ໂຄ້ດຂອງຕົນເອງ

  const customerRef = db.collection('users').doc(customerId);
  const voucherRef = db.collection('wallets').doc(customerId).collection('vouchers').doc();
  return db.runTransaction(async (tx) => {
    const customerSnap = await tx.get(customerRef);
    if (customerSnap.data()?.signupVoucherIssued) return; // ✅ idempotent guard

    tx.set(voucherRef, {
      amount: REFERRAL_SIGNUP_BONUS,
      reason: 'referral_signup',
      bookingId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(customerRef, { signupVoucherIssued: true }, { merge: true });
    tx.update(bookingRef, { signupVoucherIssued: true });
  });
}

// 🔒 [AUDIT QA-1 / HI-3] ຝາກເງິນເຂົ້າ wallet ຊ່າງແບບ idempotent — ກວດ flag
// walletCredited "ໃນ" transaction ດຽວກັນກັບການຂຽນ balance/totalEarnings ແລະ
// transaction record, pattern ດຽວກັນກັບ grantRewardPoints ຂ້າງລຸ່ມ. ປ້ອງກັນ
// Cloud Functions at-least-once retry ຝາກເງິນຊ້ຳສອງເທື່ອສຳລັບ booking ດຽວ.
//
// 🔒 [AUDIT PROV-2 / 2026-08-02 — Critical, fresh re-audit] ກ່ອນໜ້ານີ້ `total`
// ຖືກເພີ່ມເຂົ້າ `balance` (ຍອດເງິນທີ່ຖອນໄດ້) ໂດຍບໍ່ສົນ paymentMethod ເລີຍ —
// ສຳລັບ booking ທີ່ paymentMethod=='cash' (ລູກຄ້າຈ່າຍເປັນເງິນສົດໃສ່ມືຊ່າງໂດຍກົງ,
// self-attested, ບໍ່ມີ payment gateway ແທ້), LinTho ບໍ່ເຄີຍໄດ້ຮັບເງິນນັ້ນເລີຍ —
// ຊ່າງຈຶ່ງໄດ້ຮັບເງິນສົດຈາກລູກຄ້າມືແລ້ວ "ແລະ" ຍັງຖອນຈຳນວນດຽວກັນນັ້ນອອກຈາກລະບົບໄດ້
// ອີກ (ຈ່າຍຊ້ຳ). ຕອນນີ້ແຍກ: `balance` (ຖອນໄດ້) ເພີ່ມສະເພາະ booking ທີ່ LinTho
// ຖືເງິນໄວ້ຈິງ (ບໍ່ແມ່ນ 'cash', ເຊັ່ນ 'bcel') — `totalEarnings` (ສະຖິຕິລາຍຮັບ
// ລວມ, ບໍ່ໄດ້ຖອນໄດ້) ຍັງເພີ່ມທຸກ booking ຄືເກົ່າ (cash ກໍ່ຖືວ່າເປັນລາຍຮັບແທ້ຂອງ
// ຊ່າງ, ພຽງແຕ່ບໍ່ຢູ່ໃນລະບົບໃຫ້ຖອນ) ເພື່ອໃຫ້ສະຖິຕິ "ລາຍຮັບລວມ" ຍັງຖືກຕ້ອງ.
// ບັນທຶກ transaction ledger ໄວ້ຄືເກົ່າສະເໝີ (ໃຫ້ຊ່າງເຫັນປະຫວັດວຽກ), ພຽງແຕ່ລະບຸ
// ໃນ description ວ່າເປັນ cash (ບໍ່ນັບເຂົ້າຍອດຖອນ) ເພື່ອບໍ່ໃຫ້ສັບສົນກັບ balance
// ທີ່ບໍ່ປ່ຽນ.
async function grantWalletCredit(providerId, bookingId, serviceLabel, total, bookingRef, paymentMethod) {
  const walletRef = db.collection('wallets').doc(providerId);
  const txnRef = db.collection('transactions').doc();
  const isWithdrawable = paymentMethod !== 'cash';
  return db.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    if (bookingSnap.data()?.walletCredited) return; // ✅ idempotent guard

    tx.set(walletRef, {
      ...(isWithdrawable ? { balance: admin.firestore.FieldValue.increment(total) } : {}),
      totalEarnings: admin.firestore.FieldValue.increment(total),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(txnRef, {
      providerId, bookingId, type: 'earning', amount: total,
      description: isWithdrawable
        ? `ລາຍຮັບ: ${serviceLabel}`
        : `ລາຍຮັບ (ເງິນສົດ, ບໍ່ນັບຍອດຖອນ): ${serviceLabel}`,
      withdrawable: isWithdrawable,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(bookingRef, { walletCredited: true });
  });
}

// 🔒 [AUDIT BE-5 / 2026-08-02 — Low, fresh re-audit] mirrors the
// walletCredited idempotency pattern above — couponUsageReverted guards
// against Cloud Functions at-least-once retry decrementing usedCount more
// than once for the same cancelled booking.
async function revertCouponUsageIfPending(couponCode, bookingId, bookingRef) {
  const couponRef = db.collection('coupons').doc(couponCode);
  return db.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    if (bookingSnap.data()?.couponUsageReverted) return; // ✅ idempotent guard
    const couponSnap = await tx.get(couponRef);
    if (!couponSnap.exists) {
      tx.update(bookingRef, { couponUsageReverted: true });
      return;
    }
    const usedCount = (couponSnap.data().usedCount || 0);
    tx.update(couponRef, { usedCount: Math.max(0, usedCount - 1) });
    tx.update(bookingRef, { couponUsageReverted: true });
  });
}

// 🔒 [AUDIT PROV-1 / 2026-07-30] ຄ່າໃຊ້ຈ່າຍເພີ່ມ (additionalCharges) ທີ່ customer
// ອະນຸມັດ *ຫຼັງ* booking ຖືກ completed ໄປແລ້ວ (status ບໍ່ປ່ຽນຢູ່ໃນ write ນັ້ນ) ບໍ່
// ເຄີຍຖືກຄິດໄລ່ເຂົ້າ wallet ຊ່າງເລີຍ — grantWalletCredit() ຖືກເອີ້ນສະເພາະຕອນ
// status ປ່ຽນເປັນ 'completed' ເທົ່ານັ້ນ (ໃຊ້ walletCredited flag ຢູ່ແລ້ວຕອນນັ້ນ),
// ອະນຸມັດຊ້າຈຶ່ງບໍ່ເຄີຍຜ່ານ block ນັ້ນອີກ. ຟັງຊັນນີ້ແມ່ນ grantWalletCredit() ຮູບ
// ດຽວກັນເປັກໆ ແຕ່ໃຊ້ flag ແຍກຕ່າງຫາກ (additionalChargesWalletCredited) — ຖ້າໃຊ້
// walletCredited ຊ້ຳ ຈະ no-op ທັນທີເພາະຄ່ານັ້ນເປັນ true ແລ້ວຈາກການຄິດໄລ່ຄັ້ງທຳອິດ.
// 🔒 [AUDIT PROV-2 / 2026-08-02] ຄ່າໃຊ້ຈ່າຍເພີ່ມບໍ່ມີຊ່ອງທາງຈ່າຍແຍກຕ່າງຫາກເລີຍ
// (ບໍ່ມີ BCEL QR/customerConfirmedPayment ຂອງຕົນເອງ, ເບິ່ງ requestAdditionalCharges()
// ໃນ booking_repository.dart) — ຖືວ່າເກັບເງິນຊ່ອງທາງດຽວກັນກັບ booking ຫຼັກ
// (paymentMethod ຂອງ booking ນັ້ນ) ຈຶ່ງໃຊ້ logic withdrawable ດຽວກັນກັບ
// grantWalletCredit() ຂ້າງເທິງ.
// 🔒 [AUDIT BE-1 / 2026-08-02 — High, fresh re-audit] `additionalChargesWalletCredited`
// ເປັນ boolean ດຽວຕໍ່ booking ຕະຫຼອດການ — ຖືກອອກແບບເປັນ idempotency guard
// ສຳລັບການ retry ຂອງ *ເຫດການອະນຸມັດອັນດຽວ* (Cloud Functions at-least-once),
// ແຕ່ຫຼັງຈາກຮອບທຳອິດຖືກ credit ໄປແລ້ວ, flag ນີ້ຄ້າງ true ຕະຫຼອດໄປ — ຖ້າຊ່າງ
// ຮ້ອງຂໍຄ່າໃຊ້ຈ່າຍເພີ່ມຮອບທີ 2 (ໃນ booking ດຽວກັນ, ຫຼັງຮອບທຳອິດຖືກອະນຸມັດ+
// ຈ່າຍໄປແລ້ວ) ແລະ ລູກຄ້າອະນຸມັດອີກ, ການຈ່າຍຮອບທີ 2 ຈະຖືກ guard ນີ້ບລັອກງຽບໆ
// (return ທັນທີ, ບໍ່ມີ error/log) — ບໍ່ມີການແຈ້ງເຕືອນ, ບໍ່ມີ transaction record,
// ຍອດເງິນຊ່າງບໍ່ກົງກັບສິ່ງທີ່ລູກຄ້າຈ່າຍ. ຕອນນີ້ໃຊ້ "round counter" ແທນ boolean
// ດຽວ — requestAdditionalCharges() (booking_repository.dart) ເພີ່ມ
// additionalChargesRound ຂຶ້ນ 1 ທຸກຄັ້ງທີ່ຮ້ອງຂໍໃໝ່, ແລະ guard ນີ້ປຽບທຽບ
// round ປັດຈຸບັນກັບ round ທີ່ credit ໄປແລ້ວຄັ້ງລ້າສຸດ — ປ້ອງກັນທັງການຈ່າຍຊ້ຳ
// (retry ຂອງ round ດຽວກັນ) ແລະ ອະນຸຍາດໃຫ້ round ຕໍ່ໆໄປຈ່າຍໄດ້ຈິງ.
async function grantAdditionalChargesWalletCredit(providerId, bookingId, serviceLabel, amount, bookingRef, paymentMethod) {
  const walletRef = db.collection('wallets').doc(providerId);
  const txnRef = db.collection('transactions').doc();
  const isWithdrawable = paymentMethod !== 'cash';
  return db.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    const data = bookingSnap.data() || {};
    // ບັນທຶກ additionalChargesRound ຫາກໍ່ຖືກເພີ່ມມາຫຼັງ fix ນີ້ — booking ເກົ່າ
    // ທີ່ຍັງບໍ່ເຄີຍມີ field ນີ້ (ຫຼືກຳລັງຢູ່ຮອບທຳອິດ) ນັບເປັນ round 1 ໂດຍ default.
    const round = data.additionalChargesRound || 1;
    if ((data.additionalChargesCreditedRound || 0) >= round) return; // ✅ idempotent guard (per-round)

    tx.set(walletRef, {
      ...(isWithdrawable ? { balance: admin.firestore.FieldValue.increment(amount) } : {}),
      totalEarnings: admin.firestore.FieldValue.increment(amount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(txnRef, {
      providerId, bookingId, type: 'earning', amount,
      description: isWithdrawable
        ? `ຄ່າໃຊ້ຈ່າຍເພີ່ມ: ${serviceLabel}`
        : `ຄ່າໃຊ້ຈ່າຍເພີ່ມ (ເງິນສົດ, ບໍ່ນັບຍອດຖອນ): ${serviceLabel}`,
      withdrawable: isWithdrawable,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(bookingRef, {
      additionalChargesWalletCredited: true,
      additionalChargesCreditedRound: round,
    });
  });
}

// ✅ [FIX C5] ກ່ອນໜ້ານີ້ການເພີ່ມ voucher ແລະ ການຕັ້ງ referralRewardIssued ເປັນ
// ການຂຽນແຍກກັນ (ບໍ່ແມ່ນ transaction ດຽວ) — ຖ້າ onBookingStatusChange ຖືກ
// trigger ຊ້ຳ (at-least-once retry) ກ່ອນທີ່ການຂຽນຄັ້ງທຳອິດຈະ commit, ທັງສອງ
// invocation ຈະອ່ານ referralRewardIssued:false ຄືກັນ ແລະ ອອກ voucher ຊ້ຳກັນ
// ສອງໃບ. ຕອນນີ້ໃຊ້ transaction ດຽວ ກວດ flag "ໃນ" transaction ກ່ອນອອກ voucher —
// pattern ດຽວກັນກັບ grantRewardPoints ຂ້າງລຸ່ມ.
async function grantReferralReward(referralCode, customerId, bookingId, bookingRef) {
  const codeDoc = await db.collection('referralCodes').doc(referralCode).get();
  if (!codeDoc.exists) return bookingRef.update({ referralRewardIssued: true });
  const ownerUid = codeDoc.data().ownerUid;
  if (ownerUid === customerId) return bookingRef.update({ referralRewardIssued: true });

  const voucherRef = db.collection('wallets').doc(ownerUid).collection('vouchers').doc();
  return db.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    if (bookingSnap.data()?.referralRewardIssued) return; // ✅ idempotent guard

    tx.set(voucherRef, {
      amount: REFERRAL_REWARD_BONUS,
      reason: 'referral_reward',
      bookingId,
      referredCustomerId: customerId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(bookingRef, { referralRewardIssued: true });
  });
}

// ─── Rewards (loyalty points) ───────────────────────────────────────────────
// earnRatePercent/minRedeemPoints/redeemRate ຕັ້ງຢູ່ settings/rewards
// (admin ປັບໄດ້ຈາກ lintho-admin/src/app/rewards/page.tsx)

async function grantRewardPoints(customerId, bookingTotal, bookingId, bookingRef) {
  const settingsDoc = await db.collection('settings').doc('rewards').get();
  const earnRatePercent = settingsDoc.data()?.earnRatePercent ?? 1;
  const points = Math.round((bookingTotal * earnRatePercent) / 100);
  const userRef = db.collection('users').doc(customerId);

  // ✅ ໃຊ້ Transaction ດຽວ ໃຫ້ການອ່ານ flag + ການຂຽນ 3 ບ່ອນ (ແຕ້ມ, log, flag)
  // ເປັນ atomic 100%. ກວດ rewardPointsIssued ຢູ່ "ໃນ" transaction (ບໍ່ແມ່ນກວດ
  // ກ່ອນຫນ້າຢູ່ caller) ເພື່ອປ້ອງກັນກໍລະນີ function ຖືກ trigger/retry ຊໍ້າພ້ອມກັນ
  // (concurrent) ແລ້ວທັງສອງຄັ້ງອ່ານ flag ເຫັນວ່າຍັງ false ກ່ອນຈະຂຽນທັງສອງ —
  // Firestore transaction ຈະບັງຄັບໃຫ້ຄັ້ງທີ່ຊ້າກວ່າ retry ດ້ວຍຂໍ້ມູນໃໝ່ສຸດ
  return db.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    if (bookingSnap.data()?.rewardPointsIssued) return; // ✅ idempotent guard

    if (points <= 0) {
      tx.update(bookingRef, { rewardPointsIssued: true });
      return;
    }

    tx.set(userRef, {
      rewardPoints: admin.firestore.FieldValue.increment(points),
    }, { merge: true });
    tx.set(db.collection('rewardTransactions').doc(), {
      userId: customerId,
      type: 'earn',
      points,
      reason: `Earned from booking ${bookingId}`,
      bookingId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(bookingRef, { rewardPointsIssued: true });
  });
}

function _randomCouponSuffix() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < 6; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

// ລູກຄ້າສ້າງ doc ນີ້ຈາກແອັບ (Flutter: rewards_provider.dart → requestRewardRedemption)
// ບໍ່ສາມາດສ້າງ coupon ຫຼື ຫັກແຕ້ມຕົນເອງໂດຍກົງ (firestore.rules ປິດໄວ້) —
// function ນີ້ກວດເງື່ອນໄຂ ແລະ ດຳເນີນການແທນແບບ atomic ດ້ວຍ Admin SDK
exports.onRewardRedemptionRequested = functions.firestore
  .document('rewardRedemptions/{reqId}')
  .onCreate(async (snap) => {
    const { userId, points } = snap.data();
    const reqRef = snap.ref;

    try {
      const settingsDoc = await db.collection('settings').doc('rewards').get();
      const minRedeemPoints = settingsDoc.data()?.minRedeemPoints ?? 100;
      const redeemRate = settingsDoc.data()?.redeemRate ?? 100;

      if (points < minRedeemPoints) {
        return reqRef.update({ status: 'failed', error: `ຕ້ອງແລກຂັ້ນຕ່ຳ ${minRedeemPoints} ແຕ້ມ` });
      }

      const userRef = db.collection('users').doc(userId);
      const code = `PTS${_randomCouponSuffix()}`;
      const couponRef = db.collection('coupons').doc(code);
      const txnRef = db.collection('rewardTransactions').doc();

      // ✅ [FIX — ຊ່ອງໂຫວ່ດຽວກັນກັບ C4/C5] ກ່ອນໜ້ານີ້ reqRef.update({status:
      // 'completed'}) ຢູ່ນອກ transaction — ຖ້າ function crash/retry ລະຫວ່າງ
      // transaction commit ແລ້ວ ແຕ່ກ່ອນ update ນີ້ຈະແລ່ນ, ຄັ້ງທີ່ສອງຈະສ້າງ coupon
      // ໃໝ່ (code random ອີກອັນ) ແລະ ຫັກແຕ້ມຊ້ຳ. ຍ້າຍທຸກຢ່າງເຂົ້າ transaction
      // ດຽວກັນ ພ້ອມ idempotent guard ຢູ່ reqRef ເອງ.
      await db.runTransaction(async (tx) => {
        const [userSnap, reqSnap] = await Promise.all([
          tx.get(userRef),
          tx.get(reqRef),
        ]);
        if (reqSnap.data()?.status === 'completed') return; // ✅ idempotent guard

        const balance = userSnap.data()?.rewardPoints || 0;
        if (balance < points) throw new Error('ແຕ້ມຄົງເຫຼືອບໍ່ພຽງພໍ');

        const now = admin.firestore.Timestamp.now();
        tx.update(userRef, { rewardPoints: admin.firestore.FieldValue.increment(-points) });
        tx.set(couponRef, {
          code, ownerId: userId, type: 'fixed', value: points * redeemRate,
          usageLimit: 1, usedCount: 0, minOrderAmount: 0, status: 'active',
          validFrom: now,
          validUntil: admin.firestore.Timestamp.fromMillis(now.toMillis() + 30 * 24 * 60 * 60 * 1000),
          createdAt: now,
        });
        tx.set(txnRef, {
          userId, type: 'redeem', points: -points,
          reason: `Redeemed for coupon ${code}`, createdAt: now,
        });
        tx.update(reqRef, { status: 'completed', couponCode: code });
      });

      return null;
    } catch (err) {
      return reqRef.update({ status: 'failed', error: err.message });
    }
  });

// ─── Withdrawals ─────────────────────────────────────────────────────────
// ✅ [AUDIT C4] ລູກຄ້າ(provider) ສ້າງ doc ນີ້ຈາກແອັບ (Flutter:
// booking_repository.dart → EarningsRepository.requestWithdrawal) ດ້ວຍ
// status:'pending' ໂດຍບໍ່ຫັກ balance ເອງ (firestore.rules ປິດການແກ້ໄຂ
// wallets.balance ໂດຍກົງແລ້ວ). function ນີ້ກວດ + ຫັກຍອດເງິນແບບ atomic
// ພາຍໃນ transaction ດຽວ ຄືກັນກັບ onRewardRedemptionRequested ຂ້າງເທິງ —
// ຖ້າມີ 2 ຄຳຂໍພ້ອມກັນ (ຕົວຢ່າງ: double-tap ຫຼືສອງອຸປະກອນພ້ອມກັນ), Firestore
// transaction ຈະບັງຄັບໃຫ້ຄັ້ງທີ່ສອງອ່ານຍອດເງິນທີ່ຖືກຫັກໄປແລ້ວຈາກຄັ້ງທຳອິດ ແລະ
// ຈະຖືກປະຕິເສດ (status:'failed') ຖ້າຍອດບໍ່ພຽງພໍ — ບໍ່ໃຫ້ຍອດເງິນຕິດລົບໄດ້.
//
// ✅ status ບໍ່ຖືກປ່ຽນເປັນຄ່າໃໝ່ (ຍັງເປັນ 'pending') ເພື່ອບໍ່ໃຫ້ກະທົບ vocabulary
// ທີ່ LinTho Admin Panel ອາດອີງໃສ່ໃນການກັ່ນຕອງ — ເພີ່ມແຕ່ field
// balanceReserved ບອກວ່າຍອດເງິນຖືກກັນໄວ້ແລ້ວ, admin ຍັງໂອນເງິນຈິງ ແລະ
// ປິດເປັນ completed ເອງຕາມຂະບວນການເດີມ.
exports.onWithdrawalRequested = functions.firestore
  .document('withdrawalRequests/{reqId}')
  .onCreate(async (snap) => {
    const { providerId, amount } = snap.data();
    const reqRef = snap.ref;
    const MIN_WITHDRAWAL = 50000;

    if (typeof amount !== 'number' || amount < MIN_WITHDRAWAL) {
      return reqRef.update({
        status: 'failed',
        error: `ຂັ້ນຕ່ຳ ₭${MIN_WITHDRAWAL}`,
      });
    }
    if (!providerId) {
      return reqRef.update({ status: 'failed', error: 'ບໍ່ພົບ providerId' });
    }

    const walletRef = db.collection('wallets').doc(providerId);

    // ✅ [FIX C4] Cloud Functions ເປັນ "at-least-once" delivery — event ດຽວກັນ
    // ອາດຖືກ trigger ຊ້ຳ (retry ຫຼັງ timeout/infra hiccup). ກ່ອນໜ້ານີ້ transaction
    // ອ່ານ balance ແລ້ວຫັກ -amount ໂດຍບໍ່ກວດວ່າ reqRef ນີ້ຖືກຫັກໄປແລ້ວ ຫຼືບໍ່ —
    // ຖ້າ trigger ຊ້ຳ, ຄັ້ງທີສອງຈະອ່ານ balance ໃໝ່ (ຫັກໄປແລ້ວຄັ້ງທຳອິດ) ແລ້ວຫັກຊ້ຳ
    // ອີກຄັ້ງ = ຫັກ 2 ເທົ່າຈາກ request ດຽວ. ຕອນນີ້ກວດ balanceReserved ຢູ່ "ໃນ"
    // transaction ດຽວກັນກັບການອ່ານ/ຂຽນ (idempotent guard, pattern ດຽວກັນກັບ
    // grantRewardPoints/grantReferralReward ຂ້າງລຸ່ມ).
    try {
      await db.runTransaction(async (tx) => {
        const [walletSnap, reqSnap] = await Promise.all([
          tx.get(walletRef),
          tx.get(reqRef),
        ]);
        if (reqSnap.data()?.balanceReserved) return; // ✅ idempotent guard

        const balance = walletSnap.data()?.balance || 0;
        if (balance < amount) throw new Error('ຍອດເງິນບໍ່ພຽງພໍ');

        tx.update(walletRef, {
          balance: admin.firestore.FieldValue.increment(-amount),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.update(reqRef, {
          balanceReserved: true,
          reservedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (err) {
      return reqRef.update({ status: 'failed', error: err.message });
    }
  });

// ─── Admin User Management ─────────────────────────────────────────────────
// Callable functions backing the LinTho Admin "Admin Users" page. The admin
// panel (lintho-admin) is a plain client-side app — it cannot safely create,
// disable, or delete another user's Firebase Auth account with the client
// SDK (that would require being signed in as them). Only the Admin SDK can
// do that, so this runs server-side, and re-checks the caller's own role
// against Firestore itself rather than trusting anything the client sends —
// a callable function is a fresh entry point with no session tied to
// lintho-admin's client-side RequireRole check, which is UX, not security.

const ADMIN_ROLE_VALUES = [
  'super_admin', 'operations_admin', 'finance_admin', 'support_admin', 'marketing_admin',
];

// ✅ ສະເພາະ super_admin ເທົ່ານັ້ນທີ່ຈັດການບັນຊີ admin ຄົນອື່ນໄດ້ (ກົງກັບ
// ROLE_PERMISSIONS.super_admin ຝັ່ງ lintho-admin ທີ່ເປັນ tier ດຽວທີ່ມີ
// admin_users:write). ອ່ານ adminRole ຈາກ Firestore ໂດຍກົງ ບໍ່ເຊື່ອຄ່າຈາກ
// client — ບັນຊີເກົ່າທີ່ຍັງບໍ່ມີ field adminRole (ມີແຕ່ role:'admin' ແບບ flat,
// ຄືຄ່າດຽວທີ່ isAdmin()/admin bypass rule ໃນ firestore.rules ຮູ້ຈັກ) ຖືວ່າ
// ເປັນ super_admin ເໝືອນ resolveAdminRole() ຝັ່ງ lintho-admin
// (src/lib/api/realAuth.ts) ເພື່ອບໍ່ໃຫ້ admin ທີ່ມີຢູ່ແລ້ວຖືກລ໋ອກອອກ.
async function _assertSuperAdmin(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'ຕ້ອງເຂົ້າສູ່ລະບົບກ່ອນ.');
  }
  const callerSnap = await db.collection('users').doc(context.auth.uid).get();
  const callerData = callerSnap.data() || {};
  if (callerData.role !== 'admin') {
    throw new functions.https.HttpsError('permission-denied', 'ບັນຊີນີ້ບໍ່ແມ່ນ admin.');
  }
  const adminRole = callerData.adminRole || 'super_admin';
  if (adminRole !== 'super_admin') {
    throw new functions.https.HttpsError('permission-denied', 'ສະເພາະ Super Admin ເທົ່ານັ້ນທີ່ຈັດການບັນຊີ admin ຄົນອື່ນໄດ້.');
  }
  return context.auth.uid;
}

exports.createAdminUser = functions.https.onCall(async (data, context) => {
  const callerUid = await _assertSuperAdmin(context);

  const { email, password, name, adminRole } = data || {};
  if (typeof email !== 'string' || !email.includes('@')) {
    throw new functions.https.HttpsError('invalid-argument', 'Email ບໍ່ຖືກຕ້ອງ.');
  }
  if (typeof password !== 'string' || password.length < 8) {
    throw new functions.https.HttpsError('invalid-argument', 'ລະຫັດຜ່ານຕ້ອງມີຢ່າງໜ້ອຍ 8 ໂຕອັກສອນ.');
  }
  if (typeof name !== 'string' || !name.trim()) {
    throw new functions.https.HttpsError('invalid-argument', 'ກະລຸນາໃສ່ຊື່.');
  }
  if (!ADMIN_ROLE_VALUES.includes(adminRole)) {
    throw new functions.https.HttpsError('invalid-argument', 'Role ບໍ່ຖືກຕ້ອງ.');
  }

  let userRecord;
  try {
    userRecord = await admin.auth().createUser({ email, password, displayName: name });
  } catch (err) {
    const code = err.code === 'auth/email-already-exists' ? 'already-exists'
      : (err.code === 'auth/invalid-email' || err.code === 'auth/invalid-password') ? 'invalid-argument'
      : 'internal';
    throw new functions.https.HttpsError(code, err.message);
  }

  try {
    // role ຕ້ອງເປັນ 'admin' ແບບ flat ເພື່ອກົງກັບ isAdmin()/admin bypass rule
    // (firestore.rules ~line 24-25, 58-60) — adminRole ຄືຄ່າ tier ລະອຽດທີ່
    // ຝັ່ງ client (lintho-admin) ອ່ານໄປໃຊ້ ບໍ່ໄດ້ມີຄວາມໝາຍຫຍັງຕໍ່ rules ເລີຍ.
    await db.collection('users').doc(userRecord.uid).set({
      name,
      email,
      role: 'admin',
      adminRole,
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: callerUid,
    });
  } catch (err) {
    // ✅ ບໍ່ໃຫ້ຄ້າງບັນຊີ Auth ທີ່ບໍ່ມີ Firestore doc ຄູ່ກັນ (ຈະ login ໄດ້ແຕ່
    // realAuth.ts ຫາ role ບໍ່ພົບ ແລະ ປະຕິເສດ — ບັນຊີເປົ່າທີ່ບໍ່ມີປະໂຫຍດ) —
    // ລຶບ Auth user ຄືນຖ້າ Firestore write ລົ້ມເຫຼວ.
    await admin.auth().deleteUser(userRecord.uid).catch(() => {});
    throw new functions.https.HttpsError('internal', 'ສ້າງບັນຊີ Auth ສຳເລັດແຕ່ບັນທຶກ Firestore ລົ້ມເຫຼວ: ' + err.message);
  }

  return { uid: userRecord.uid };
});

exports.setAdminUserActive = functions.https.onCall(async (data, context) => {
  const callerUid = await _assertSuperAdmin(context);
  const { uid, isActive } = data || {};
  if (typeof uid !== 'string' || !uid) {
    throw new functions.https.HttpsError('invalid-argument', 'ບໍ່ພົບ uid.');
  }
  if (typeof isActive !== 'boolean') {
    throw new functions.https.HttpsError('invalid-argument', 'isActive ຕ້ອງເປັນ true/false.');
  }
  if (uid === callerUid && !isActive) {
    throw new functions.https.HttpsError('failed-precondition', 'ບໍ່ສາມາດປິດການໃຊ້ງານບັນຊີຕົນເອງໄດ້.');
  }

  await admin.auth().updateUser(uid, { disabled: !isActive });
  await db.collection('users').doc(uid).update({
    isActive,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { uid, isActive };
});

exports.deleteAdminUser = functions.https.onCall(async (data, context) => {
  const callerUid = await _assertSuperAdmin(context);
  const { uid } = data || {};
  if (typeof uid !== 'string' || !uid) {
    throw new functions.https.HttpsError('invalid-argument', 'ບໍ່ພົບ uid.');
  }
  if (uid === callerUid) {
    throw new functions.https.HttpsError('failed-precondition', 'ບໍ່ສາມາດລຶບບັນຊີຕົນເອງໄດ້.');
  }

  await admin.auth().deleteUser(uid);
  await db.collection('users').doc(uid).delete();

  return { uid };
});

// 🔒 [FOLLOWUP-I4] "ລຶບບັນຊີຜູ້ໃຊ້" ໃນ Profile ເຄີຍພຽງແຕ່ Navigator.pop —
// ບໍ່ມີການລຶບຫຍັງເລີຍ, ຜູ້ໃຊ້ຄິດວ່າບັນຊີຖືກລຶບແລ້ວທັງໆທີ່ຍັງຢູ່ຄົບ. ຄັດລອກ pattern
// ດຽວກັນກັບ deleteAdminUser() ຂ້າງເທິງ ແຕ່ອະນຸຍາດໃຫ້ user ລຶບບັນຊີຕົນເອງເທົ່ານັ້ນ
// (ບໍ່ຕ້ອງການ admin role). ຂອບເຂດ: ລຶບ Auth user + users/{uid} + ຍ່ອຍ
// addresses — ບໍ່ໄດ້ລຶບ providers/{uid}/wallets/bookings history (ອອກນອກ
// scope ຂອງ bug fix ນີ້, ຕ້ອງການການອອກແບບແຍກຕ່າງຫາກສຳລັບຂໍ້ມູນທຸລະກຳ).
exports.deleteOwnAccount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'ຕ້ອງເຂົ້າສູ່ລະບົບກ່ອນ.');
  }
  const uid = context.auth.uid;

  const addressesSnap = await db.collection('users').doc(uid).collection('addresses').get();
  const batch = db.batch();
  addressesSnap.forEach((doc) => batch.delete(doc.ref));
  batch.delete(db.collection('users').doc(uid));
  await batch.commit();

  await admin.auth().deleteUser(uid);

  return { uid };
});

// ════════════════════════════════════════════════════════════
// CLOUDINARY — signed upload
// ════════════════════════════════════════════════════════════
// 🔒 [Security fix] ເມື່ອກ່ອນ client ອັບໂຫລດຮູບ (ລວມທັງ KYC — ບັດປະຊາຊົນ +
// ເຊວຟີ) ຂຶ້ນ Cloudinary ໂດຍກົງດ້ວຍ "unsigned upload preset" — cloud name
// ແລະ preset name hardcode ຢູ່ໃນ app (ດຶງອອກຈາກ APK ໄດ້ງ່າຍໆ). ໃຜກໍອັບໂຫລດ
// ເຂົ້າ account ນີ້ໄດ້ໂດຍກົງ ໂດຍບໍ່ຕ້ອງຜ່ານ auth ຂອງ LinTho ເລີຍ. ຕອນນີ້
// client ຕ້ອງຂໍ signature ຈາກ Cloud Function ນີ້ກ່ອນ (ຕ້ອງ login ແລ້ວເທົ່ານັ້ນ,
// ແລະ folder ຖືກຈຳກັດໃຫ້ຢູ່ພາຍໃຕ້ uid/booking ຂອງຕົນເອງເທົ່ານັ້ນ).

function _isOwnCloudinaryFolder(uid, folder) {
  return folder === `profiles/customers/${uid}` ||
      folder === `profiles/providers/${uid}` ||
      folder === `kyc/${uid}/id` ||
      folder === `kyc/${uid}/selfie`;
}

const _JOB_PHOTO_FOLDER_RE = /^bookings\/jobPhotos\/([A-Za-z0-9_-]{1,100})$/;
// 🔒 [FOLLOWUP-B] ຮູບກ່ອນ/ຫຼັງວຽກ (uploadJobPhoto() ໃນ lib/cloudinary_service.dart)
// ສົ່ງ folder ຮູບແບບ `jobs/$bookingId/before` ຫຼື `/after` — ບໍ່ກົງກັບ regex
// ຂ້າງເທິງ (ຮູບແບບ KYC-photo). ກ່ອນໜ້ານີ້ບໍ່ມີ regex ຮອງຮັບ folder ນີ້ເລີຍ,
// ທຸກ upload ຮູບກ່ອນ/ຫຼັງວຽກຈຶ່ງຖືກປະຕິເສດ permission-denied ຕະຫຼອດ.
const _JOB_PHOTO_BEFORE_AFTER_RE =
  /^jobs\/([A-Za-z0-9_-]{1,100})\/(before|after)$/;

exports.getCloudinarySignature = functions
  .runWith({ secrets: [CLOUDINARY_API_SECRET, CLOUDINARY_API_KEY] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'ຕ້ອງເຂົ້າສູ່ລະບົບກ່ອນ.');
    }
    const uid = context.auth.uid;
    const folder = (data && data.folder) || '';
    if (typeof folder !== 'string' || !folder) {
      throw new functions.https.HttpsError('invalid-argument', 'ບໍ່ພົບ folder.');
    }

    const jobPhotoMatch = folder.match(_JOB_PHOTO_FOLDER_RE) ||
      folder.match(_JOB_PHOTO_BEFORE_AFTER_RE);
    if (_isOwnCloudinaryFolder(uid, folder)) {
      // ✅ profile photo / KYC — ຢູ່ໃຕ້ uid ຂອງຕົນເອງເທົ່ານັ້ນ, ຜ່ານ
    } else if (jobPhotoMatch) {
      // ✅ job before/after photo — ຖ້າ booking ນີ້ຖືກສ້າງໄວ້ແລ້ວ (doc ມີ)
      // ຕ້ອງເປັນ customer ຫຼື provider ຂອງ booking ນັ້ນແທ້; ຖ້າຍັງບໍ່ມີ doc
      // (client generate clientRequestId ເອງກ່ອນ Firestore write) ອະນຸຍາດຜ່ານ
      const bookingSnap = await db.collection('bookings').doc(jobPhotoMatch[1]).get();
      if (bookingSnap.exists) {
        const b = bookingSnap.data() || {};
        if (b.customerId !== uid && b.providerId !== uid) {
          throw new functions.https.HttpsError('permission-denied', 'ບໍ່ແມ່ນເຈົ້າຂອງ booking ນີ້.');
        }
      }
    } else {
      throw new functions.https.HttpsError('permission-denied', 'Folder ບໍ່ຖືກອະນຸຍາດ.');
    }

    const timestamp = Math.floor(Date.now() / 1000);
    const toSign = `folder=${folder}&timestamp=${timestamp}`;
    const signature = crypto
      .createHash('sha1')
      .update(toSign + CLOUDINARY_API_SECRET.value())
      .digest('hex');

    return {
      signature,
      timestamp,
      apiKey: CLOUDINARY_API_KEY.value(),
      cloudName: CLOUDINARY_CLOUD_NAME,
      folder,
    };
  });

// ════════════════════════════════════════════════════════════
// SIGNED MEDIA URL — short-lived read access to sensitive Storage files
// ════════════════════════════════════════════════════════════
// 🔒 [AUDIT SEC-2 / 2026-08-06] uploadKyc()/uploadTopupSlip()
// (lib/booking_repository.dart) persist a Firebase Storage getDownloadURL()
// into Firestore (kyc/{uid}.idDocUrl/selfieUrl, topupRequests/{id}.slipUrl)
// — that URL embeds a permanent bearer token that grants read access to
// anyone who ever obtains it (browser history, logs, a shared screenshot),
// independent of storage.rules and independent of the requester's auth
// state, for as long as the file exists. This function lets the admin panel
// fetch a short-lived (5 min) signed URL on demand instead — the caller
// must be a signed-in admin, and the path must be scoped to kyc/ or
// topupRequests/ (no arbitrary Storage path can be read through this).
// Requires the corresponding Firestore doc to also carry a *storage path*
// field (idDocPath/selfiePath/slipPath, added alongside the existing URL
// fields in lib/booking_repository.dart) — records uploaded before this
// fix has no path field and the admin panel falls back to the old URL for
// those, so this is additive/backward-compatible, not a breaking migration.
const _SIGNED_MEDIA_PATH_RE = /^(kyc|topupRequests)\/[A-Za-z0-9_-]{1,128}\/[A-Za-z0-9_.-]{1,128}$/;

exports.getSignedMediaUrl = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'ຕ້ອງເຂົ້າສູ່ລະບົບກ່ອນ.');
  }
  const callerSnap = await db.collection('users').doc(context.auth.uid).get();
  if ((callerSnap.data() || {}).role !== 'admin') {
    throw new functions.https.HttpsError('permission-denied', 'ສະເພາະ admin ເທົ່ານັ້ນ.');
  }

  const path = (data && data.path) || '';
  if (typeof path !== 'string' || !_SIGNED_MEDIA_PATH_RE.test(path)) {
    throw new functions.https.HttpsError('invalid-argument', 'Path ບໍ່ຖືກຕ້ອງ.');
  }

  const [url] = await admin.storage().bucket().file(path).getSignedUrl({
    action: 'read',
    expires: Date.now() + 5 * 60 * 1000,
  });
  return { url };
});