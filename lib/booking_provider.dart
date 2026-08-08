// ============================================================
// booking_provider.dart — LinTho Provider App
// Riverpod State Management
//
// Fixes:
//   ✅ BookingNotifier: AsyncValue<void> → BookingState
//      ເພື່ອ track loadingIds per booking (ບໍ່ disable ທຸກ card)
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'Booking.dart';
import 'booking_repository.dart';

// ── REPOSITORIES ─────────────────────────────────────────────

final bookingRepoProvider  = Provider((_) => BookingRepository());
final earningsRepoProvider = Provider((_) => EarningsRepository());
final profileRepoProvider  = Provider((_) => ProfileRepository());
final customerBookingRepoProvider =
    Provider((_) => CustomerBookingRepository());

// 🔒 [FIX account-switch] StreamProvider ຂ້າງລຸ່ມນີ້ (ບໍ່ໄດ້ໃຊ້ .autoDispose)
// ສ້າງ query ຄັ້ງດຽວແລ້ວ cache ໄວ້ຕະຫຼອດອາຍຸແອັບ (ProviderScope ຢູ່ main.dart
// ຄົງຢູ່ຕະຫຼອດ process, ບໍ່ recreate ຕອນ login/logout) — _uid ຖືກອ່ານຕອນ
// stream ຖືກສ້າງເທື່ອທຳອິດເທົ່ານັ້ນ. ຖ້າສະຫຼັບບັນຊີ (ເຊັ່ນ logout ແລ້ວ Google
// sign-in ບັນຊີອື່ນ) ໂດຍບໍ່ restart ແອັບ, stream ເກົ່າຍັງຄ້າງ query ຫາ uid ເກົ່າ —
// ໜ້າ jobs/earnings ຈຶ່ງບໍ່ຂຶ້ນຂໍ້ມູນຈົນກວ່າຈະ pull-to-refresh (invalidate
// ໂດຍບັງເອີນ). watch currentUidProvider ໃນທຸກ provider ຂ້າງລຸ່ມ ບັງຄັບໃຫ້ມັນ
// rebuild ດ້ວຍ uid ໃໝ່ທັນທີທີ່ auth state ປ່ຽນ.
final currentUidProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((u) => u?.uid);
});

// ── BOOKING STREAMS ──────────────────────────────────────────

final activeBookingsProvider = StreamProvider<List<Booking>>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(bookingRepoProvider).watchActiveBookings();
});

final jobHistoryProvider = StreamProvider<List<Booking>>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(bookingRepoProvider).watchJobHistory();
});

final pendingJobsProvider = Provider<List<Booking>>((ref) {
  return ref.watch(activeBookingsProvider).whenOrNull(
    data: (list) => list
        .where((b) => b.status == JobStatus.pending && !b.isExpired)
        .toList(),
  ) ??
      [];
});

// 🔒 [AUDIT BE-1 / 2026-07-30] watchOpenJobs() ຖືກແທນທີ່ດ້ວຍ 2 query ທີ່ພິສູດໄດ້
// ແຍກກັນ (ເບິ່ງ booking_repository.dart) — ລວມທັງສອງເຂົ້າກັນຢູ່ນີ້ດ້ວຍ pattern
// Riverpod ທຳມະດາ (watch 2 StreamProvider, merge ໃນ Provider ທຳມະດາ) ແທນທີ່ຈະ
// hand-roll StreamController — Riverpod ຈັດການ subscription lifecycle ແລະ error
// propagation ໃຫ້ເອງ. openJobsProvider ຍັງເປັນ AsyncValue<List<Booking>> ຄືເກົ່າ
// (Provider<AsyncValue<T>> ໃຫ້ interface ດຽວກັນກັບ StreamProvider ຕອນ watch) —
// unassignedOpenJobsProvider ຂ້າງລຸ່ມ ແລະ home_tab.dart ຈຶ່ງບໍ່ຕ້ອງແກ້ໄຂຫຍັງເລີຍ.
final _openJobsPublicProvider = StreamProvider<List<Booking>>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(bookingRepoProvider).watchOpenJobsPublic();
});

final _openJobsSentToMeProvider = StreamProvider<List<Booking>>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(bookingRepoProvider).watchOpenJobsSentToMe();
});

final openJobsProvider = Provider<AsyncValue<List<Booking>>>((ref) {
  final a = ref.watch(_openJobsPublicProvider);
  final b = ref.watch(_openJobsSentToMeProvider);
  if (a.hasError) {
    debugPrint('openJobsProvider (public): ${a.error}');
    return AsyncValue.error(a.error!, a.stackTrace ?? StackTrace.current);
  }
  if (b.hasError) {
    debugPrint('openJobsProvider (sentToMe): ${b.error}');
    return AsyncValue.error(b.error!, b.stackTrace ?? StackTrace.current);
  }
  if (!a.hasValue || !b.hasValue) return const AsyncValue.loading();
  final seen = <String>{};
  final merged = <Booking>[];
  for (final booking in [...a.value!, ...b.value!]) {
    if (seen.add(booking.id)) merged.add(booking);
  }
  merged.sort((x, y) => y.createdAt.compareTo(x.createdAt));
  return AsyncValue.data(merged);
});

