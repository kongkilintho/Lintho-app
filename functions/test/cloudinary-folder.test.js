// ============================================================
// cloudinary-folder.test.js — LinTho Cloud Functions
//
// Regression test for FOLLOWUP-B: the job before/after photo folder regex
// in index.js's getCloudinarySignature(). Client (lib/cloudinary_service.dart
// uploadJobPhoto()) sends `jobs/$bookingId/before` or `/after`; the original
// _JOB_PHOTO_FOLDER_RE only matched `bookings/jobPhotos/...` (the KYC-style
// path used by booking_form_screen.dart's job-photo-before-booking flow) —
// every after-acceptance before/after photo upload was rejected
// permission-denied.
//
// Uses Node's built-in test runner (no new devDependency needed — matches
// engines.node: 24 in package.json). Run with (from functions/):
//   node --test
//
// ໝາຍເຫດ: index.js ນີ້ໂຫລດ Firebase Admin SDK ແລະ secrets ຕອນ import (module
// top-level) — ບໍ່ເໝາະສົມ import ໂດຍກົງໃນ unit test ນອກ emulator. ຄັດລອກ
// regex ທັງສອງອອກມາທົດສອບແທນ (ຄືກັນກັບ pattern ໃນ test/critical_fixes_test.dart
// ຝັ່ງ Dart) — ຖ້າແກ້ regex ໃນ source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
// ============================================================

const test = require('node:test');
const assert = require('node:assert/strict');

const _JOB_PHOTO_FOLDER_RE = /^bookings\/jobPhotos\/([A-Za-z0-9_-]{1,100})$/;
const _JOB_PHOTO_BEFORE_AFTER_RE =
  /^jobs\/([A-Za-z0-9_-]{1,100})\/(before|after)$/;

function matchesEitherJobPhotoFolder(folder) {
  return _JOB_PHOTO_FOLDER_RE.test(folder) ||
    _JOB_PHOTO_BEFORE_AFTER_RE.test(folder);
}

test('jobs/<bookingId>/before matches the new regex', () => {
  assert.match('jobs/abc123/before', _JOB_PHOTO_BEFORE_AFTER_RE);
});

test('jobs/<bookingId>/after matches the new regex', () => {
  assert.match('jobs/abc123/after', _JOB_PHOTO_BEFORE_AFTER_RE);
});

test('the before/after regex captures the bookingId in group 1', () => {
  const m = 'jobs/abc123/before'.match(_JOB_PHOTO_BEFORE_AFTER_RE);
  assert.ok(m);
  assert.equal(m[1], 'abc123');
});

test('bookings/jobPhotos/<id> still matches the original regex (KYC-style path)', () => {
  assert.match('bookings/jobPhotos/abc123', _JOB_PHOTO_FOLDER_RE);
});

test('an unrelated folder matches neither regex', () => {
  assert.equal(matchesEitherJobPhotoFolder('random/folder/path'), false);
});

test('a folder with an invalid before/after suffix is rejected', () => {
  assert.equal(matchesEitherJobPhotoFolder('jobs/abc123/during'), false);
});

test('path traversal / extra segments are rejected', () => {
  assert.equal(matchesEitherJobPhotoFolder('jobs/abc123/before/extra'), false);
  assert.equal(matchesEitherJobPhotoFolder('jobs/../etc/before'), false);
});
