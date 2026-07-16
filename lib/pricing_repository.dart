// ============================================================
// pricing_repository.dart — LinTho Customer App
// ກວດເບິ່ງ Service pricing (FIXED/TIERED) ທີ່ admin ຕັ້ງໄວ້ໃນ Firestore
// `services/{serviceId}` — ໂຄງສ້າງດຽວກັນກັບ lintho-admin/src/types/index.ts
// (Service / TierAttribute / TierOption).
//
// ✅ one-shot fetch ດຽວ (ບໍ່ stream) + cache ໃນ memory ~5 ນາທີ
// ✅ ບໍ່ throw ເດັດຂາດ — ຖ້າ offline/missing/error → return null
//    ໃຫ້ບ່ອນເອີ້ນໃຊ້ fallback ໄປໃຊ້ລາຄາ default/static ເອງ.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class TierOption {
  final String key;
  final String label;
  final num? price;
  final num? priceMin;
  final num? priceMax;

  const TierOption({
    required this.key,
    required this.label,
    this.price,
    this.priceMin,
    this.priceMax,
  });

  factory TierOption.fromMap(Map<String, dynamic> m) => TierOption(
        key: m['key'] as String? ?? '',
        label: m['label'] as String? ?? '',
        price: m['price'] as num?,
        priceMin: m['priceMin'] as num?,
        priceMax: m['priceMax'] as num?,
      );
}

enum TierAttributeType { select, perUnit, addonList }

TierAttributeType _tierAttributeTypeFrom(String? raw) => switch (raw) {
      'perUnit' => TierAttributeType.perUnit,
      'addonList' => TierAttributeType.addonList,
      _ => TierAttributeType.select,
    };

class TierAttribute {
  final String key;
  final String label;
  final TierAttributeType type;
  final List<TierOption> options;
  final num? unitPriceMin;
  final num? unitPriceMax;
  final num? minQty;

  const TierAttribute({
    required this.key,
    required this.label,
    required this.type,
    this.options = const [],
    this.unitPriceMin,
    this.unitPriceMax,
    this.minQty,
  });

  factory TierAttribute.fromMap(Map<String, dynamic> m) => TierAttribute(
        key: m['key'] as String? ?? '',
        label: m['label'] as String? ?? '',
        type: _tierAttributeTypeFrom(m['type'] as String?),
        options: (m['options'] as List<dynamic>? ?? [])
            .map((o) => TierOption.fromMap(o as Map<String, dynamic>))
            .toList(),
        unitPriceMin: m['unitPriceMin'] as num?,
        unitPriceMax: m['unitPriceMax'] as num?,
        minQty: m['minQty'] as num?,
      );

  /// ຫາ option ດ້ວຍ key — ໃຊ້ໂດຍ adapter/booking screen.
  TierOption? optionByKey(String key) {
    for (final o in options) {
      if (o.key == key) return o;
    }
    return null;
  }
}

class ServicePricing {
  final String id;
  final String pricingType; // 'FIXED' | 'TIERED'
  final num? basePrice;
  final List<TierAttribute> tierAttributes;

  const ServicePricing({
    required this.id,
    required this.pricingType,
    this.basePrice,
    this.tierAttributes = const [],
  });

  bool get isFixed => pricingType == 'FIXED';
  bool get isTiered => pricingType == 'TIERED';

  factory ServicePricing.fromMap(String id, Map<String, dynamic> m) => ServicePricing(
        id: id,
        pricingType: m['pricingType'] as String? ?? 'FIXED',
        basePrice: m['basePrice'] as num?,
        tierAttributes: (m['tierAttributes'] as List<dynamic>? ?? [])
            .map((a) => TierAttribute.fromMap(a as Map<String, dynamic>))
            .toList(),
      );

  /// ຫາ attribute ດ້ວຍ key — ໃຊ້ໂດຍ adapter/booking screen.
  TierAttribute? attributeByKey(String key) {
    for (final a in tierAttributes) {
      if (a.key == key) return a;
    }
    return null;
  }
}

class _CacheEntry {
  final ServicePricing? pricing;
  final DateTime fetchedAt;
  _CacheEntry(this.pricing, this.fetchedAt);
}

class PricingRepository {
  PricingRepository._();
  static final PricingRepository instance = PricingRepository._();

  static const _cacheTtl = Duration(minutes: 5);
  final Map<String, _CacheEntry> _cache = {};

  /// ດຶງ pricing ຂອງ service ດຽວ — one-shot, ບໍ່ stream.
  /// ຖ້າ fetch ສຳເລັດ ຈະ cache ໄວ້ ~5 ນາທີ ເພື່ອບໍ່ໃຫ້ອ່ານ Firestore ຫຼາຍຄັ້ງ.
  /// ຖ້າ offline/missing/error → return null (ບໍ່ throw) ໃຫ້ caller fallback ເອງ.
  Future<ServicePricing?> fetchPricing(String serviceId) async {
    final cached = _cache[serviceId];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached.pricing;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('services').doc(serviceId).get();
      if (!doc.exists || doc.data() == null) {
        _cache[serviceId] = _CacheEntry(null, DateTime.now());
        return null;
      }
      final pricing = ServicePricing.fromMap(doc.id, doc.data()!);
      _cache[serviceId] = _CacheEntry(pricing, DateTime.now());
      return pricing;
    } catch (_) {
      return null;
    }
  }

  void clearCache() => _cache.clear();
}