// ✅ [FIX-3] ວຽກ pending ທີ່ providerId ຍັງວ່າງເປົ່າ (ບໍ່ຖືກມອບໝາຍໃຫ້ໃຜ) —
// ກອງໃຫ້ເຫຼືອສະເພາະປະເພດວຽກທີ່ provider ນີ້ຮັບໄດ້ (serviceTypes ຫວ່າງ
// = ຮັບໄດ້ທຸກປະເພດ, ບໍ່ຮູ້ຈັກ profile ຍັງ)
// 🔒 [AUDIT QA-1 / HI-5] ກ່ອນໜ້ານີ້ກອງດ້ວຍ b.serviceType — ແຕ່ Quick Booking
// ຂຽນ label ພາສາລາວ (display text) ໃສ່ field ນີ້, ບໍ່ແມ່ນ canonical key
// (ຕ່າງຈາກ provider.serviceTypes ທີ່ເປັນ key ສະເໝີ ເຊັ່ນ 'ac_clean') — ເຮັດໃຫ້
// contains() ບໍ່ເຄີຍກົງກັນ ແລະ ວຽກຈາກ Quick Booking ຫາຍໄປຈາກຄິວຂອງ provider
// ທີ່ຕັ້ງກອງ serviceTypes ໄວ້. ໃຊ້ b.category (canonical key ສະເໝີ, ທັງສອງ flow
// ຂຽນຄ່າດຽວກັນ) ແທນ.
//
// 🔒 [FOLLOWUP-H] ດຶງ predicate ອອກມາເປັນ top-level pure function ໃຫ້ unit
// test ໄດ້ໂດຍກົງ (ບໍ່ຈຳເປັນຕ້ອງ mock Riverpod/FirebaseAuth) — ຍັງເພີ່ມການກອງ
// sentTo ໃໝ່: match_screen.dart ຂຽນ sentTo (top-3 provider ທີ່ຖືກເລືອກ) ແຕ່
// ບໍ່ເຄີຍຖືກອ່ານກັບຄືນມາໃຊ້ຢູ່ໃສເລີຍ — ວຽກຈຶ່ງເບິ່ງເຫັນໄດ້ໂດຍ provider ທຸກຄົນທີ່
// serviceTypes ກົງ, ບໍ່ແມ່ນສະເພາະ 3 ຄົນທີ່ຖືກເລືອກແທ້ຄືທີ່ UI ບອກລູກຄ້າ.
// sentTo ຫວ່າງເປົ່າ (ຍັງບໍ່ທັນຜ່ານ top-3 flow — ເຊັ່ນ booking ເກົ່າ/edge path)
// ຍັງເບິ່ງເຫັນໄດ້ໂດຍທຸກຄົນຄືເກົ່າ.
bool isJobVisibleToProvider(
    Booking b, String? myUid, List<String> myTypes) {
  if (b.providerId.isNotEmpty || b.isExpired) return false;
  if (myUid != null && b.rejectedBy.contains(myUid)) return false;
  if (myTypes.isNotEmpty && !myTypes.contains(b.category)) return false;
  if (b.sentTo.isNotEmpty && (myUid == null || !b.sentTo.contains(myUid))) {
    return false;
  }
  return true;
}

final unassignedOpenJobsProvider = Provider<List<Booking>>((ref) {
  final jobs = ref.watch(openJobsProvider).valueOrNull ?? [];
  final myTypes = ref.watch(profileStreamProvider).valueOrNull?.serviceTypes ?? [];
  final myUid = FirebaseAuth.instance.currentUser?.uid;
  return jobs.where((b) => isJobVisibleToProvider(b, myUid, myTypes)).toList();
});

final ongoingJobProvider = Provider<Booking?>((ref) {
  return ref.watch(activeBookingsProvider).whenOrNull(
    data: (list) => list
        .where((b) =>
    b.status == JobStatus.onTheWay ||
        b.status == JobStatus.arrived ||
        b.status == JobStatus.inProgress)
        .firstOrNull,
  );
});

// ── EARNINGS ─────────────────────────────────────────────────

final walletProvider = StreamProvider<Wallet>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(earningsRepoProvider).watchWallet();
});

final transactionsProvider = StreamProvider<List<ProviderTransaction>>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(earningsRepoProvider).watchTransactions();
});

