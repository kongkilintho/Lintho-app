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

exports.processFCMQueue = functions.firestore
  .document('fcm_queue/{docId}')
  .onCreate(async (snap) => {
    const data = snap.data();
    if (!data || data.sent) return null;
    const { targetUserId, targetRole, title, body } = data;
    const msgData = data.data || {};
    try {
      const col = targetRole === 'provider' ? 'providers' : 'users';
      const userDoc = await db.collection(col).doc(targetUserId).get();
      if (!userDoc.exists) return snap.ref.update({ sent: true });
      const tokens = userDoc.data().fcmTokens || [];
      if (tokens.length === 0) return snap.ref.update({ sent: true });
      const result = await messaging.sendEachForMulticast({
        notification: { title, body },
        data: msgData,
        android: { priority: 'high', notification: { sound: 'default', channelId: _getChannelId(data.type) } },
        apns: { payload: { aps: { sound: 'default', badge: 1 } } },
        tokens,
      });
      return snap.ref.update({ sent: true, successCount: result.successCount });
    } catch (err) {
      return snap.ref.update({ sent: true, error: err.message });
    }
  });

exports.onBookingStatusChange = functions.firestore
  .document('bookings/{bookingId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const bookingId = context.params.bookingId;
    if (before.status === after.status) return null;
    const { customerId, providerId, serviceType, category, price, additionalCharges, additionalChargesApproved } = after;
    // ✅ [FIX HI-4] serviceType ອາດຂາດຢູ່ໃນ booking ເກົ່າ (ຫຼືກໍລະນີບໍ່ຄາດຄິດ) —
    // fallback ໄປ category ເພື່ອບໍ່ໃຫ້ notification ສະແດງ "undefined"
    const svcLabel = serviceType || category || 'ບໍລິການ';
    const providerDoc = await db.collection('providers').doc(providerId).get();
    const providerName = providerDoc.data()?.displayName || 'ຊ່າງ';
    const queue = [];
    const notify = (targetUserId, targetRole, title, body, type) => {
      queue.push(db.collection('fcm_queue').add({
        targetUserId, targetRole, type, bookingId,
        title, body, data: { type, bookingId },
        createdAt: admin.firestore.FieldValue.serverTimestamp(), sent: false,
      }));
    };
    if (after.status === 'accepted') notify(customerId, 'customer', '✅ ຊ່າງຮັບງານແລ້ວ!', `${providerName} ກຳລັງກຽມໄປ`, 'booking_update');
    if (after.status === 'onTheWay') notify(customerId, 'customer', '🚗 ຊ່າງກຳລັງໄປ!', `${providerName} ກຳລັງເດີນທາງ`, 'booking_update');
    if (after.status === 'arrived') notify(customerId, 'customer', '📍 ຊ່າງຮອດແລ້ວ!', `${providerName} ຢູ່ໜ້ານາງ`, 'booking_update');
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
        queue.push(grantWalletCredit(providerId, bookingId, svcLabel, total, change.after.ref));

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
      // 🔒 [AUDIT QA-1 / LO-6] providerId ອາດວ່າງເປົ່າ (booking ຍັງບໍ່ເຄີຍຖືກຮັບ
      // ເລີຍ ຕອນລູກຄ້າຍົກເລີກ) — notify() ຂຽນ fcm_queue doc ໄດ້ປົກກະຕິແມ້
      // targetUserId ວ່າງ, ແຕ່ບໍ່ຄວນ notify provider ທີ່ບໍ່ມີໂຕຕົນຈິງ
      if (providerId) notify(providerId, 'provider', '❌ ຍົກເລີກ', `${svcLabel} ຖືກຍົກເລີກ`, 'booking_update');
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
    const batch = db.batch();
    const notifications = [];
    snap.docs.forEach((doc) => {
      batch.update(doc.ref, {
        status: 'cancelled',
        cancelReason: 'expired_no_provider',
        cancelledBy: 'system',
      });
      const { customerId, serviceType, category } = doc.data();
      if (customerId) {
        notifications.push(db.collection('fcm_queue').add({
          targetUserId: customerId, targetRole: 'customer',
          type: 'booking_update', bookingId: doc.id,
          title: '⏰ ບໍ່ມີຊ່າງຮັບງານ',
          body: `${serviceType || category || 'ການຈອງ'} ຖືກຍົກເລີກ · ບໍ່ມີຊ່າງຮັບໃນເວລາ`,
          data: { type: 'booking_update', bookingId: doc.id },
          createdAt: admin.firestore.FieldValue.serverTimestamp(), sent: false,
        }));
      }
    });
    await batch.commit();
    return Promise.all(notifications);
  });

exports.onNewBooking = functions.firestore
  .document('bookings/{bookingId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const bookingId = context.params.bookingId;
    if (!data) return null;
    const { providerId, customerId, serviceType, category, referralCode } = data;
    const svcLabel = serviceType || category || 'ບໍລິການ';
    const customerDoc = await db.collection('users').doc(customerId).get();
    const customerName = customerDoc.data()?.displayName || 'ລູກຄ້າ';
    const queue = [db.collection('fcm_queue').add({
      targetUserId: providerId, targetRole: 'provider',
      type: 'new_booking', bookingId,
      title: '🔔 ງານໃໝ່!', body: `${customerName} ຕ້ອງການ ${svcLabel}`,
      data: { type: 'new_booking', bookingId },
      createdAt: admin.firestore.FieldValue.serverTimestamp(), sent: false,
    })];

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
async function grantSignupVoucher(referralCode, customerId, bookingId, bookingRef) {
  const codeDoc = await db.collection('referralCodes').doc(referralCode).get();
  if (!codeDoc.exists) return null;
  const ownerUid = codeDoc.data().ownerUid;
  if (ownerUid === customerId) return null; // ຫ້າມໃຊ້ໂຄ້ດຂອງຕົນເອງ

  const voucherRef = db.collection('wallets').doc(customerId).collection('vouchers').doc();
  return db.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    if (bookingSnap.data()?.signupVoucherIssued) return; // ✅ idempotent guard

    tx.set(voucherRef, {
      amount: REFERRAL_SIGNUP_BONUS,
      reason: 'referral_signup',
      bookingId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(bookingRef, { signupVoucherIssued: true });
  });
}

// 🔒 [AUDIT QA-1 / HI-3] ຝາກເງິນເຂົ້າ wallet ຊ່າງແບບ idempotent — ກວດ flag
// walletCredited "ໃນ" transaction ດຽວກັນກັບການຂຽນ balance/totalEarnings ແລະ
// transaction record, pattern ດຽວກັນກັບ grantRewardPoints ຂ້າງລຸ່ມ. ປ້ອງກັນ
// Cloud Functions at-least-once retry ຝາກເງິນຊ້ຳສອງເທື່ອສຳລັບ booking ດຽວ.
async function grantWalletCredit(providerId, bookingId, serviceLabel, total, bookingRef) {
  const walletRef = db.collection('wallets').doc(providerId);
  const txnRef = db.collection('transactions').doc();
  return db.runTransaction(async (tx) => {
    const bookingSnap = await tx.get(bookingRef);
    if (bookingSnap.data()?.walletCredited) return; // ✅ idempotent guard

    tx.set(walletRef, {
      balance: admin.firestore.FieldValue.increment(total),
      totalEarnings: admin.firestore.FieldValue.increment(total),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(txnRef, {
      providerId, bookingId, type: 'earning', amount: total,
      description: `ລາຍຮັບ: ${serviceLabel}`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(bookingRef, { walletCredited: true });
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