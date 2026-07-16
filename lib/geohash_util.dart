// ============================================================
// geohash_util.dart — LinTho
// Manual geohash encode + neighbor lookup — ບໍ່ໃຊ້ external package
// (geoflutterfire2 ບໍ່ຮອງຮັບ cloud_firestore ^5.x ແລ້ວ)
//
// ໃຊ້ສຳລັບ bounding-box query ໃນ Firestore ກ່ອນ sort ດ້ວຍ
// Haversine distance (ProviderModel.distanceTo) — ບໍ່ໃຫ້ provider
// ໄກໆຖືກເລືອກກ່ອນ provider ໃກ້ ເພາະ Firestore limit() ຕັດກ່ອນຮູ້ໄລຍະທາງ
// ============================================================

class GeohashUtil {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  // ── encode(lat, lng, precision) ──────────────────────────
  static String encode(double lat, double lng, [int precision = 6]) {
    double latMin = -90.0,  latMax = 90.0;
    double lngMin = -180.0, lngMax = 180.0;

    final buffer = StringBuffer();
    bool isEvenBit = true;
    int bit = 0;
    int charIndex = 0;

    while (buffer.length < precision) {
      if (isEvenBit) {
        final mid = (lngMin + lngMax) / 2;
        if (lng >= mid) {
          charIndex = (charIndex << 1) + 1;
          lngMin = mid;
        } else {
          charIndex = charIndex << 1;
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          charIndex = (charIndex << 1) + 1;
          latMin = mid;
        } else {
          charIndex = charIndex << 1;
          latMax = mid;
        }
      }
      isEvenBit = !isEvenBit;

      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32[charIndex]);
        bit = 0;
        charIndex = 0;
      }
    }
    return buffer.toString();
  }

  // ── decode bounding box ກາງ ge ohash cell ────────────────
  static (double lat, double lng) _decodeCenter(String geohash) {
    double latMin = -90.0,  latMax = 90.0;
    double lngMin = -180.0, lngMax = 180.0;
    bool isEvenBit = true;

    for (final char in geohash.split('')) {
      final idx = _base32.indexOf(char);
      for (int i = 4; i >= 0; i--) {
        final bit = (idx >> i) & 1;
        if (isEvenBit) {
          final mid = (lngMin + lngMax) / 2;
          if (bit == 1) {
            lngMin = mid;
          } else {
            lngMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if (bit == 1) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        isEvenBit = !isEvenBit;
      }
    }
    return ((latMin + latMax) / 2, (lngMin + lngMax) / 2);
  }

  // ── neighborsOf(geohash) — 8 ຊ່ອງຂ້າງຄຽງ + ຕົນເອງ (9 ຊ່ອງ) ──
  // ໃຊ້ສຳລັບ Firestore `whereIn` bounding-box query
  static List<String> neighborsOf(String geohash) {
    final precision = geohash.length;
    final (lat, lng) = _decodeCenter(geohash);

    // ປະມານຂະໜາດ cell ຕາມ precision (latitude degrees)
    final latStep = 180.0 / (1 << (5 * precision ~/ 2));
    final lngStep = 360.0 / (1 << (5 * precision - 5 * precision ~/ 2));

    final result = <String>{geohash};
    for (final dLat in [-1, 0, 1]) {
      for (final dLng in [-1, 0, 1]) {
        if (dLat == 0 && dLng == 0) continue;
        final nLat = (lat + dLat * latStep).clamp(-90.0, 90.0);
        final nLng = lng + dLng * lngStep;
        final wrapped = nLng > 180
            ? nLng - 360
            : nLng < -180
                ? nLng + 360
                : nLng;
        result.add(encode(nLat, wrapped, precision));
      }
    }
    return result.toList();
  }
}