// 🔒 [AUDIT PERF-5 / 2026-08-06] see EarningsRepository.watchMonthlyEarnings()
final monthlyEarningsProvider = StreamProvider<List<ProviderTransaction>>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(earningsRepoProvider).watchMonthlyEarnings();
});

// ── PROFILE ──────────────────────────────────────────────────

final profileStreamProvider = StreamProvider<ProviderProfile>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(profileRepoProvider).watchProfile();
});

final scheduleProvider = StreamProvider<WorkSchedule>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(profileRepoProvider).watchSchedule();
});

final reviewsProvider = StreamProvider<List<Review>>((ref) {
  ref.watch(currentUidProvider);
  return ref.watch(profileRepoProvider).watchReviews();
});

// ── BOOKING STATE ─────────────────────────────────────────────
// ✅ ເພີ່ມ BookingState ເພື່ອ track loadingIds per booking

class BookingState {
  final Set<String> loadingIds; // bookingIds ທີ່ກຳລັງ loading
  final String?     error;

  const BookingState({
    this.loadingIds = const {},
    this.error,
  });

  bool get isLoading => loadingIds.isNotEmpty;

  BookingState copyWith({
    Set<String>? loadingIds,
    String?      error,
  }) =>
      BookingState(
        loadingIds: loadingIds ?? this.loadingIds,
        error:      error,
      );
}

// ── BOOKING NOTIFIER ─────────────────────────────────────────

class BookingNotifier extends Notifier<BookingState> {
  late BookingRepository _repo;

  @override
  BookingState build() {
    _repo = ref.read(bookingRepoProvider);
    return const BookingState();
  }

  // ✅ helper: add/remove loadingId
  void _setLoading(String id, bool loading) {
    final ids = Set<String>.from(state.loadingIds);
    loading ? ids.add(id) : ids.remove(id);
    state = state.copyWith(loadingIds: ids, error: null);
  }

  Future<bool> accept(String bookingId) async {
    _setLoading(bookingId, true);
    try {
      await _repo.acceptBooking(bookingId);
      _setLoading(bookingId, false);
      return true;
    } catch (e) {
      state = state.copyWith(
        loadingIds: Set.from(state.loadingIds)..remove(bookingId),
        error:      e.toString(),
      );
      return false;
    }
  }

  Future<bool> reject(String bookingId, String reason) async {
    _setLoading(bookingId, true);
    try {
      await _repo.rejectBooking(bookingId, reason);
      _setLoading(bookingId, false);
      return true;
    } catch (e) {
      state = state.copyWith(
        loadingIds: Set.from(state.loadingIds)..remove(bookingId),
        error:      e.toString(),
      );
      return false;
    }
  }

  // 🔒 [AUDIT PROV-2 / 2026-07-30] ຍົກເລີກວຽກຫຼັງຮັບໄປແລ້ວ — ເບິ່ງ
  // providerCancelBooking() (booking_repository.dart) ສຳລັບ root cause.
  Future<bool> cancelJob(String bookingId, String reason) async {
    _setLoading(bookingId, true);
    try {
      await _repo.providerCancelBooking(bookingId, reason);
      _setLoading(bookingId, false);
      return true;
    } catch (e) {
      state = state.copyWith(
        loadingIds: Set.from(state.loadingIds)..remove(bookingId),
        error:      e.toString(),
      );
      return false;
    }
  }

  Future<bool> updateStatus(String bookingId, JobStatus status) async {
    _setLoading(bookingId, true);
    try {
      await _repo.updateStatus(bookingId, status);
      _setLoading(bookingId, false);
      return true;
    } catch (e) {
      state = state.copyWith(
        loadingIds: Set.from(state.loadingIds)..remove(bookingId),
        error:      e.toString(),
      );
      return false;
    }
  }

  // ✅ [FIX CRIT-1] step ໃໝ່ ຢືນຢັນຮັບເງິນ — ຕ້ອງເອີ້ນກ່ອນ updateStatus(completed)
  // ຈຶ່ງຈະຜ່ານ (booking_repository.dart / firestore.rules ບັງຄັບ paymentStatus
  // == 'paid' ກ່ອນປິດງານໄດ້).
  Future<bool> confirmPayment(String bookingId) async {
    _setLoading(bookingId, true);
    try {
      await _repo.confirmPaymentReceived(bookingId);
      _setLoading(bookingId, false);
      return true;
    } catch (e) {
      state = state.copyWith(
        loadingIds: Set.from(state.loadingIds)..remove(bookingId),
        error:      e.toString(),
      );
      return false;
    }
  }

