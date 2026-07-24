// ============================================================
// job_visibility_test.dart — LinTho Provider App
//
// Regression test for FOLLOWUP-H: `sentTo` (the top-3 targeted providers,
// written by match_screen.dart's _sendRequestToTop3()) was never read back
// anywhere — unassignedOpenJobsProvider showed every open job to every
// provider whose serviceTypes matched, contradicting the "sent to 3
// people" premise shown to the customer.
//
// isJobVisibleToProvider() (booking_provider.dart) is a plain, unit-
// testable pure function — no Riverpod/FirebaseAuth mocking needed.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintho/Booking.dart';
import 'package:lintho/booking_provider.dart';

Booking _job({
  String providerId = '',
  bool expired = false,
  List<String> rejectedBy = const [],
  List<String> sentTo = const [],
  String category = 'house_clean',
}) {
  final now = DateTime.now();
  return Booking(
    id: 'b1',
    customerId: 'c1',
    customerName: 'ລູກຄ້າ',
    customerPhone: '2091234567',
    providerId: providerId,
    serviceType: 'house_clean',
    category: category,
    serviceEmoji: '🧹',
    address: 'ບ້ານ',
    location: const GeoPoint(0, 0),
    scheduledAt: now,
    status: JobStatus.pending,
    price: 100000,
    createdAt: now,
    expiresAt: expired
        ? now.subtract(const Duration(minutes: 1))
        : now.add(const Duration(minutes: 10)),
    rejectedBy: rejectedBy,
    sentTo: sentTo,
  );
}

void main() {
  group('FOLLOWUP-H: isJobVisibleToProvider()', () {
    test('a job with empty sentTo is visible to everyone (legacy/edge path)',
        () {
      final job = _job(sentTo: const []);
      expect(isJobVisibleToProvider(job, 'provider-X', const []), isTrue);
    });

    test('a job with sentTo set is only visible to the targeted providers',
        () {
      final job = _job(sentTo: const ['provider-A', 'provider-B']);
      expect(isJobVisibleToProvider(job, 'provider-A', const []), isTrue);
      expect(isJobVisibleToProvider(job, 'provider-C', const []), isFalse,
          reason: 'a provider not in the top-3 sentTo list must not see '
              'the job, matching the "sent to 3 people" premise shown to '
              'the customer');
    });

    test('an already-assigned job is never visible on the open board', () {
      final job = _job(providerId: 'provider-A', sentTo: const ['provider-A']);
      expect(isJobVisibleToProvider(job, 'provider-A', const []), isFalse);
    });

    test('an expired job is never visible', () {
      final job = _job(expired: true, sentTo: const ['provider-A']);
      expect(isJobVisibleToProvider(job, 'provider-A', const []), isFalse);
    });

    test('a provider that already rejected the job does not see it again',
        () {
      final job = _job(
          sentTo: const ['provider-A'], rejectedBy: const ['provider-A']);
      expect(isJobVisibleToProvider(job, 'provider-A', const []), isFalse);
    });

    test('serviceTypes filter still applies on top of sentTo', () {
      final job = _job(
          category: 'ac_clean', sentTo: const ['provider-A']);
      expect(
          isJobVisibleToProvider(job, 'provider-A', const ['house_clean']),
          isFalse,
          reason:
              'a provider must only see jobs matching their own service '
              'types, even if targeted by sentTo');
      expect(
          isJobVisibleToProvider(job, 'provider-A', const ['ac_clean']),
          isTrue);
    });

    test('a null myUid never matches a non-empty sentTo list', () {
      final job = _job(sentTo: const ['provider-A']);
      expect(isJobVisibleToProvider(job, null, const []), isFalse);
    });
  });
}
