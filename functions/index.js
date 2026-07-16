const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

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
    const { customerId, providerId, serviceType, price, additionalCharges, additionalChargesApproved } = after;
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
      const total = (price || 0) + (additionalChargesApproved ? (additionalCharges || 0) : 0);
      notify(customerId, 'customer', '🎉 ວຽກສຳເລັດ!', `${serviceType} ສຳເລັດ · ກະລຸນາໃຫ້ຄະແນນ`, 'booking_update');
      notify(providerId, 'provider', '💰 ລາຍຮັບເຂົ້າ!', `₭${total} ຈາກ ${serviceType}`, 'payment');
      queue.push(db.collection('wallets').doc(providerId).set({
        balance: admin.firestore.FieldValue.increment(total),
        totalEarnings: admin.firestore.FieldValue.increment(total),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true }));
      queue.push(db.collection('transactions').add({
        providerId, bookingId, type: 'earning', amount: total,
        description: `ລາຍຮັບ: ${serviceType}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }));

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
    if (after.status === 'rejected') notify(customerId, 'customer', '❌ ຖືກປະຕິເສດ', `${serviceType} ຖືກປະຕິເສດ`, 'booking_update');
    if (after.status === 'cancelled') notify(providerId, 'provider', '❌ ຍົກເລີກ', `${serviceType} ຖືກຍົກເລີກ`, 'booking_update');
    return Promise.all(queue);
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
      const { customerId, serviceType } = doc.data();
      if (customerId) {
        notifications.push(db.collection('fcm_queue').add({
          targetUserId: customerId, targetRole: 'customer',
          type: 'booking_update', bookingId: doc.id,
          title: '⏰ ບໍ່ມີຊ່າງຮັບງານ',
          body: `${serviceType || 'ການຈອງ'} ຖືກຍົກເລີກ · ບໍ່ມີຊ່າງຮັບໃນເວລາ`,
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
    const { providerId, customerId, serviceType, referralCode } = data;
    const customerDoc = await db.collection('users').doc(customerId).get();
    const customerName = customerDoc.data()?.displayName || 'ລູກຄ້າ';
    const queue = [db.collection('fcm_queue').add({
      targetUserId: providerId, targetRole: 'provider',
      type: 'new_booking', bookingId,
      title: '🔔 ງານໃໝ່!', body: `${customerName} ຕ້ອງການ ${serviceType}`,
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
        queue.push(grantSignupVoucher(referralCode, customerId, bookingId));
      }
    }

    return Promise.all(queue);
  });

const REFERRAL_SIGNUP_BONUS = 20000;
const REFERRAL_REWARD_BONUS = 20000;

async function grantSignupVoucher(referralCode, customerId, bookingId) {
  const codeDoc = await db.collection('referralCodes').doc(referralCode).get();
  if (!codeDoc.exists) return null;
  const ownerUid = codeDoc.data().ownerUid;
  if (ownerUid === customerId) return null; // ຫ້າມໃຊ້ໂຄ້ດຂອງຕົນເອງ
  return db.collection('wallets').doc(customerId).collection('vouchers').add({
    amount: REFERRAL_SIGNUP_BONUS,
    reason: 'referral_signup',
    bookingId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
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