  Future<bool> requestAdditionalCharges(
      String bookingId,
      double amount,
      String note,
      ) async {
    _setLoading(bookingId, true);
    try {
      await _repo.requestAdditionalCharges(bookingId, amount, note);
      _setLoading(bookingId, false);
      return true;
    } catch (e) {
      state = state.copyWith(
        loadingIds: Set.from(state.loadingIds)..remove(bookingId),
        error:      e.toString(),
      );
      return false;
    }
  }
}

final bookingNotifierProvider =
NotifierProvider<BookingNotifier, BookingState>(BookingNotifier.new);

// ── PROFILE NOTIFIER ─────────────────────────────────────────

class ProfileNotifier extends AsyncNotifier<void> {
  late ProfileRepository _repo;

  @override
  Future<void> build() async {
    _repo = ref.read(profileRepoProvider);
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.updateProfile(data));
    return !state.hasError;
  }

  Future<bool> saveSchedule(WorkSchedule schedule) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.saveSchedule(schedule));
    return !state.hasError;
  }

  Future<bool> replyToReview(String reviewId, String reply) async {
    state = const AsyncLoading();
    state =
    await AsyncValue.guard(() => _repo.replyToReview(reviewId, reply));
    return !state.hasError;
  }
}

final profileNotifierProvider =
AsyncNotifierProvider<ProfileNotifier, void>(ProfileNotifier.new);

// ── CREATE BOOKING NOTIFIER (ຝັ່ງລູກຄ້າ) ──────────────────────

class CreateBookingNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  Future<String?> submit(Map<String, dynamic> data, {String? couponCode}) async {
    state = const AsyncLoading();
    final repo   = ref.read(customerBookingRepoProvider);
    final result = await AsyncValue.guard(
        () => repo.createBooking(data, couponCode: couponCode));
    state = result;
    return result.valueOrNull;
  }
}

final createBookingNotifierProvider =
AsyncNotifierProvider<CreateBookingNotifier, String?>(
    CreateBookingNotifier.new);

// 🔒 [FOLLOWUP-I1] ກ່ອນໜ້ານີ້ໜ້າ Profile ສະແດງເລກ '5' ຄົງທີ່ຢູ່ໃນ source ໂດຍກົງ
// (ບໍ່ແມ່ນ query ຈິງ) — ລູກຄ້າທຸກຄົນເຫັນຄ່າດຽວກັນບໍ່ວ່າຈະມີປະຫວັດຈອງຈິງເທົ່າໃດ.
// ໃຊ້ aggregate count() ແທນ (ຖືກກວ່າການ download ທັງ list ພຽງແຕ່ນັບ).
final customerBookingCountProvider = FutureProvider<int>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 0;
  final agg = await FirebaseFirestore.instance
      .collection('bookings')
      .where('customerId', isEqualTo: uid)
      .count()
      .get();
  return agg.count ?? 0;
});

// ── FILTER ───────────────────────────────────────────────────

// 🔒 [AUDIT PROV-5 / 2026-08-02 — Medium, fresh re-audit] ກ່ອນໜ້ານີ້ state
// ນີ້ເປັນ String ຄ່າ hardcoded ພາສາລາວ ('ທັງໝົດ'), ປຽບທຽບກັບ b.status.label
// ທີ່ກໍ hardcode ພາສາລາວຄືກັນ (Booking.dart) — ຖ້າຜູ້ໃຊ້ປ່ຽນພາສາແອັບເປັນອື່ນ
// (English/Thai/Chinese), ໜ້າ Jobs tab ຈະສະແດງ filter chip ເປັນພາສານັ້ນ
// (ຜ່ານ tr() ໃນ jobs_tab.dart) ແຕ່ຄ່າທີ່ຂຽນລົງ state ນີ້ (f, ຄື tr() ຜົນ)
// ບໍ່ເຄີຍກົງກັບ 'ທັງໝົດ' ຫຼື b.status.label ອີກຕໍ່ໄປ — filter ບໍ່ເຮັດວຽກ
// (ລາຍການຫວ່າງເປົ່າ) ໃນທຸກພາສາທີ່ບໍ່ແມ່ນລາວ. ຕອນນີ້ໃຊ້ JobStatus? (null ='all')
// ເປັນ state ແທນ — locale-independent, jobs_tab.dart ຍັງສະແດງ label ທີ່
// localized ໄດ້ຄືເກົ່າ, ພຽງແຕ່ compare ດ້ວຍ enum ບໍ່ແມ່ນ display string.
final jobFilterProvider = StateProvider<JobStatus?>((_) => null);

final filteredHistoryProvider =
Provider<AsyncValue<List<Booking>>>((ref) {
  final filter  = ref.watch(jobFilterProvider);
  final history = ref.watch(jobHistoryProvider);
  return history.whenData((list) {
    if (filter == null) return list;
    return list.where((b) => b.status == filter).toList();
  });
});