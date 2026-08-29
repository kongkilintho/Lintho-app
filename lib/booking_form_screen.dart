// ============================================================
// booking_form_screen.dart — LinTho
// Fixes applied in this version:
//   ✅ [FIX-1] tr("error") → replaced with hardcoded Lao string
//              (safe even if app_locale.dart changes)
//   ✅ [FIX-2] cleanRoomPrices[roomType]! null bang → safe lookup
//   ✅ [FIX-3] expiresAt client DateTime.now() → FieldValue approach
//              with comment explaining limitation
//   ✅ [FIX-4] _TimeSlots date drift → base computed once outside build
//   ── Previous fixes (kept) ──────────────────────────────────
//   ✅ _catLabel() string interpolation
//   ✅ _SqmInput uses TextEditingController (no state loss)
//   ✅ _BcelQrBox uses qr_flutter real QR
//   ✅ _TravelFeeBox shows note when manual address
//   ✅ Skeleton loading ແທນ CircularProgressIndicator ສະເພາະ full-page/list
//      load state — inline button/upload-progress spinners (still
//      CircularProgressIndicator by design, see AUDIT UI-6 2026-08-02) are a
//      different UX moment and were never meant to be covered by this fix
//   ✅ withValues(alpha:) ທຸກ instance
//   ✅ InkWell + Material ທຸກ tap target
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check ຫຼັງ async
// ============================================================

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_colors.dart';
import 'theme/app_theme.dart' show AppRadius, AppSpacing, AppTypography;
import 'widgets/app_text.dart';
import 'widgets/status_stepper.dart';
import 'app_locale.dart';
import 'app_navigation_state.dart';
import 'booking_provider.dart';
import 'cloudinary_service.dart';
import 'coupon_repository.dart';
import 'firestore_service.dart';
import 'match_screen.dart';
import 'payment_config_provider.dart';
import 'phone_verification.dart';
import 'pricing_repository.dart';

String _generateClientRequestId() {
  final rnd = Random();
  final ts = DateTime.now().millisecondsSinceEpoch;
  final suffix = List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
  return 'cr_${ts}_$suffix';
}

// ════════════════════════════════════════════════════════════
//  CONSTANTS & PRICING
// ════════════════════════════════════════════════════════════

class AppPricing {
  // ▸ [LIVE PRICING] ຄ່າທັງໝົດໃນຄລາສນີ້ເປັນ `static` (ບໍ່ແມ່ນ `const`) ໂດຍ
  // ເຈດຕະນາ — ຄ່າທີ່ຂຽນຢູ່ນີ້ແມ່ນ default/fallback (ລາຄາມາດຕະຖານ 2026).
  // `AppPricing.loadLive()` (ເອີ້ນຕອນ initState ຂອງ _BookingFormScreenState)
  // ຈະ override ຄ່າທີ່ admin ຕັ້ງໄວ້ໃນ Firestore `services/{ac_clean,
  // house_clean, pest_control}` (TIERED, ເບິ່ງ pricing_repository.dart) —
  // ຖ້າ admin ບໍ່ໄດ້ຕັ້ງ key ໃດໄວ້ ຄ່າ default ນີ້ຈະຍັງໃຊ້ຕໍ່ (ບໍ່ throw,
  // ບໍ່ regression). ທຸກ 40+ ບ່ອນອ່ານ `AppPricing.xxx` ໃນໄຟລ໌ນີ້ບໍ່ຕ້ອງແກ້ໄຂ
  // ເລີຍ ເພາະອ່ານຄ່າ static ດຽວກັນນີ້ໂດຍກົງ.

  // ✅ ລາຄາມາດຕະຖານ 2026 — ແຍກຕາມຂະໜາດ BTU ໂດຍກົງ, ບໍ່ບວກກັນລະຫວ່າງ
  // "ລ້າງທົ່ວໄປ" ກັບ "ລ້າງໃຫຍ່" (ແຕ່ລະປະເພດເປັນລາຄາສຸດທິແຍກກັນ)
  static Map<AcBtuSize, int> acStdPrice = {
    AcBtuSize.small:   300000, // 9,000–13,000 BTU
    AcBtuSize.large:   350000, // 18,000–24,000 BTU
    AcBtuSize.cabinet: 450000, // 30,000+ BTU
  };
  static Map<AcBtuSize, int> acDeepPrice = {
    AcBtuSize.small:   690000,
    AcBtuSize.large:   790000,
    AcBtuSize.cabinet: 990000,
  };
  static Map<AcBtuSize, (int min, int max)> acRefillPrice = {
    AcBtuSize.small:   (150000, 200000),
    AcBtuSize.large:   (200000, 300000),
    AcBtuSize.cabinet: (300000, 450000),
  };

  static int relocateSmallMin   = 450000;
  static int relocateSmallMax   = 600000;
  static int relocateLargeMin   = 650000;
  static int relocateLargeMax   = 850000;
  static int relocateCabinetMin = 950000;
  static int relocateCabinetMax = 1300000;

  // ✅ ສ່ວນຫຼຸດປະລິມານ — ນັບສະເພາະເຄື່ອງທີ່ "ລ້າງ" (ທົ່ວໄປ/ໃຫຍ່), ບໍ່ນັບ Add-on
  static double acVolumeDiscountPct(int washQty) {
    if (washQty >= 5) return 0.10;
    if (washQty >= 2) return 0.05;
    return 0;
  }

  static int acUnitPrice(AcServiceType type, AcBtuSize size) {
    switch (type) {
      case AcServiceType.standard: return acStdPrice[size]!;
      case AcServiceType.deepFull: return acDeepPrice[size]!;
      case AcServiceType.refill:   return acRefillPrice[size]!.$1; // ປະມານ = min
      case AcServiceType.relocate:
        return switch (size) {
          AcBtuSize.small   => relocateSmallMin,
          AcBtuSize.large   => relocateLargeMin,
          AcBtuSize.cabinet => relocateCabinetMin,
        };
    }
  }

  static int installSmallMin  = 300000;
  static int installSmallMax  = 400000;
  static int installLargeMin  = 450000;
  static int installLargeMax  = 550000;
  static int removeMin        = 150000;
  static int removeMax        = 250000;

  static int btuLargeSurchargeMin = 200000;
  static int btuLargeSurchargeMax = 400000;

  static int cleanHourMin    = 60000;
  static int cleanHourMax    = 90000;
  static int cleanHourMinQty = 2;

  static Map<String, Map<String, int>> cleanRoomPrices = {
    '1bed': {'min': 250000, 'max': 350000},
    '2bed': {'min': 350000, 'max': 500000},
  };

  // ✅ ບໍລິການເສີມ — ສຳລັບໜ້າທຳຄວາມສະອາດທົ່ວໄປ (ເໝົາຕາມຫ້ອງ)
  // ✅ [i18n] 'name' ໃນນີ້ບໍ່ແມ່ນ display text ອີກຕໍ່ໄປ — ມັນຄື tr() KEY.
  // ຄ່າ static ນີ້ອາດຖືກ override ໂດຍ loadLive() (spread ...addonItems[key]!)
  // ເຊິ່ງຍັງຄົງ 'name' key ເກົ່າໄວ້ — ບໍ່ກະທົບ. ໃຫ້ tr() ຢູ່ display site ເທົ່ານັ້ນ
  // (_AddonCheckRow) ເພື່ອບໍ່ໃຫ້ static field ຄ້າງພາສາເກົ່າ.
  // 🔒 [AUDIT UI-1 / 2026-08-02 — Medium, fresh re-audit] 'emoji' → 'icon'
  // (IconData) — ໜ້ານີ້ໄດ້ migrate _QuickBookCard/_BigCatCard/_BtuSelector
  // ໄປໃຊ້ Icon() ແລ້ວ (ເບິ່ງ [FIX ME-7] comment) ແຕ່ addon/specialist rows
  // ຂ້າງລຸ່ມນີ້ຍັງເຫຼືອ emoji ດິບ.
  static Map<String, Map<String, dynamic>> addonItems = {
    'ironing': {'name': 'addon_ironing_name', 'icon': Icons.iron_outlined, 'price': 50000},
    'fridge':  {'name': 'addon_fridge_name',  'icon': Icons.kitchen_outlined, 'price': 40000},
    'oven':    {'name': 'addon_oven_name',    'icon': Icons.local_fire_department_outlined, 'price': 20000},
    'window':  {'name': 'addon_window_name',  'icon': Icons.window_outlined, 'price': 30000},
  };

  static int deepResMin  = 15000;
  static int deepResMax  = 25000;
  static int deepPostMin = 20000;
  static int deepPostMax = 35000;
  static double deepSqmMin = 50; // ✅ ຂັ້ນຕ່ຳ 50 ຕາແມັດ
  // 🔒 [AUDIT EDGE-4 / 2026-08-06] ບໍ່ເຄີຍມີຂອບເຂດເທິງ — ຕົວເລກຜິດພາດ (ພິມເລກ
  // 0 ເກີນ, ເຊັ່ນ 5000 ແທນ 500) ຈະຜ່ານທຸກຂັ້ນຕອນຈົນຮອດ submit ແລ້ວຖືກ
  // firestore.rules' price<=50000000 ປະຕິເສດແບບ raw exception ທີ່ອ່ານບໍ່ຮູ້ເລື່ອງ.
  // ຂອບເຂດນີ້ (2000 ຕາແມັດ ≈ ບ້ານໃຫຍ່ທີ່ສຸດທີ່ເປັນໄປໄດ້ຈິງ) ໃຫ້ warn ຝັ່ງ UI ກ່ອນ.
  static double deepSqmMax = 2000;

  static int pestSqmMin = 5000;
  static int pestSqmMax = 10000;

  // ✅ [i18n] 'name'/'unit'/'sub' ໃນນີ້ຄື tr() KEY (ບໍ່ແມ່ນ display text) —
  // ເບິ່ງ comment ຢູ່ addonItems ຂ້າງເທິງ.
  static Map<String, Map<String, dynamic>> specialistItems = {
    'sofa':     {'name': 'specialist_sofa_name',     'icon': Icons.weekend_outlined, 'min': 300000, 'max': 500000, 'unit': 'specialist_sofa_unit'},
    'mattress': {'name': 'specialist_mattress_name', 'icon': Icons.bed_outlined, 'min': 250000, 'max': 450000, 'unit': 'specialist_mattress_unit',
                 'sub': 'specialist_mattress_sub'},
    'vacuum':   {'name': 'specialist_vacuum_name',   'icon': Icons.cyclone_outlined, 'min': 150000, 'max': 250000, 'unit': 'specialist_vacuum_unit',
                 'sub': 'specialist_vacuum_sub'},
    'carpet':   {'name': 'specialist_carpet_name',   'icon': Icons.texture_outlined, 'min': 25000,  'max': 40000,  'unit': 'specialist_carpet_unit'},
    'facade':   {'name': 'specialist_facade_name',   'icon': Icons.apartment_outlined, 'min': 5000, 'max': 15000, 'unit': 'specialist_facade_unit'},
    'pest':     {'name': 'specialist_pest_name',     'icon': Icons.pest_control_outlined, 'min': 5000,   'max': 10000,  'unit': 'specialist_pest_unit'},
  };

  static double travelFreeKm = 10.0;
  static int    travelFee    = 30000;

  static String fmt(int p) => p.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  static int calcCleanHourly(int hours) => cleanHourMin * hours;

  static int calcDeepSqm(double sqm, bool isPost) {
    final rate = isPost ? deepPostMin : deepResMin;
    return (sqm * rate).round();
  }

  // ▸ [LIVE PRICING] ດຶງ TIERED service docs ຈາກ Firestore ແລະ override
  // ຄ່າ static ຂ້າງເທິງ — ເອີ້ນຄັ້ງດຽວຕອນເປີດ Booking Form (initState).
  // ບໍ່ throw ເດັດຂາດ (PricingRepository ຫຸ້ມ try/catch ໝົດແລ້ວ); ຖ້າ
  // service doc ບໍ່ມີ ຫຼື attribute/option key ບໍ່ກົງ → ຄ່າ default ຍັງຄົງເກົ່າ.
  //
  // ▸ Key convention (admin ຕ້ອງຕັ້ງໃຫ້ກົງ — ເບິ່ງ TierAttributeEditor):
  //   services/ac_clean (TIERED):
  //     acStdBtu (select: small/large/cabinet, price)        → acStdPrice
  //     acDeepBtu (select: small/large/cabinet, price)        → acDeepPrice
  //     acRefillBtu (select: small/large/cabinet, priceMin/Max)→ acRefillPrice
  //     acRelocateBtu (select: small/large/cabinet, priceMin/Max) → relocate*
  //     acInstallBtu (select: small/large, priceMin/Max)      → install*
  //     acRemove (perUnit: unitPriceMin/Max)                  → removeMin/Max
  //     acBtuLargeSurcharge (perUnit: unitPriceMin/Max)        → btuLargeSurcharge*
  //   services/house_clean (TIERED):
  //     roomCount (select: 1bed/2bed, priceMin/Max)            → cleanRoomPrices
  //     hourlyRate (perUnit: unitPriceMin/Max, minQty)         → cleanHourMin/Max/MinQty
  //     addons (addonList: ironing/fridge/oven/window, price) → addonItems[*]['price']
  //     areaSqmResidential (perUnit: unitPriceMin/Max, minQty) → deepResMin/Max, deepSqmMin
  //     areaSqmCommercial (perUnit: unitPriceMin/Max)          → deepPostMin/Max
  //     specialistItem (select: sofa/mattress/vacuum/carpet/facade, priceMin/Max) → specialistItems[*]['min'/'max']
  //   services/pest_control (TIERED):
  //     areaSqm (perUnit: unitPriceMin/Max)                    → pestSqmMin/Max
  static Future<void> loadLive() async {
    final repo = PricingRepository.instance;
    final results = await Future.wait([
      repo.fetchPricing('ac_clean'),
      repo.fetchPricing('house_clean'),
      repo.fetchPricing('pest_control'),
    ]);
    final ac    = results[0];
    final house = results[1];
    final pest  = results[2];

    if (ac != null && ac.isTiered) {
      _applySelectBtu(ac.attributeByKey('acStdBtu'), (m) => acStdPrice = m);
      _applySelectBtu(ac.attributeByKey('acDeepBtu'), (m) => acDeepPrice = m);
      _applySelectBtuRange(ac.attributeByKey('acRefillBtu'), (m) => acRefillPrice = m);

      final relocate = ac.attributeByKey('acRelocateBtu');
      final relocateSmall = relocate?.optionByKey('small');
      if (relocateSmall != null) {
        relocateSmallMin = (relocateSmall.priceMin ?? relocateSmallMin).round();
        relocateSmallMax = (relocateSmall.priceMax ?? relocateSmallMax).round();
      }
      final relocateLarge = relocate?.optionByKey('large');
      if (relocateLarge != null) {
        relocateLargeMin = (relocateLarge.priceMin ?? relocateLargeMin).round();
        relocateLargeMax = (relocateLarge.priceMax ?? relocateLargeMax).round();
      }
      final relocateCabinet = relocate?.optionByKey('cabinet');
      if (relocateCabinet != null) {
        relocateCabinetMin = (relocateCabinet.priceMin ?? relocateCabinetMin).round();
        relocateCabinetMax = (relocateCabinet.priceMax ?? relocateCabinetMax).round();
      }

      final install = ac.attributeByKey('acInstallBtu');
      final installSmall = install?.optionByKey('small');
      if (installSmall != null) {
        installSmallMin = (installSmall.priceMin ?? installSmallMin).round();
        installSmallMax = (installSmall.priceMax ?? installSmallMax).round();
      }
      final installLarge = install?.optionByKey('large');
      if (installLarge != null) {
        installLargeMin = (installLarge.priceMin ?? installLargeMin).round();
        installLargeMax = (installLarge.priceMax ?? installLargeMax).round();
      }

      final remove = ac.attributeByKey('acRemove');
      if (remove != null) {
        removeMin = (remove.unitPriceMin ?? removeMin).round();
        removeMax = (remove.unitPriceMax ?? removeMax).round();
      }
      final surcharge = ac.attributeByKey('acBtuLargeSurcharge');
      if (surcharge != null) {
        btuLargeSurchargeMin = (surcharge.unitPriceMin ?? btuLargeSurchargeMin).round();
        btuLargeSurchargeMax = (surcharge.unitPriceMax ?? btuLargeSurchargeMax).round();
      }
    }

    if (house != null && house.isTiered) {
      final roomCount = house.attributeByKey('roomCount');
      if (roomCount != null) {
        final next = <String, Map<String, int>>{};
        for (final opt in roomCount.options) {
          if (opt.priceMin != null && opt.priceMax != null) {
            next[opt.key] = {'min': opt.priceMin!.round(), 'max': opt.priceMax!.round()};
          }
        }
        if (next.isNotEmpty) cleanRoomPrices = next;
      }

      final hourly = house.attributeByKey('hourlyRate');
      if (hourly != null) {
        cleanHourMin = (hourly.unitPriceMin ?? cleanHourMin).round();
        cleanHourMax = (hourly.unitPriceMax ?? cleanHourMax).round();
        cleanHourMinQty = (hourly.minQty ?? cleanHourMinQty).round();
      }

      final addons = house.attributeByKey('addons');
      if (addons != null) {
        for (final opt in addons.options) {
          if (addonItems.containsKey(opt.key) && opt.price != null) {
            addonItems[opt.key] = {...addonItems[opt.key]!, 'price': opt.price!.round()};
          }
        }
      }

      final areaRes = house.attributeByKey('areaSqmResidential');
      if (areaRes != null) {
        deepResMin = (areaRes.unitPriceMin ?? deepResMin).round();
        deepResMax = (areaRes.unitPriceMax ?? deepResMax).round();
        deepSqmMin = (areaRes.minQty ?? deepSqmMin).toDouble();
      }
      final areaCom = house.attributeByKey('areaSqmCommercial');
      if (areaCom != null) {
        deepPostMin = (areaCom.unitPriceMin ?? deepPostMin).round();
        deepPostMax = (areaCom.unitPriceMax ?? deepPostMax).round();
      }

      final specialist = house.attributeByKey('specialistItem');
      if (specialist != null) {
        for (final opt in specialist.options) {
          if (specialistItems.containsKey(opt.key) && opt.priceMin != null && opt.priceMax != null) {
            specialistItems[opt.key] = {
              ...specialistItems[opt.key]!,
              'min': opt.priceMin!.round(),
              'max': opt.priceMax!.round(),
            };
          }
        }
      }
    }

    if (pest != null && pest.isTiered) {
      final areaSqm = pest.attributeByKey('areaSqm');
      if (areaSqm != null) {
        pestSqmMin = (areaSqm.unitPriceMin ?? pestSqmMin).round();
        pestSqmMax = (areaSqm.unitPriceMax ?? pestSqmMax).round();
      }
    }
  }

  static void _applySelectBtu(TierAttribute? attr, void Function(Map<AcBtuSize, int>) apply) {
    if (attr == null) return;
    final next = <AcBtuSize, int>{};
    for (final size in AcBtuSize.values) {
      final opt = attr.optionByKey(size.name);
      if (opt?.price != null) next[size] = opt!.price!.round();
    }
    if (next.length == AcBtuSize.values.length) apply(next);
  }

  static void _applySelectBtuRange(
      TierAttribute? attr, void Function(Map<AcBtuSize, (int, int)>) apply) {
    if (attr == null) return;
    final next = <AcBtuSize, (int, int)>{};
    for (final size in AcBtuSize.values) {
      final opt = attr.optionByKey(size.name);
      if (opt?.priceMin != null && opt?.priceMax != null) {
        next[size] = (opt!.priceMin!.round(), opt.priceMax!.round());
      }
    }
    if (next.length == AcBtuSize.values.length) apply(next);
  }
}

// ════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════

enum ServiceCategory  { acCleaning, homeCleaning }

// ▸ ລະຫັດ category ມາດຕະຖານ (snake_case) ໃຫ້ກົງກັນກັບ
// provider.serviceTypes (ນິຍາມໃນ profile_tab.dart) ແລະ admin Service.category —
// ຫ້າມໃຊ້ ServiceCategory.name (camelCase) ໂດຍກົງ ບໍ່ດັ່ງນັ້ນ match_screen.dart
// ຈະຫາ provider ບໍ່ພົບ.
extension ServiceCategoryKey on ServiceCategory {
  String get key => switch (this) {
    ServiceCategory.acCleaning   => 'ac_clean',
    ServiceCategory.homeCleaning => 'house_clean',
  };
}
enum HomeCleaningType { general, deep, specialist }
enum AcServiceType    { standard, deepFull, refill, relocate }
enum AcBtuSize        { small, large, cabinet }
enum PriceMode        { hourly, room, sqm, perUnit, quote }

String acTypeEmoji(AcServiceType t) => switch (t) {
  AcServiceType.standard => '❄️',
  AcServiceType.deepFull => '🔧',
  AcServiceType.refill   => '🧪',
  AcServiceType.relocate => '🚚',
};

// 🔒 [PHASE1] acTypeEmoji() ຍັງຄົງໄວ້ (ບໍ່ໄດ້ໃຊ້ render ອີກຕໍ່ໄປ — ຄົງໄວ້ເຜື່ອ
// ບ່ອນອື່ນອ້າງອີງ) — cart-item tile ດຽວນີ້ໃຊ້ acTypeIcon() ແທນ, ຄືກັນກັບ
// _AcTypeCard/_QuickBookCard ຂ້າງເທິງທີ່ migrate ໄປແລ້ວ
IconData acTypeIcon(AcServiceType t) => switch (t) {
  AcServiceType.standard => Icons.ac_unit_rounded,
  AcServiceType.deepFull => Icons.auto_awesome_outlined,
  AcServiceType.refill   => Icons.science_outlined,
  AcServiceType.relocate => Icons.local_shipping_outlined,
};

String acTypeLabel(AcServiceType t) => switch (t) {
  AcServiceType.standard => tr('ac_type_general_wash'),
  AcServiceType.deepFull => tr('ac_type_deep_wash'),
  AcServiceType.refill   => tr('ac_type_refill'),
  AcServiceType.relocate => tr('ac_type_relocate'),
};

String btuLabel(AcBtuSize b) => switch (b) {
  AcBtuSize.small   => '9,000–13,000 BTU',
  AcBtuSize.large   => '18,000–24,000 BTU',
  AcBtuSize.cabinet => '30,000+ BTU',
};

// ✅ ກະຕ່າສິນຄ້າ — ຮອງຮັບການຈອງຫຼາຍເຄື່ອງ ຫຼາຍຂະໜາດ/ປະເພດ ໃນຄຳສັ່ງດຽວ
class AcCartItem {
  final String        id;
  final AcServiceType type;
  final AcBtuSize     btuSize;
  int                 qty;
  AcCartItem({required this.type, required this.btuSize, required this.qty})
      : id = _generateClientRequestId();
}

class BookingOrder {
  ServiceCategory    category;
  List<AcCartItem>   acCart      = [];
  AcServiceType?     acDraftType;
  AcBtuSize          acDraftBtu  = AcBtuSize.small;
  int                acDraftQty  = 1;
  HomeCleaningType? cleanType;
  PriceMode?        priceMode;
  int               hours     = 2;
  String?           roomType;
  double            sqm       = 0;
  bool              isPostConstruct = false;
  Map<String, int>  specialistQty   = {};
  double            pestSqm         = 0; // ✅ ພົ່ນຢາຂ້າເຊື້ອ ຄິດເປັນຕາແມັດ ບໍ່ແມ່ນຈຳນວນ
  Set<String>       addonServices   = {}; // ✅ ບໍລິການເສີມ (ຮີດເຄື່ອງ/ຕູ້ເຢັນ/ຕູ້ອົບ/ກະຈົກ)
  String            maidNotes       = ''; // ✅ ໝາຍເຫດເຖິງແມ່ບ້ານ
  DateTime?         scheduledAt;
  bool              isNow      = true;
  String            address    = '';
  // ✅ ຄ່າເລີ່ມຕົ້ນ = ສູນກາງວຽງຈັນ — ປ້ອງກັນ permission-denied ຕອນສົ່ງ booking
  // ເພາະ firestore.rules ບັງຄັບ lat/lng ຕ້ອງເປັນ number (ກໍລະນີພິມທີ່ຢູ່ມືເອງ ບໍ່ໄດ້ກົດ GPS)
  double            lat = 17.9667;
  double            lng = 102.6000;
  double            distanceKm = 0;
  bool              isGpsAddress = false;
  String            landmark = ''; // ✅ ຮ່ອມ/ເຮືອນເລກທີ/ຈຸດສັງເກດ — ຊ່ວຍຊ່າງຊອກຫາເຮືອນ
  String            specialInstructions = ''; // ✅ ໝາຍເຫດເຖິງຊ່າງ — ໃຊ້ໄດ້ທຸກປະເພດບໍລິການ
  String            jobPhotoUrl = ''; // ✅ ຮູບໜ້າວຽກ (ທາງເລືອກ) ໃຫ້ຊ່າງເບິ່ງກ່ອນ
  String            paymentMethod = 'cash';
  final String      clientRequestId = _generateClientRequestId();
  String?           couponCode;
  num?              couponDiscount;
  // 🔒 [AUDIT CUST-1 / 2026-08-06] grandTotal ຢູ່ຕອນທີ່ coupon ຖືກກວດ/apply —
  // couponDiscount ຖືກເກັບເປັນຈຳນວນ Kip ຄົງທີ່ (ບໍ່ແມ່ນ % ສົດ), ຄິດໄລ່ຈາກ
  // grandTotal ຕອນນັ້ນຄັ້ງດຽວ. ຖ້າຜູ້ໃຊ້ກັບໄປແກ້ໄຂລາຍການ (ກົດ "ແກ້ໄຂ" ຈາກໜ້າ
  // ທົບທວນ ຫຼືປ່ຽນຈຳນວນ/ແພັກເກັດ) ຫຼັງຈາກ apply coupon ແລ້ວ, grandTotal ໃໝ່ຈະ
  // ບໍ່ກົງກັບຄ່ານີ້ອີກຕໍ່ໄປ — ໃຊ້ປຽບທຽບໃນ _invalidateStaleCoupon() ຂ້າງລຸ່ມ.
  num?              _couponBaseTotal;

  BookingOrder({required this.category});

  bool get hasTravelFee => distanceKm > AppPricing.travelFreeKm;

  // 🔒 [AUDIT CUST-1 / 2026-08-06] ຖ້າ grandTotal ປ່ຽນໄປຫຼັງຈາກ coupon ຖືກ
  // apply (ເບິ່ງ _couponBaseTotal ຂ້າງເທິງ), couponDiscount ເກົ່າບໍ່ຄືນເປັນ
  // ຄ່າທີ່ຖືກຕ້ອງອີກຕໍ່ໄປ — ຖ້າປ່ອຍໃຫ້ discountedTotal ຫັກມັນອອກຈາກ grandTotal
  // ໃໝ່ໂດຍກົງ, ຜູ້ໃຊ້ສາມາດຫຼຸດລາຍການຈົນລາຄາຕ່ຳກວ່າສ່ວນຫຼຸດ ແລ້ວ price ຈະຖືກ
  // clamp ເປັນ 0 ໄດ້ທັງໆທີ່ຍັງໄດ້ຮັບບໍລິການເຕັມມູນຄ່າ. ຕອນນີ້ຖືວ່າ coupon ໝົດ
  // ອາຍຸ/ບໍ່ກົງກັນອີກຕໍ່ໄປທັນທີ grandTotal ປ່ຽນ — ລ້າງຄ່າຖິ້ມ (ບໍ່ຫັກສ່ວນຫຼຸດ,
  // ບໍ່ຂຽນ couponCode ໄປນຳ booking — ບໍ່ດັ່ງນັ້ນ createBooking()
  // (booking_repository.dart) ຈະນັບວ່າ coupon ຖືກໃຊ້ (usedCount+1) ທັງໆທີ່ບໍ່ໄດ້
  // ຫັກສ່ວນຫຼຸດແທ້) — ຜູ້ໃຊ້ຕ້ອງໃສ່ລະຫັດຄືນໃໝ່ຖ້າຍັງຕ້ອງການໃຊ້.
  void _invalidateStaleCoupon() {
    if (couponCode != null &&
        _couponBaseTotal != null &&
        grandTotal != _couponBaseTotal) {
      couponCode = null;
      couponDiscount = null;
      _couponBaseTotal = null;
    }
  }

  // ✅ ລາຄາສຸດທິຫຼັງຫັກສ່ວນຫຼຸດ coupon (ຖ້າມີ) — ນີ້ຄືຄ່າທີ່ລູກຄ້າຈ່າຍຈິງ
  // ແລະ ຄ່າທີ່ຂຽນເຂົ້າ field 'price' (admin dashboard revenue ອ່ານ field ນີ້)
  num get discountedTotal {
    _invalidateStaleCoupon();
    return (grandTotal - (couponDiscount ?? 0)).clamp(0, double.infinity);
  }

  // ✅ ລາຍການ "ລ້າງ" (ທົ່ວໄປ/ໃຫຍ່) ນັບລວມເພື່ອຄິດສ່ວນຫຼຸດປະລິມານ — ບໍ່ນັບ Add-on
  bool _isWashItem(AcCartItem i) =>
      i.type == AcServiceType.standard || i.type == AcServiceType.deepFull;

  int get acWashQty =>
      acCart.where(_isWashItem).fold(0, (s, i) => s + i.qty);

  int get acWashSubtotal => acCart.where(_isWashItem).fold(
      0, (s, i) => s + AppPricing.acUnitPrice(i.type, i.btuSize) * i.qty);

  int get acAddonSubtotal => acCart.where((i) => !_isWashItem(i)).fold(
      0, (s, i) => s + AppPricing.acUnitPrice(i.type, i.btuSize) * i.qty);

  double get acDiscountPct => AppPricing.acVolumeDiscountPct(acWashQty);
  int    get acDiscountAmt => (acWashSubtotal * acDiscountPct).round();

  // ✅ ສູດ: (ລາຄາລ້າງທັງໝົດ × (1 - %ສ່ວນຫຼຸດ)) + Add-on (ເຕີມນ້ຳຢາ/ຍ້າຍແອ)
  int get acCartTotal => (acWashSubtotal - acDiscountAmt) + acAddonSubtotal;

  bool get acHasRefill =>
      acCart.any((i) => i.type == AcServiceType.refill);

  // ✅ ລາຄາ "preview" ຂອງລາຍການກຳລັງເລືອກ (ຍັງບໍ່ໄດ້ກົດ "ເພີ່ມລົງລາຍການ") —
  // ໃຫ້ຕົວເລກລາຄາລວມອັບເດດທັນທີ ບໍ່ຕ້ອງລໍຖ້າກົດເພີ່ມລົງລາຍການກ່ອນ
  int get acDraftPrice => acDraftType == null
      ? 0
      : AppPricing.acUnitPrice(acDraftType!, acDraftBtu) * acDraftQty;

  // ✅ ລາຄາລວມທີ່ສະແດງຢູ່ແຖບລຸ່ມໃນລະຫວ່າງເລືອກ — ລາຍການໃນກະຕ່າ + preview ລາຍການກຳລັງເລືອກ
  int get acDisplayTotal => acCartTotal + acDraftPrice;

  // ✅ ບໍລິການເສີມ (ຮີດເຄື່ອງ/ຕູ້ເຢັນ/ຕູ້ອົບ/ກະຈົກ) — ສຳລັບໜ້າທຳຄວາມສະອາດທົ່ວໄປ
  int get addonTotal => addonServices.fold(0, (s, id) {
    final item = AppPricing.addonItems[id];
    if (item == null) return s; // ✅ safe — skip unknown keys
    return s + (item['price'] as int);
  });

  int get serviceTotal {
    switch (category) {
      case ServiceCategory.acCleaning:
        return acCartTotal;

      case ServiceCategory.homeCleaning:
        if (cleanType == HomeCleaningType.general) {
          if (priceMode == PriceMode.hourly) return AppPricing.calcCleanHourly(hours) + addonTotal;
          if (priceMode == PriceMode.room && roomType != null) {
            // ✅ [FIX-2] safe lookup — ບໍ່ໃຊ້ ! bang operator
            final roomData = AppPricing.cleanRoomPrices[roomType];
            if (roomData == null) return addonTotal;
            return (roomData['min'] ?? 0) + addonTotal;
          }
        }
        if (cleanType == HomeCleaningType.deep) {
          return AppPricing.calcDeepSqm(sqm, isPostConstruct);
        }
        if (cleanType == HomeCleaningType.specialist) {
          final qtyTotal = specialistQty.entries.fold(0, (sum, e) {
            if (e.key == 'pest') return sum; // ✅ pest ຄິດເປັນຕາແມັດ ບໍ່ແມ່ນ qty
            final item = AppPricing.specialistItems[e.key];
            if (item == null) return sum; // ✅ [FIX-2] safe — skip unknown keys
            return sum + (item['min'] as int) * e.value;
          });
          final pestTotal = (pestSqm * AppPricing.pestSqmMin).round();
          return qtyTotal + pestTotal;
        }
        return 0;
    }
  }

  int get travelFeeAmt => hasTravelFee ? AppPricing.travelFee : 0;
  int get grandTotal   => serviceTotal + travelFeeAmt;

  // ✅ AC ດຽວນີ້ສະແດງລາຄາສຸດທິໄດ້ສະເໝີ (ລາຍການເຕີມນ້ຳຢາໃຊ້ລາຄາປະມານຂັ້ນຕ່ຳ) —
  // isQuote ຈຶ່ງເຫຼືອພຽງກໍລະນີ "ເໝົາຕາມຫ້ອງ" ທີ່ບໍ່ໄດ້ເລືອກຂະໜາດ
  bool get isQuote =>
      category == ServiceCategory.homeCleaning &&
      cleanType == HomeCleaningType.general &&
      priceMode == PriceMode.room &&
      roomType == null;

  // 🔒 [AUDIT CUST-1 / 2026-08-02 — High, fresh re-audit] ກ່ອນໜ້ານີ້ໃຊ້
  // grandTotal (ລາຄາກ່ອນຫັກສ່ວນຫຼຸດ) — ຖ້າລູກຄ້າໃສ່ຄູປອງ, Bill Card ຂ້າງເທິງ
  // (ໃຊ້ discountedTotal ຢູ່ແລ້ວ) ແລະ ຄ່າທີ່ບັນທຶກລົງ Firestore ('price':
  // discountedTotal, ເບິ່ງ toFirestore() ຂ້າງລຸ່ມ) ຈະບໍ່ກົງກັບຈຳນວນທີ່ QR ນີ້ບອກ
  // ໃຫ້ໂອນ — ລູກຄ້າຖືກບອກໃຫ້ໂອນຫຼາຍກວ່າລາຄາຈິງ. ໃຊ້ discountedTotal ດຽວກັນນຳ.
  String get bcelQrData =>
      'BCEL|LINTHO|LAK|${discountedTotal.round()}|LinTho Service';

  Map<String, dynamic> toFirestore(
      String userId, String userName, String phone) {
    final now = DateTime.now();
    // 🔒 [AUDIT CUST-1 / 2026-08-06] ເອີ້ນຢ່າງຈະແຈ້ງກ່ອນອ່ານ couponCode/
    // couponDiscount ຂ້າງລຸ່ມ — ບໍ່ອີງໃສ່ລຳດັບການປະເມີນ map literal
    // (discountedTotal ຖືກເອີ້ນຢູ່ໃນ map ນຳ, ແຕ່ການເອີ້ນຊ້ຳຢູ່ນີ້ຮັບປະກັນຄວາມ
    // ຖືກຕ້ອງເຖິງແມ່ນຈະມີໃຜປ່ຽນລຳດັບ field ໃນ map ໃນອະນາຄົດ).
    _invalidateStaleCoupon();
    return {
      'customerId':    userId,
      'customerName':  userName,
      'customerPhone': phone,
      // ✅ [Phone-verified booking] 'contactPhone' — ເບີໂທຢືນຢັນແລ້ວຂອງບັນຊີ
      // (ເບິ່ງ phone_verification.dart), ຄືເບີດຽວກັນກັບ customerPhone ຂ້າງເທິງ
      // ຢູ່ໃນ path ນີ້ (customerPhone ຄົງໄວ້ເພື່ອ backward-compat ກັບ code
      // ເກົ່າ/admin dashboard ທີ່ຍັງອ່ານ field ນັ້ນ) — ຝັ່ງຊ່າງອ່ານ contactPhone
      'contactPhone':  phone,
      'category':      category.key,
      // ✅ [FIX CR-1] 'location' GeoPoint — Booking.fromFirestore ອ່ານ field ນີ້
      // ເທົ່ານັ້ນ (ບໍ່ອ່ານ lat/lng ແຍກ), ຂາດມັນເຮັດໃຫ້ຊ່າງນຳທາງໄປພິກັດ (0,0)
      'location':      GeoPoint(lat, lng),
      // ✅ [FIX HI-4] 'serviceType' — Cloud Functions (onNewBooking,
      // onBookingStatusChange, cleanupExpiredBookings) ອ່ານ field ນີ້ໂດຍກົງ
      // ບໍ່ມີ fallback; ບໍ່ໃສ່ຈະເຮັດໃຫ້ notification ສະແດງ "undefined".
      // ໃຊ້ຄ່າດຽວກັນກັບ category.key ເພາະນີ້ຄື canonical key ທີ່
      // provider matching (unassignedOpenJobsProvider) ກໍ່ໃຊ້ຢູ່ແລ້ວ.
      'serviceType':   category.key,
      if (category == ServiceCategory.acCleaning) ...{
        'acCart': acCart.map((i) => {
          'type':      i.type.name,
          'btuSize':   i.btuSize.name,
          'qty':       i.qty,
          'unitPrice': AppPricing.acUnitPrice(i.type, i.btuSize),
        }).toList(),
        'acQty':          acCart.fold(0, (s, i) => s + i.qty),
        'acWashQty':      acWashQty,
        'acDiscountPct':  acDiscountPct,
        'acDiscountAmt':  acDiscountAmt,
      },
      if (category == ServiceCategory.homeCleaning) ...{
        'cleanType':       cleanType?.name,
        'priceMode':       priceMode?.name,
        'hours':           hours,
        'roomType':        roomType,
        'sqm':             sqm,
        'isPostConstruct': isPostConstruct,
        'specialistItems': specialistQty,
        'pestSqm':         pestSqm,
        'addonServices':   addonServices.toList(),
        'addonTotal':      addonTotal,
        'maidNotes':       maidNotes,
      },
      'scheduledAt': isNow
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(scheduledAt ?? now),
      'isNow':         isNow,
      'address':       address,
      'landmark':      landmark,
      'specialInstructions': specialInstructions,
      'jobPhotoUrl':   jobPhotoUrl,
      'lat':           lat,
      'lng':           lng,
      'distanceKm':    distanceKm,
      'serviceTotal':  serviceTotal,
      'travelFee':     travelFeeAmt,
      'grandTotal':    grandTotal,
      // ✅ [FIX] admin dashboard revenue (ແລະ Booking.fromFirestore) ອ່ານ
      // field 'price' — Path A (booking form ຫຼັກ) ບໍ່ມີ field ນີ້ມາກ່ອນ,
      // booking ປະເພດນີ້ຈິ່ງບໍ່ຖືກນັບໃນ revenue. ເພີ່ມແບບ additive,
      // ບໍ່ລຶບ serviceTotal/grandTotal ເກົ່າ. ໃຊ້ `discountedTotal` (ຫັກ
      // coupon ແລ້ວ) ເພາະນີ້ຄືຍອດທີ່ລູກຄ້າຈ່າຍຈິງ.
      'price':         discountedTotal,
      if (couponCode != null) 'couponCode': couponCode,
      if (couponDiscount != null) 'discountAmount': couponDiscount,
      'paymentMethod': paymentMethod,
      'paymentStatus': 'pending',
      'clientRequestId': clientRequestId,
      'status':        'pending',
      'reviewed':      false,
      'createdAt':     FieldValue.serverTimestamp(),
      // ✅ [FIX-3] ໃຊ້ client time ສຳລັບ expiresAt ເພາະ Firestore
      // ບໍ່ support serverTimestamp() + offset ໂດຍກົງ.
      // ວິທີທີ່ດີທີ່ສຸດຄືໃຊ້ Cloud Function — ແຕ່ client time
      // ແມ່ນ acceptable ສຳລັບ use case ນີ້.
      // ຖ້າຕ້ອງການ server-accurate: ໃຊ້ Cloud Function trigger.
      'expiresAt': Timestamp.fromDate(
          now.add(const Duration(minutes: 10))),
    };
  }
}

// ════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════

class BookingFormScreen extends ConsumerStatefulWidget {
  final String?        providerId;
  final BookingOrder?  initialOrder;
  final int            initialStep;
  const BookingFormScreen({
    super.key, this.providerId,
    this.initialOrder, this.initialStep = 0,
  });

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {

  late int      _step;
  BookingOrder? _order;
  bool          _loading = false;
  bool          _uploadingPhoto = false;
  // ✅ [FIX ME-12] track ວ່າ live pricing (loadLive()) resolve ແລ້ວບໍ່ — ໃຊ້
  // gate ບໍ່ໃຫ້ submit ກ່ອນລາຄາຫຼ້າສຸດຈາກ admin ຖືກໂຫລດ
  bool          _pricingLoaded = false;

  // ✅ RULE: dispose() ທຸກ controller
  final _addressCtrl   = TextEditingController();
  final _landmarkCtrl  = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _sqmCtrl       = TextEditingController();
  final _maidNotesCtrl = TextEditingController();

  static List<String> get _stepLabels => [
    tr('step_label_service'), tr('price'), tr('step_label_schedule'),
    tr('address'), tr('step_label_payment'),
  ];

  // ✅ [Premium redesign / Batch 3 / P1-1] step-progress indicator — reuses
  // the existing shared StatusStepper widget, sourced from the same _step +
  // _stepLabels already driving the AppBar title. Presentation only: reads
  // _step, introduces no new state, does not touch step-transition logic.
  static List<StatusStep> get _progressSteps => [
    StatusStep(icon: Icons.category_rounded, label: tr('step_label_service')),
    StatusStep(icon: Icons.tune_rounded, label: tr('price')),
    StatusStep(icon: Icons.calendar_today_rounded, label: tr('step_label_schedule')),
    StatusStep(icon: Icons.location_on_rounded, label: tr('address')),
    StatusStep(icon: Icons.payment_rounded, label: tr('step_label_payment')),
  ];

  // ✅ [Phone-verified booking] ເບີໂທຢືນຢັນແລ້ວຂອງບັນຊີ — ອ່ານແຕ່ຄ່ານີ້, ບໍ່ຮັບ
  // ການພິມມືອີກຕໍ່ໄປ (ເບິ່ງ phone_verification.dart). ໜ້ານີ້ຖືກຫຸ້ມດ້ວຍ
  // PhoneRequiredGate ຢູ່ build() ຢູ່ແລ້ວ ດັ່ງນັ້ນຄ່ານີ້ຄວນບໍ່ວ່າງສະເໝີເມື່ອຮອດ
  // ຈຸດນີ້ — getter ຄືນ '' ເປັນ defense-in-depth ເທົ່ານັ້ນ
  String get _verifiedPhone => verifiedPhoneNumber() ?? '';

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _step  = widget.initialStep;
    _loadLivePricing();
  }

  // ▸ [LIVE PRICING] ດຶງ TIERED pricing ຈາກ admin (Firestore) ມາທັບ
  // `AppPricing` static defaults — ເບິ່ງລາຍລະອຽດ key convention ຢູ່
  // `AppPricing.loadLive()`. ບໍ່ throw; ຖ້າ fetch ບໍ່ສຳເລັດ ລາຄາ default
  // ຍັງໃຊ້ໄດ້ປົກກະຕິ. setState() ຫຼັງ fetch ສຳເລັດ ເພື່ອ rebuild ດ້ວຍລາຄາໃໝ່.
  Future<void> _loadLivePricing() async {
    await AppPricing.loadLive();
    // ✅ [FIX ME-12] AppPricing.loadLive() ບໍ່ throw ເດັດຂາດ (ຫຸ້ມ try/catch
    // ໝົດແລ້ວ), ດັ່ງນັ້ນ _pricingLoaded ຈະຖືກຕັ້ງ true ສະເໝີບໍ່ວ່າ fetch
    // ຈະສຳເລັດ ຫຼື fallback ໄປໃຊ້ຄ່າ default — ຈຸດປະສົງແມ່ນພຽງແຕ່ບໍ່ໃຫ້ຜູ້ໃຊ້
    // submit ກ່ອນຮອບ fetch ນີ້ resolve (ຄ່າອາດປ່ຽນຈາກ default ເປັນ live ລະຫວ່າງ
    // ນັ້ນ), ບໍ່ແມ່ນການລໍຖ້າໃຫ້ fetch "ສຳເລັດ" ໂດຍສະເພາະ.
    if (mounted) setState(() => _pricingLoaded = true);
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _landmarkCtrl.dispose();
    _instructionsCtrl.dispose();
    _sqmCtrl.dispose();
    _maidNotesCtrl.dispose();
    super.dispose();
  }

  // ✅ ລາຄາລວມສະແດງຢູ່ແຖບລຸ່ມ — ໃນຂັ້ນຕອນ AC ໃຫ້ລວມ preview ຂອງລາຍການກຳລັງເລືອກນຳ
  // (ກ່ອນກົດ "ເພີ່ມລົງລາຍການ") ເພື່ອບໍ່ໃຫ້ຕົວເລກຄ້າງ 0 ກີບ
  int get _displayTotal {
    final o = _order!;
    if (_step == 1 && o.category == ServiceCategory.acCleaning) {
      return o.acDisplayTotal + o.travelFeeAmt;
    }
    return o.grandTotal;
  }

  // ── can proceed? ─────────────────────────────────────────
  bool get _canNext {
    switch (_step) {
      case 0: return _order != null;
      case 1:
        final o = _order!;
        bool packageSelected;
        if (o.category == ServiceCategory.acCleaning) {
          packageSelected = o.acCart.isNotEmpty; // ✅ ຕ້ອງມີຢ່າງໜ້ອຍ 1 ລາຍການໃນກະຕ່າ
        } else if (o.cleanType == HomeCleaningType.general) {
          if (o.priceMode == PriceMode.hourly) {
            packageSelected = o.hours >= 2;
          } else if (o.priceMode == PriceMode.room) {
            packageSelected = o.roomType != null;
          } else {
            packageSelected = false;
          }
        } else if (o.cleanType == HomeCleaningType.deep) {
          packageSelected = o.sqm >= AppPricing.deepSqmMin &&
              o.sqm <= AppPricing.deepSqmMax;
        } else if (o.cleanType == HomeCleaningType.specialist) {
          packageSelected = o.specialistQty.values.any((v) => v > 0) || o.pestSqm > 0;
        } else {
          packageSelected = false;
        }
        // ✅ ປຸ່ມ "ຕໍ່ໄປ" ຕ້ອງ disable ຖ້າຍັງບໍ່ໄດ້ເລືອກແພັກເກດ ຫຼື ລາຄາລວມເທົ່າກັບ 0
        return packageSelected && o.serviceTotal > 0;
      case 2: return _order!.isNow || _order!.scheduledAt != null;
      case 3:
        if (_order!.address.trim().length < 5) return false;
        // ✅ [FIX ME-10] ຄ່ອຍໆບັງຄັບແຕ່ທີ່ຢູ່ພິມມືເອງ (ບໍ່ແມ່ນ GPS) ຕ້ອງມີເລກ
        // ຢ່າງໜ້ອຍ 1 ໂຕ (ບ້ານເລກທີ/ຮ່ອມ) — ກັນຂໍ້ຄວາມທີ່ບໍ່ມີຄວາມໝາຍເຊັ່ນ "aaaaa"
        if (!_order!.isGpsAddress &&
            !RegExp(r'\d').hasMatch(_order!.address)) {
          return false;
        }
        // ✅ [Phone-verified booking] defense-in-depth — ໜ້ານີ້ຖືກ
        // PhoneRequiredGate ຫຸ້ມຢູ່ແລ້ວ, ຄ່ານີ້ຄວນບໍ່ວ່າງສະເໝີ
        if (_verifiedPhone.isEmpty) return false;
        return true;
      // ✅ [FIX ME-12] ບໍ່ໃຫ້ submit ກ່ອນ live pricing fetch resolve — ກັນ
      // ກໍລະນີຜູ້ໃຊ້ໄວກົດຈົນຮອດ submit ກ່ອນລາຄາຫຼ້າສຸດຈາກ admin ຖືກໂຫລດ
      case 4: return _pricingLoaded;
      default: return false;
    }
  }

  // ✅ [Premium redesign / Batch 3 / P1-2] presentation-only hint explaining
  // why the primary CTA is disabled — reads the same conditions `_canNext`
  // already evaluates (does not modify `_canNext`, does not add new
  // validation, does not change eligibility). Returns null when the CTA is
  // valid (hint disappears) or on a step whose gate doesn't have a single
  // clear blocking reason worth surfacing.
  String? get _nextBlockedReason {
    if (_canNext) return null;
    switch (_step) {
      case 1:
        final o = _order!;
        if (o.category == ServiceCategory.acCleaning) {
          return tr('booking_hint_select_ac_package');
        }
        if (o.cleanType == HomeCleaningType.general &&
            o.priceMode == PriceMode.hourly) {
          return tr('booking_hint_select_hours');
        }
        if (o.cleanType == HomeCleaningType.general &&
            o.priceMode == PriceMode.room) {
          return tr('booking_hint_select_room_type');
        }
        if (o.cleanType == HomeCleaningType.deep) {
          return tr('booking_hint_enter_sqm');
        }
        if (o.cleanType == HomeCleaningType.specialist) {
          return tr('booking_hint_select_specialist_service');
        }
        return tr('booking_hint_select_package');
      case 3:
        if (_order!.address.trim().length < 5) {
          return tr('booking_hint_enter_address');
        }
        if (!_order!.isGpsAddress &&
            !RegExp(r'\d').hasMatch(_order!.address)) {
          return tr('booking_hint_address_needs_number');
        }
        return null; // ✅ verifiedPhone-empty branch is defense-in-depth only
                     // (PhoneRequiredGate already blocks build() before this)
      case 4:
        if (!_pricingLoaded) return tr('booking_hint_loading_price');
        return null;
      default:
        return null;
    }
  }

  // ── submit ───────────────────────────────────────────────
  Future<void> _submit() async {
    if (_order == null) return;
    // ✅ [FIX ME-17] method-level guard — defense-in-depth ນອກເໜືອຈາກ
    // button-level `!isLoading` check ຢູ່ _BottomBar (ບໍ່ອີງໃສ່ widget rebuild
    // timing ຝ່າຍດຽວ)
    if (_loading) return;

    // ✅ [FIX ME-18] ກ່ອນໜ້ານີ້ບໍ່ໄດ້ກວດ currentUser == null ກ່ອນສົ່ງ booking —
    // ຖ້າ session ໝົດອາຍຸກາງທາງ, write ຈະຖືກ reject ຈາກ firestore.rules ແລ້ວ
    // ສະແດງ raw exception ທີ່ອ່ານບໍ່ຮູ້ເລື່ອງ. ຕອນນີ້ກວດກ່ອນ ແລະ ສະແດງຂໍ້ຄວາມ
    // ຊັດເຈນ ຄືກັນກັບ quick_booking_screen.dart's _confirm().
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('please_login_first'))));
      return;
    }
    // ✅ [Phone-verified booking] defense-in-depth — ໜ້ານີ້ຖືກ
    // PhoneRequiredGate ຫຸ້ມຢູ່ແລ້ວ ແຕ່ກວດຄືນກ່ອນ write ຈິງ
    if (_verifiedPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('phone_verification_required_title'))));
      return;
    }

    // 🔒 [PHASE0 P1] ກ່ອນໜ້ານີ້ໜ້ານີ້ບໍ່ເຄີຍກວດ provider.isOnline ເລີຍ — ລູກຄ້າ
    // ສາມາດ submit booking ໃຫ້ຊ່າງທີ່ offline ໄດ້ໂດຍບໍ່ມີການເຕືອນ. ກວດສົດຈາກ
    // Firestore ຢູ່ນີ້ (ບໍ່ອີງໃສ່ຄ່າ isOnline ຕອນເປີດໜ້າ, ອາດຫຼ້າສະໄໝແລ້ວ) —
    // ໃຊ້ພຽງແຕ່ເມື່ອເປັນການຈອງ provider ສະເພາະ (providerId != null); ການຈອງ
    // ແບບ "ຊອກຊ່າງອັດຕະໂນມັດ" (providerId == null → match_screen.dart) ບໍ່ກ່ຽວ.
    if (widget.providerId != null) {
      final provider = await FirestoreService().getProvider(widget.providerId!);
      if (!mounted) return;
      if (provider != null && !provider.isOnline) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('provider_offline_choose_another')),
          backgroundColor: C.orange,
        ));
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final data = _order!.toFirestore(
        user.uid,
        user.displayName ?? tr('customer'),
        _verifiedPhone,
      );
      if (widget.providerId != null) data['providerId'] = widget.providerId;

      final bookingId = await ref
          .read(createBookingNotifierProvider.notifier)
          .submit(data, couponCode: _order!.couponCode);

      if (!mounted) return;
      setState(() => _loading = false);

      if (bookingId == null) {
        final err = ref.read(createBookingNotifierProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr("error")}: $err'),
          backgroundColor: C.red,
        ));
        return;
      }

      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => MatchScreen(bookingId: bookingId),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // ✅ [FIX-1] ແທນ tr("error") ດ້ວຍ Lao string ໂດຍກົງ
      // — ປອດໄພກວ່າ: ບໍ່ຂຶ້ນກັບ app_locale.dart
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tr("error")}: $e'),
        backgroundColor: C.red,
      ));
    }
  }

  // ✅ ຖ້າ permission ໄດ້ໃຫ້ໄວ້ແລ້ວ — ດຶງທີ່ຢູ່ໃຫ້ອັດຕະໂນມັດ ບໍ່ໃຫ້ຕ້ອງກົດປຸ່ມເອງ.
  // ບໍ່ prompt permission ໃໝ່ ແລະ ບໍ່ overwrite ຖ້າຜູ້ໃຊ້ພິມທີ່ຢູ່ໄປແລ້ວ.
  Future<void> _autoGpsIfGranted() async {
    if (_order == null || _order!.address.isNotEmpty) return;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
      await _useGps();
    }
  }

  // ── GPS ──────────────────────────────────────────────────
  Future<void> _useGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('enable_gps_first')),
          backgroundColor: C.orange,
        ));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('gps_blocked')),
          backgroundColor: C.orange,
        ));
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      const centerLat = 17.9667;
      const centerLng = 102.6000;
      final dist = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, centerLat, centerLng) /
          1000;

      // ✅ ດຶງຊື່ສະຖານທີ່ທີ່ອ່ານໄດ້ — fallback ເປັນພິກັດດິບຖ້າ reverse geocode ບໍ່ໄດ້
      var addr =
          'GPS: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      try {
        final places = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (places.isNotEmpty) {
          final p = places.first;
          addr = [p.street, p.subLocality, p.locality]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
          if (addr.isEmpty) {
            addr = 'GPS: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
          }
        }
      } catch (_) {
        // best-effort — ໃຊ້ພິກັດດິບເປັນ fallback
      }
      if (!mounted) return;

      setState(() {
        _order!
          ..lat          = pos.latitude
          ..lng          = pos.longitude
          ..distanceKm   = dist
          ..address      = addr
          ..isGpsAddress = true;
        _addressCtrl.text = addr;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tr("gps_error")}: $e'),
        backgroundColor: C.red,
      ));
    }
  }

  // ── ຮູບໜ້າວຽກ (ທາງເລືອກ) ──────────────────────────────────
  Future<void> _pickJobPhoto(BookingOrder o) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: C.border, borderRadius: BorderRadius.circular(AppRadius.chip)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: C.primary),
            title: Text(tr('take_photo')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined, color: C.primary),
            title: Text(tr('choose_from_gallery')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: AppSpacing.sm),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    try {
      // ✅ [FIX ME-2] ເພີ່ມ maxWidth/maxHeight — imageQuality ຄວບຄຸມສະເພາະລະດັບ
      // JPEG compression ບໍ່ຄວບຄຸມຄວາມລະອຽດ (pixel), ຮູບຈາກກ້ອງມືຖືສະໄໝໃໝ່ຈຶ່ງ
      // ຍັງອັບໂຫລດຂະໜາດໃຫຍ່ຫຼາຍ MB ຢູ່ໄດ້ຖ້າບໍ່ຈຳກັດ dimension ນຳ
      final picked = await ImagePicker().pickImage(
          source: source, imageQuality: 80, maxWidth: 1600, maxHeight: 1600);
      if (picked == null || !mounted) return;

      setState(() => _uploadingPhoto = true);
      final url = await CloudinaryService.instance.uploadImage(
          File(picked.path), folder: 'bookings/jobPhotos/${o.clientRequestId}');
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        if (url != null) o.jobPhotoUrl = url;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tr("upload_failed")}: $e'),
        backgroundColor: C.red,
      ));
    }
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // ✅ [Phone-verified booking] ບໍ່ອະນຸຍາດໃຫ້ຈອງຖ້າບັນຊີຍັງບໍ່ມີ/ຍັງບໍ່ໄດ້
    // ຢືນຢັນເບີໂທ — ເບິ່ງ phone_verification.dart
    if (_verifiedPhone.isEmpty) {
      return PhoneRequiredGate(
          onGoToProfile: () => goToProfileTab(context, ref));
    }
    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: C.primary, size: 20),
          tooltip: tr('back_semantic'),
          onPressed: () {
            if (_step > 0) setState(() => _step--);
            else Navigator.pop(context);
          },
        ),
        // ✅ [Phase 2 / Batch B] matches AppTypography.appBarTitle's shape
        // (18/w800) exactly — only the brand-green color is a deliberate
        // override vs. the app-wide default ink app-bar title.
        title: Text(_stepLabels[_step],
            style: AppTypography.appBarTitle.copyWith(color: C.primary)),
        centerTitle: true,
        // ✅ [Premium redesign / Batch 3 / P1-1] step-progress indicator
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
            child: StatusStepper(
              steps: _progressSteps,
              currentIndex: _step,
              activeColor: C.primary,
            ),
          ),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            // ✅ [Premium redesign / Batch 3 / P2-5] 20 → AppSpacing.xl(24)
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: switch (_step) {
              0 => _buildStep0(),
              1 => _buildStep1(),
              2 => _buildStep2(),
              3 => _buildStep3(),
              _ => _buildStep4(),
            },
          ),
        ),
        if (_step > 0)
          _BottomBar(
            step:      _step,
            isLast:    _step == 4,
            canNext:   _canNext,
            isLoading: _loading,
            estimatedTotal: _order != null && _step >= 1 ? _displayTotal : null,
            showCleaningDisclaimer: _order?.category == ServiceCategory.homeCleaning,
            blockedReason: _nextBlockedReason,
            onNext: () {
              if (_step == 4) {
                _submit();
              } else {
                final nextStep = _step + 1;
                setState(() => _step = nextStep);
                if (nextStep == 3) _autoGpsIfGranted();
              }
            },
          ),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════
  //  STEP 0 — ເລືອກໝວດ
  // ════════════════════════════════════════════════════════

  void _quickBookAc() {
    setState(() {
      _order = BookingOrder(category: ServiceCategory.acCleaning)
        ..acCart.add(AcCartItem(
            type: AcServiceType.standard, btuSize: AcBtuSize.small, qty: 1));
      _step = 2;
    });
  }

  void _quickBookCleaning() {
    setState(() {
      _order = BookingOrder(category: ServiceCategory.homeCleaning)
        ..cleanType = HomeCleaningType.general
        ..priceMode = PriceMode.hourly
        ..hours     = 2;
      _step = 2;
    });
  }

  Widget _buildStep0() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label(tr('label_popular_packages'), sub: tr('sub_popular_packages')),
      const SizedBox(height: AppSpacing.md),
      Row(children: [
        Expanded(child: _QuickBookCard(
          icon: Icons.ac_unit_outlined, title: tr('quickbook_ac_title'), sub: '${tr("quickbook_ac_sub")} ${AppPricing.fmt(AppPricing.acStdPrice[AcBtuSize.small]!)} ${tr("kip_currency")}',
          color: C.categoryAcBg, accent: C.categoryAcAccent,
          badge: tr('quickbook_ac_badge'),
          onTap: _quickBookAc,
        )),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _QuickBookCard(
          icon: Icons.cleaning_services_outlined, title: tr('svc_house_clean'), sub: '${tr("quickbook_cleaning_sub")} ${AppPricing.fmt(AppPricing.calcCleanHourly(2))} ${tr("kip_currency")}',
          color: C.categoryCleanBg, accent: C.categoryCleanAccent,
          onTap: _quickBookCleaning,
        )),
      ]),
      const SizedBox(height: AppSpacing.xl),
      _Label(tr('label_or_choose_category'), sub: tr('sub_other_needs')),
      const SizedBox(height: 20),
      _BigCatCard(
        icon: Icons.ac_unit_outlined, title: tr('svc_ac_clean'), sub: tr('cat_ac_sub'),
        note: tr('bigcat_ac_note'),
        bullets: [tr('ac_type_general_wash'), tr('bigcat_ac_bullet_deep'), tr('ac_type_refill')],
        color: C.categoryAcBg, accent: C.categoryAcAccent,
        selected: _order?.category == ServiceCategory.acCleaning,
        onTap: () => setState(() {
          _order = BookingOrder(category: ServiceCategory.acCleaning);
          _step = 1;
        }),
      ),
      const SizedBox(height: AppSpacing.lg),
      _BigCatCard(
        icon: Icons.cleaning_services_outlined, title: tr('svc_house_clean'), sub: tr('cat_house_sub'),
        note: tr('bigcat_house_note'),
        bullets: [tr('bigcat_house_bullet_general'), tr('bigcat_house_bullet_deep'), tr('bigcat_house_bullet_specialist')],
        color: C.categoryCleanBg, accent: C.categoryCleanAccent,
        selected: _order?.category == ServiceCategory.homeCleaning,
        onTap: () => setState(() {
          _order = BookingOrder(category: ServiceCategory.homeCleaning);
          _step = 1;
        }),
      ),
    ]);
  }

  // ════════════════════════════════════════════════════════
  //  STEP 1 — Package + ລາຄາ
  // ════════════════════════════════════════════════════════

  Widget _buildStep1() {
    if (_order!.category == ServiceCategory.acCleaning) return _buildAcStep();
    return _buildCleaningStep();
  }

  // ✅ ກະຕ່າສິນຄ້າ — ເພີ່ມລາຍການແອປະຈຸບັນ (ປະເພດ+ຂະໜາດ+ຈຳນວນ) ລົງລາຍການ
  // ຫາກມີລາຍການປະເພດ+ຂະໜາດດຽວກັນຢູ່ແລ້ວ ໃຫ້ລວມຈຳນວນເຂົ້າກັນ
  void _addAcDraftToCart(BookingOrder o) {
    final type = o.acDraftType;
    if (type == null) return;
    setState(() {
      final idx = o.acCart.indexWhere(
          (i) => i.type == type && i.btuSize == o.acDraftBtu);
      if (idx >= 0) {
        o.acCart[idx].qty += o.acDraftQty;
      } else {
        o.acCart.add(AcCartItem(
            type: type, btuSize: o.acDraftBtu, qty: o.acDraftQty));
      }
      o.acDraftType = null;
      o.acDraftBtu  = AcBtuSize.small;
      o.acDraftQty  = 1;
    });
  }

  Widget _buildAcStep() {
    final o = _order!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label(tr('label_choose_ac_type'), sub: tr('sub_choose_add_multi')),
      const SizedBox(height: 14),
      _AcTypeCard(type: AcServiceType.standard,
          selected: o.acDraftType == AcServiceType.standard,
          onTap: () => setState(() => o.acDraftType = AcServiceType.standard)),
      const SizedBox(height: 10),
      _AcTypeCard(type: AcServiceType.deepFull,
          selected: o.acDraftType == AcServiceType.deepFull,
          onTap: () => setState(() => o.acDraftType = AcServiceType.deepFull)),
      const SizedBox(height: 10),
      _AcTypeCard(type: AcServiceType.refill,
          selected: o.acDraftType == AcServiceType.refill,
          onTap: () => setState(() => o.acDraftType = AcServiceType.refill)),
      const SizedBox(height: 10),
      _AcTypeCard(type: AcServiceType.relocate,
          selected: o.acDraftType == AcServiceType.relocate,
          onTap: () => setState(() => o.acDraftType = AcServiceType.relocate)),

      if (o.acDraftType != null) ...[
        const SizedBox(height: 20),
        _Label(tr('label_ac_type_size')),
        const SizedBox(height: 10),
        _BtuSelector(
            selected: o.acDraftBtu,
            onChanged: (v) => setState(() => o.acDraftBtu = v)),
        const SizedBox(height: 20),
        _Label(tr('label_device_qty')),
        const SizedBox(height: 10),
        _QtyRow(
            qty: o.acDraftQty, minQty: 1, maxQty: 20, label: tr('unit_device'),
            onChanged: (v) => setState(() => o.acDraftQty = v)),

        const SizedBox(height: 14),
        _PriceInfoBox(color: C.categoryAcBg, lines: [
          _PriceLine(
            '${AppPricing.fmt(AppPricing.acUnitPrice(o.acDraftType!, o.acDraftBtu))} ${tr("kip_currency")} × ${o.acDraftQty} ${tr("unit_device")}',
            '${AppPricing.fmt(o.acDraftPrice)} ${tr("kip_currency")}',
            bold: true,
          ),
        ]),

        if (o.acDraftType == AcServiceType.relocate) ...[
          const SizedBox(height: 14),
          const _RelocateExtrasInfo(),
        ],
        if (o.acDraftType == AcServiceType.refill) ...[
          const SizedBox(height: 14),
          _RefillInfoCard(btuSize: o.acDraftBtu),
        ],

        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          // ✅ [FIX ME-8] revert ກັບ tinted-fill ElevatedButton ເດີມ — ຮູບແບບ
          // OutlinedButton ຂອບສີ primary ທີ່ໃຊ້ຢູ່ນີ້ບໍ່ກົງກັບທັງ convention
          // grey-outline (quick_booking_screen.dart) ຫຼື filled-primary
          // (ປຸ່ມ "Next" ຢູ່ໜ້າດຽວກັນ) — ແຂ່ງສາຍຕາກັບປຸ່ມ primary ແທ້
          child: ElevatedButton.icon(
            onPressed: () => _addAcDraftToCart(o),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.primary.withValues(alpha: 0.1),
              foregroundColor: C.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card)),
            ),
            icon: const Icon(Icons.add_circle_outline),
            label: Text(tr('add_to_list'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],

      if (o.acCart.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        _Label(tr('label_selected_items'), sub: tr('sub_adjust_qty_remove')),
        const SizedBox(height: 10),
        ...o.acCart.map((item) => _AcCartTile(
          item: item,
          onQtyChanged: (v) => setState(() => item.qty = v),
          onRemove: () => setState(() => o.acCart.remove(item)),
        )),
        const SizedBox(height: 14),
        _AcCartSummary(order: o),
      ],
    ]);
  }

  Widget _buildCleaningStep() {
    final o = _order!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label(tr('label_choose_type')),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _SmallTypeCard(
          icon: Icons.cleaning_services_outlined, title: tr('smalltype_general_title'),
          selected: o.cleanType == HomeCleaningType.general,
          onTap: () => setState(() {
            o.cleanType = HomeCleaningType.general;
            o.priceMode = null; o.roomType = null;
          }),
        )),
        const SizedBox(width: 10),
        Expanded(child: _SmallTypeCard(
          icon: Icons.auto_awesome_outlined, title: tr('smalltype_deep_title'),
          selected: o.cleanType == HomeCleaningType.deep,
          onTap: () => setState(() {
            o.cleanType = HomeCleaningType.deep;
            o.priceMode = PriceMode.sqm;
          }),
        )),
        const SizedBox(width: 10),
        Expanded(child: _SmallTypeCard(
          icon: Icons.chair_outlined, title: tr('smalltype_specialist_title'),
          selected: o.cleanType == HomeCleaningType.specialist,
          onTap: () => setState(() {
            o.cleanType = HomeCleaningType.specialist;
            o.priceMode = PriceMode.perUnit;
          }),
        )),
      ]),
      const SizedBox(height: AppSpacing.xl),

      // ── General ─────────────────────────────────────────
      if (o.cleanType == HomeCleaningType.general) ...[
        _Label(tr('label_pricing_mode'), sub: tr('sub_choose_format')),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(child: _ModeCard(
            title: tr('mode_hourly_title'), sub: tr('mode_hourly_sub'),
            selected: o.priceMode == PriceMode.hourly,
            onTap: () => setState(() { o.priceMode = PriceMode.hourly; o.roomType = null; }),
          )),
          const SizedBox(width: 10),
          Expanded(child: _ModeCard(
            title: tr('mode_room_title'), sub: tr('mode_room_sub'),
            selected: o.priceMode == PriceMode.room,
            onTap: () => setState(() => o.priceMode = PriceMode.room),
          )),
        ]),

        if (o.priceMode == PriceMode.hourly) ...[
          const SizedBox(height: 20),
          _Label(tr('label_hours_qty'), sub: tr('sub_min_2hrs')),
          const SizedBox(height: 10),
          _QtyRow(qty: o.hours, minQty: 2, maxQty: 12, label: tr('hours_unit'),
              onChanged: (v) => setState(() => o.hours = v)),
          const SizedBox(height: 14),
          _PriceInfoBox(color: C.categoryCleanBg, lines: [
            _PriceLine('${o.hours} ${tr("hours_unit")} × ${AppPricing.fmt(AppPricing.cleanHourMin)} ${tr("kip_currency")}',
                '${AppPricing.fmt(AppPricing.calcCleanHourly(o.hours))} ${tr("kip_currency")}', bold: true),
            _PriceLine(tr('price_line_estimate_note'), ''),
          ]),
        ],

        if (o.priceMode == PriceMode.room) ...[
          const SizedBox(height: 20),
          _Label(tr('label_room_size')),
          const SizedBox(height: 10),
          // ✅ [FIX ME-13] ກ່ອນໜ້ານີ້ minP/maxP ເປັນ literal ຄົງທີ່, ບໍ່ເຄີຍອ່ານ
          // ຈາກ AppPricing.cleanRoomPrices (ຄ່າດຽວກັນທີ່ serviceTotal ໃຊ້ຄິດເງິນ
          // ຈິງ) — ຮາຄາທີ່ສະແດງອາດບໍ່ກົງກັບຮາຄາທີ່ຄິດເງິນ ຖ້າ admin ປ່ຽນລາຄາຜ່ານ
          // loadLive(). ຕອນນີ້ອ່ານຈາກ AppPricing.cleanRoomPrices ໂດຍກົງ.
          ...[
            ('1bed', tr('room_1bed_title'), tr('room_1bed_sub')),
            ('2bed', tr('room_2bed_title'), tr('room_2bed_sub')),
          ].map((r) {
            final priceData = AppPricing.cleanRoomPrices[r.$1];
            return _RoomTile(
              id: r.$1, title: r.$2, sub: r.$3,
              minP: priceData?['min'] ?? 0, maxP: priceData?['max'] ?? 0,
              selected: o.roomType == r.$1,
              onTap: () => setState(() => o.roomType = r.$1),
            );
          }),

          // ── Add-on Services ───────────────────────────────
          const SizedBox(height: 20),
          _Label(tr('label_addon_services'), sub: tr('sub_multi_optional')),
          const SizedBox(height: 10),
          ...AppPricing.addonItems.entries.map((e) => _AddonCheckRow(
            id: e.key, data: e.value,
            checked: o.addonServices.contains(e.key),
            onChanged: (v) => setState(() {
              if (v) o.addonServices.add(e.key);
              else o.addonServices.remove(e.key);
            }),
          )),

          // ── Notes for maid ─────────────────────────────────
          const SizedBox(height: 20),
          _Label(tr('label_notes_to_maid'), sub: tr('sub_optional')),
          const SizedBox(height: 10),
          TextField(
            controller: _maidNotesCtrl,
            onChanged: (v) => setState(() => o.maidNotes = v),
            maxLines: 3,
            maxLength: 300, // ✅ [FIX ME-11]
            decoration: InputDecoration(
              hintText:  tr('hint_maid_notes'),
              hintStyle: AppTypography.caption,
              counterText: '',
              filled: true, fillColor: C.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: const BorderSide(color: C.primary, width: 1.5)),
            ),
          ),

          const SizedBox(height: 10),
          Text(
            tr('cleaning_price_disclaimer'),
            style: AppTypography.caption,
          ),
        ],
      ],

      // ── Deep ─────────────────────────────────────────────
      if (o.cleanType == HomeCleaningType.deep) ...[
        _Label(tr('label_deep_clean_type')),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(child: _ModeCard(
            title: tr('mode_movein_title'), sub: tr('mode_movein_sub'),
            selected: !o.isPostConstruct,
            onTap: () => setState(() => o.isPostConstruct = false),
          )),
          const SizedBox(width: 10),
          Expanded(child: _ModeCard(
            title: tr('mode_postconstruct_title'), sub: tr('mode_postconstruct_sub'),
            selected: o.isPostConstruct,
            onTap: () => setState(() => o.isPostConstruct = true),
          )),
        ]),
        const SizedBox(height: 20),
        _Label(tr('label_area_sqm'), sub: tr('sub_min_50sqm')),
        const SizedBox(height: 10),
        _SqmInput(
          controller: _sqmCtrl,
          value:      o.sqm,
          minSqm:     AppPricing.deepSqmMin,
          onChanged: (v) => setState(() => o.sqm = v),
        ),
        if (o.sqm >= AppPricing.deepSqmMin) ...[
          const SizedBox(height: 14),
          _DeepBreakdown(order: o),
        ],
      ],

      // ── Specialist ───────────────────────────────────────
      if (o.cleanType == HomeCleaningType.specialist) ...[
        _Label(tr('label_choose_item'), sub: tr('sub_press_add_qty')),
        const SizedBox(height: AppSpacing.md),
        ...AppPricing.specialistItems.entries
            .where((e) => e.key != 'pest')
            .map((e) => _SpecialistRow(
          id: e.key, data: e.value,
          qty: o.specialistQty[e.key] ?? 0,
          onChanged: (v) => setState(() {
            if (v <= 0) o.specialistQty.remove(e.key);
            else o.specialistQty[e.key] = v;
          }),
        )),
        const SizedBox(height: AppSpacing.sm),
        _PestRow(
          sqm: o.pestSqm,
          onTap: () => _showPestSqmDialog(o),
          onClear: () => setState(() => o.pestSqm = 0),
        ),
        if (o.specialistQty.isNotEmpty || o.pestSqm > 0) ...[
          const SizedBox(height: 14),
          _SpecialistSummary(order: o),
        ],
      ],
    ]);
  }

  // ✅ ພົ່ນຢາຂ້າເຊື້ອ ຄິດເປັນຕາແມັດ — ໃຫ້ລະບຸແຍກຕ່າງຫາກຫຼັງກົດເລືອກ
  // ✅ [FIX ME-9] ກ່ອນໜ້ານີ້ປຸ່ມ OK ເປີດໃຫ້ກົດໄດ້ສະເໝີ ແລະ parse ຄ່າໂດຍບໍ່ກວດ —
  // ຮັບຄ່າ 0/ຕິດລົບໄດ້, ເຮັດໃຫ້ລາຄາລວມຫຼຸດລົງໂດຍບໍ່ມີການເຕືອນ. ຕອນນີ້ໃຊ້
  // StatefulBuilder ໃຫ້ reactive: disable OK ແລະ ສະແດງ error ຖ້າຄ່າ <= 0.
  Future<void> _showPestSqmDialog(BookingOrder o) async {
    final ctrl = TextEditingController(
        text: o.pestSqm > 0 ? o.pestSqm.toStringAsFixed(0) : '');
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final parsed  = double.tryParse(ctrl.text.trim());
          final hasError = ctrl.text.trim().isNotEmpty && (parsed == null || parsed <= 0);
          final canSubmit = parsed != null && parsed > 0;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: C.border, borderRadius: BorderRadius.circular(AppRadius.chip)),
              )),
              Text(tr('pest_spray_title'),
                  style: AppTypography.heading.copyWith(
                      fontSize: 16, fontWeight: FontWeight.w800, color: C.textPrimary)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${tr("pest_sqm_dialog_hint")} '
                '${AppPricing.fmt(AppPricing.pestSqmMin)}–${AppPricing.fmt(AppPricing.pestSqmMax)} ${tr("kip_currency")}/${tr("unit_sqm")}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setSheetState(() {}),
                decoration: InputDecoration(
                  hintText: tr('hint_pest_sqm'),
                  suffixText: tr('unit_sqm'),
                  errorText: hasError ? tr('pest_sqm_error_positive') : null,
                  filled: true, fillColor: C.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: const BorderSide(color: C.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: const BorderSide(color: C.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: const BorderSide(color: C.primary, width: 1.5)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: canSubmit ? () => Navigator.pop(ctx, parsed) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: C.border,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                  ),
                  child: Text(tr('ok'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          );
        },
      ),
    );
    if (result != null && mounted) setState(() => o.pestSqm = result);
  }

  // ════════════════════════════════════════════════════════
  //  STEP 2 — ນັດໝາຍ
  // ════════════════════════════════════════════════════════

  Widget _buildStep2() {
    final o = _order!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label(tr('label_choose_time')),
      const SizedBox(height: AppSpacing.lg),
      Row(children: [
        Expanded(child: _TimeToggle(
          icon: Icons.bolt_rounded, title: tr('now_option_title'), sub: '30–60 ${tr('minutes_unit')}',
          selected: o.isNow,
          onTap: () => setState(() { o.isNow = true; o.scheduledAt = null; }),
        )),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _TimeToggle(
          icon: Icons.event_outlined, title: tr('scheduled_option_title'), sub: tr('select_datetime'),
          selected: !o.isNow,
          onTap: () => setState(() => o.isNow = false),
        )),
      ]),

      if (o.isNow) ...[
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: C.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: C.primary.withValues(alpha: 0.18)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.bolt_rounded, color: C.primary, size: 20),
            const SizedBox(width: 10),
            // ✅ [Phase 2 / Batch B] 13/w600 is an exact match for
            // AppTypography.label; only the color override is bespoke.
            Expanded(child: Text(
              tr('now_eta_note'),
              style: AppTypography.label.copyWith(color: C.primary),
            )),
          ]),
        ),
      ],

      if (!o.isNow) ...[
        const SizedBox(height: 20),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(hours: 1)),
                firstDate:   DateTime.now(),
                lastDate:    DateTime.now().add(const Duration(days: 30)),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.light(primary: C.primary)),
                  child: child!,
                ),
              );
              if (!mounted || date == null) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.light(primary: C.primary)),
                  child: child!,
                ),
              );
              if (!mounted || time == null) return;
              final picked = DateTime(
                  date.year, date.month, date.day, time.hour, time.minute);
              // 🔒 [AUDIT CUST-1 / 2026-07-30] showDatePicker.firstDate ກັນວັນທີ
              // ໃນອະດີດໄດ້ ແຕ່ showTimePicker ບໍ່ມີຂອບເຂດຫຍັງເລີຍ — ຖ້າເລືອກວັນທີ
              // ມື້ນີ້ + ໂມງທີ່ຜ່ານໄປແລ້ວ, scheduledAt ຈະຢູ່ໃນອະດີດໄດ້ໂດຍບໍ່ມີການກວດ
              // ຈາກ client ຫຼື server (isValidNewBookingShape() ບໍ່ແຕະ scheduledAt).
              // ປະຕິເສດຢູ່ນີ້ແທນທີ່ຈະຍອມຮັບແລ້ວປ່ອຍໃຫ້ຊ່າງເຫັນວຽກ "ນັດ" ທີ່ໝົດເວລາໄປແລ້ວ.
              if (picked.isBefore(DateTime.now())) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr('past_scheduled_time_error')),
                    backgroundColor: C.red));
                return;
              }
              setState(() => o.scheduledAt = picked);
            },
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                    color: o.scheduledAt != null ? C.primary : C.border),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today,
                    color: o.scheduledAt != null ? C.primary : C.muted,
                    size: 20),
                const SizedBox(width: AppSpacing.md),
                Text(
                  o.scheduledAt != null
                      ? '${o.scheduledAt!.day.toString().padLeft(2, '0')}/'
                      '${o.scheduledAt!.month.toString().padLeft(2, '0')}/'
                      '${o.scheduledAt!.year}  '
                      '${o.scheduledAt!.hour.toString().padLeft(2, '0')}:'
                      '${o.scheduledAt!.minute.toString().padLeft(2, '0')}'
                      : tr('tap_to_select_datetime'),
                  style: TextStyle(
                      color: o.scheduledAt != null ? C.textPrimary : C.muted,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, color: C.muted),
              ]),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Label(tr('label_or_choose_timeslot'), sub: tr('sub_any_day')),
        const SizedBox(height: 10),
        // ✅ [FIX-4] ສ່ງ base date ເຂົ້າ widget — ບໍ່ let it recompute on each build
        _TimeSlots(
          baseDate: DateTime.now().add(const Duration(days: 1)),
          selected: o.scheduledAt,
          onSelected: (dt) => setState(() => o.scheduledAt = dt),
        ),
      ],
    ]);
  }

  // ════════════════════════════════════════════════════════
  //  STEP 3 — ທີ່ຢູ່
  // ════════════════════════════════════════════════════════

  Widget _buildStep3() {
    final o = _order!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label(tr('label_service_address')),
      const SizedBox(height: AppSpacing.lg),
      if (o.isGpsAddress)
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: C.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: C.primary.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            // ✅ ບ່ອນວາງ Mini Map Preview ໃນອະນາຄົດ
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: C.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: const Icon(Icons.map_outlined, color: C.primary, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('current_address_gps'),
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(o.address, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w700)),
              ],
            )),
            TextButton(
              onPressed: _useGps,
              style: TextButton.styleFrom(foregroundColor: C.primary),
              child: Text(tr('change'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        )
      else
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _useGps,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: C.primary.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.my_location, color: C.primary),
                const SizedBox(width: 10),
                Text(tr('use_current_address_gps'),
                    style: const TextStyle(
                        color: C.primary, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 14),
      TextField(
        controller: _landmarkCtrl,
        onChanged: (v) => setState(() => o.landmark = v),
        maxLength: 100, // ✅ [FIX ME-11]
        decoration: InputDecoration(
          hintText:  tr('hint_landmark'),
          hintStyle: AppTypography.caption,
          prefixIcon: const Icon(Icons.signpost_outlined, color: C.muted, size: 20),
          counterText: '',
          filled: true, fillColor: C.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.primary, width: 1.5)),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(tr('or_continue_with'), style: const TextStyle(color: C.muted))),
        const Expanded(child: Divider()),
      ]),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _addressCtrl,
        onChanged: (v) => setState(() {
          o.address      = v;
          o.isGpsAddress = false;
          o.distanceKm   = 0;
        }),
        maxLines: 3,
        maxLength: 200, // ✅ [FIX ME-11]
        decoration: InputDecoration(
          hintText:  tr('hint_manual_address'),
          hintStyle: AppTypography.caption,
          counterText: '',
          filled: true, fillColor: C.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.primary, width: 1.5)),
        ),
      ),
      if (o.address.isNotEmpty) ...[
        const SizedBox(height: 14),
        _TravelFeeBox(order: o),
      ],

      const SizedBox(height: 20),
      _Label(tr('label_notes_to_tech'), sub: tr('sub_optional')),
      const SizedBox(height: 10),
      TextField(
        controller: _instructionsCtrl,
        onChanged: (v) => setState(() => o.specialInstructions = v),
        maxLines: 3,
        maxLength: 300, // ✅ [FIX ME-11]
        decoration: InputDecoration(
          hintText:  tr('hint_notes_to_tech'),
          hintStyle: AppTypography.caption,
          counterText: '',
          filled: true, fillColor: C.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: const BorderSide(color: C.primary, width: 1.5)),
        ),
      ),

      const SizedBox(height: 20),
      _Label(tr('label_job_photo'), sub: tr('sub_optional_show_tech')),
      const SizedBox(height: 10),
      _JobPhotoPicker(
        photoUrl:   o.jobPhotoUrl,
        uploading:  _uploadingPhoto,
        onPick:     () => _pickJobPhoto(o),
        onRemove:   () => setState(() => o.jobPhotoUrl = ''),
      ),
    ]);
  }

  // ════════════════════════════════════════════════════════
  //  STEP 4 — ສະຫຼຸບ + ຊຳລະ
  // ════════════════════════════════════════════════════════

  Widget _buildStep4() {
    final o = _order!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ✅ [FIX ME-12] ໃຫ້ຜູ້ໃຊ້ຮູ້ວ່າເປັນຫຍັງປຸ່ມ "ຢືນຢັນ" ຍັງກົດບໍ່ໄດ້ (ຖ້າຍັງ
      // syncing) ແທນທີ່ຈະງຽບໆ disable ໂດຍບໍ່ອະທິບາຍ
      if (!_pricingLoaded) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: C.muted.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(children: [
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: C.muted),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('syncing_pricing_note'),
                style: AppTypography.caption)),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      _Label(tr('label_review_booking'), sub: tr('sub_check_before_confirm')),
      const SizedBox(height: AppSpacing.md),
      _BookingReviewCard(
        order: o,
        onEditService:  () => setState(() => _step = 1),
        onEditSchedule: () => setState(() => _step = 2),
        onEditAddress:  () => setState(() => _step = 3),
      ),
      const SizedBox(height: 20),

      _Label(tr('label_cost_summary')),
      const SizedBox(height: AppSpacing.md),
      _BillCard(order: o),
      const SizedBox(height: AppSpacing.md),
      _CouponBox(
        order: o,
        onChanged: () => setState(() {}),
      ),
      const SizedBox(height: 20),

      _Label(tr('label_payment_method')),
      const SizedBox(height: AppSpacing.md),
      _PaymentCard(
        // ✅ [FIX ME-7] icon override (ຄືກັນກັບ bcel ຂ້າງລຸ່ມ) — ບໍ່ດັ່ງນັ້ນ
        // build() ຈະ fallback ໄປໃຊ້ emoji ຕໍ່
        method: 'cash', emoji: '💵', icon: Icons.payments_outlined,
        title: tr('payment_cash_title'), sub: tr('payment_cash_sub'),
        selected: o.paymentMethod == 'cash',
        onTap: () => setState(() => o.paymentMethod = 'cash'),
      ),
      const SizedBox(height: 10),
      _PaymentCard(
        method: 'bcel', emoji: '📱', icon: Icons.qr_code_scanner_rounded,
        title: tr('payment_bcel_title'), sub: tr('payment_bcel_sub'),
        selected: o.paymentMethod == 'bcel',
        onTap: () => setState(() => o.paymentMethod = 'bcel'),
      ),

      if (o.paymentMethod == 'bcel') ...[
        const SizedBox(height: AppSpacing.lg),
        _BcelQrBox(order: o),
      ],

      const SizedBox(height: 20),

      if (o.category == ServiceCategory.acCleaning && o.acHasRefill) ...[
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: C.orange.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: C.orange.withValues(alpha: 0.3)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 🔒 [PHASE1] emoji → Icon
            const Icon(Icons.warning_amber_rounded, size: 16, color: C.orange),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(
              tr('refill_price_notice'),
              style: AppTypography.caption.copyWith(color: C.noteWarningText),
            )),
          ]),
        ),
        const SizedBox(height: AppSpacing.md),
      ],

      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: C.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: C.primary.withValues(alpha: 0.15)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: C.primary, size: 16),
          const SizedBox(width: AppSpacing.sm),
          // ✅ [Phase 2 / Batch B] fontSize matches AppTypography.caption.
          Expanded(child: Text(
            tr('dispatch_notice'),
            style: AppTypography.caption.copyWith(color: C.primary),
          )),
        ]),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: C.muted.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.policy_outlined, color: C.muted, size: 14),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(
            tr('cancellation_policy_notice'),
            style: AppTypography.caption.copyWith(fontSize: 10, color: C.mutedLight),
          )),
        ]),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════
//  BREAKDOWN WIDGETS
// ════════════════════════════════════════════════════════════

class _AcCartTile extends StatelessWidget {
  final AcCartItem        item;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback      onRemove;
  const _AcCartTile({
    required this.item, required this.onQtyChanged, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final unit      = AppPricing.acUnitPrice(item.type, item.btuSize);
    final lineTotal = unit * item.qty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: C.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 🔒 [PHASE1] emoji → Icon
        Icon(acTypeIcon(item.type), size: 20, color: C.primary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${acTypeLabel(item.type)} · ${btuLabel(item.btuSize)}',
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            item.type == AcServiceType.refill
                ? '${AppPricing.fmt(unit)} ${tr("kip_currency")}/${tr("unit_device")} (${tr("estimate_label")})'
                : '${AppPricing.fmt(unit)} ${tr("kip_currency")}/${tr("unit_device")}',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 6),
          _QtyRow(qty: item.qty, minQty: 1, maxQty: 20, label: tr('unit_device'),
              onChanged: onQtyChanged, compact: true),
        ])),
        const SizedBox(width: AppSpacing.sm),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: const Icon(Icons.close_rounded, size: 18, color: C.muted),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // ✅ [Phase 2 / Batch B] fontSize matches AppTypography.caption.
          Text('${AppPricing.fmt(lineTotal)} ${tr("kip_currency")}',
              style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w800, color: C.primary)),
        ]),
      ]),
    );
  }
}

class _AcCartSummary extends StatelessWidget {
  final BookingOrder order;
  const _AcCartSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    final lines = <_PriceLine>[
      if (order.acWashQty > 0)
        _PriceLine('${tr("svc_ac_clean")} (${order.acWashQty} ${tr("unit_device")})',
            '${AppPricing.fmt(order.acWashSubtotal)} ${tr("kip_currency")}'),
    ];
    if (order.acDiscountPct > 0) {
      lines.add(_PriceLine(
          '${tr("volume_discount_label")} ${(order.acDiscountPct * 100).toStringAsFixed(0)}%',
          '- ${AppPricing.fmt(order.acDiscountAmt)} ${tr("kip_currency")}', green: true));
    }
    if (order.acAddonSubtotal > 0) {
      lines.add(_PriceLine(tr('addon_refill_relocate_label'),
          '${AppPricing.fmt(order.acAddonSubtotal)} ${tr("kip_currency")}'));
    }
    lines.add(_PriceLine(tr('net_total_label'),
        '${AppPricing.fmt(order.acCartTotal)} ${tr("kip_currency")}', bold: true));
    if (order.acHasRefill) {
      lines.add(_PriceLine(
          tr('refill_price_estimate_note'), ''));
    }
    return _PriceInfoBox(color: C.categoryAcBg, lines: lines);
  }
}

class _DeepBreakdown extends StatelessWidget {
  final BookingOrder order;
  const _DeepBreakdown({required this.order});

  @override
  Widget build(BuildContext context) {
    final rate    = order.isPostConstruct ? AppPricing.deepPostMin : AppPricing.deepResMin;
    final rateMax = order.isPostConstruct ? AppPricing.deepPostMax : AppPricing.deepResMax;
    final minT    = (order.sqm * rate).round();
    final maxT    = (order.sqm * rateMax).round();
    return _PriceInfoBox(color: C.categoryCleanBg, lines: [
      _PriceLine(
          '${order.sqm.toStringAsFixed(0)} ${tr("unit_sqm")} × '
              '${AppPricing.fmt(rate)}–${AppPricing.fmt(rateMax)} ${tr("kip_currency")}', ''),
      _PriceLine(tr('estimated_price_label'),
          '${AppPricing.fmt(minT)}–${AppPricing.fmt(maxT)} ${tr("kip_currency")}', bold: true),
      _PriceLine(tr('provider_confirms_final_price'), ''),
    ]);
  }
}

class _SpecialistSummary extends StatelessWidget {
  final BookingOrder order;
  const _SpecialistSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    final lines = order.specialistQty.entries.map((e) {
      final item  = AppPricing.specialistItems[e.key];
      if (item == null) return const _PriceLine('', ''); // ✅ [FIX-2] safe
      final price = (item['min'] as int) * e.value;
      // 🔒 [AUDIT UI-1 / 2026-08-02] _PriceLine ເປັນ text-only row (ບໍ່ມີ icon
      // slot) — ຕັດ emoji ອອກແທນທີ່ຈະໃສ່ IconData ໃນ text string.
      return _PriceLine(
          '${tr(item['name'] as String)} × ${e.value}',
          '${AppPricing.fmt(price)} ${tr("kip_currency")}');
    }).toList();
    if (order.pestSqm > 0) {
      final pestPrice = (order.pestSqm * AppPricing.pestSqmMin).round();
      lines.add(_PriceLine(
          '${tr("pest_spray_title")} × ${order.pestSqm.toStringAsFixed(0)} ${tr("unit_sqm")}',
          '${AppPricing.fmt(pestPrice)} ${tr("kip_currency")}'));
    }
    lines.add(_PriceLine(tr('total_price_label'),
        '${AppPricing.fmt(order.serviceTotal)} ${tr("kip_currency")}', bold: true));
    return _PriceInfoBox(color: C.categoryPestBg, lines: lines);
  }
}

// ════════════════════════════════════════════════════════════
//  BILL CARD
// ════════════════════════════════════════════════════════════

class _BillCard extends StatelessWidget {
  final BookingOrder order;
  const _BillCard({required this.order});

  @override
  Widget build(BuildContext context) {
    // 🔒 [AUDIT CUST-1 / 2026-08-06] ກວດ/ລ້າງ coupon ທີ່ໝົດຄວາມສົດກ່ອນ ເພື່ອບໍ່ໃຫ້
    // ແຖວ "ສ່ວນຫຼຸດ" ຂ້າງລຸ່ມສະແດງຄ້າງ ໃນຂະນະທີ່ຍອດລວມ (discountedTotal, ຊຶ່ງ
    // self-heal ຢູ່ແລ້ວ) ບໍ່ໄດ້ຫັກສ່ວນຫຼຸດນັ້ນອອກອີກຕໍ່ໄປ.
    order._invalidateStaleCoupon();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8, offset: const Offset(0, 3),
        )],
      ),
      child: Column(children: [
        _BillRow(tr('bill_category'), bookingCatLabel(order)),
        const Divider(height: 20),
        _BillRow(tr('bill_service_fee'),
            order.isQuote
                ? tr('bill_pending_quote')
                : '${AppPricing.fmt(order.serviceTotal)} ${tr("kip_currency")}'),
        if (order.hasTravelFee) ...[
          const SizedBox(height: 6),
          _BillRow(
              '${tr('travel_fee_label')} (>${AppPricing.travelFreeKm.toInt()} ${tr('km_unit')})',
              '+ ${AppPricing.fmt(AppPricing.travelFee)} ${tr("kip_currency")}',
              orange: true),
        ],
        if (order.couponCode != null && order.couponDiscount != null) ...[
          const SizedBox(height: 6),
          _BillRow(
              '${tr('discount_label')} (${order.couponCode})',
              '- ${AppPricing.fmt(order.couponDiscount!.round())} ${tr("kip_currency")}',
              green: true),
        ],
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: _DashedDivider()),
        _BillRow(
          tr('total_price_label'),
          order.isQuote
              ? tr('bill_pending_provider')
              : '${AppPricing.fmt(order.discountedTotal.round())} ${tr("kip_currency")}',
          bold: true,
        ),
      ]),
    );
  }

}

String bookingCatLabel(BookingOrder o) {
  if (o.category == ServiceCategory.acCleaning) {
    if (o.acCart.isEmpty) return tr('svc_ac_clean');
    final totalQty = o.acCart.fold<int>(0, (s, i) => s + i.qty);
    return '${tr("svc_ac_clean")} ${o.acCart.length} ${tr("unit_item")} ($totalQty ${tr("unit_device")})';
  }
  return switch (o.cleanType) {
    HomeCleaningType.general    => o.priceMode == PriceMode.hourly
        ? '${tr("svc_house_clean")} ${o.hours} ${tr("hours_unit")}'
        : '${tr("svc_house_clean")} (${_roomTypeLabel(o.roomType)})',
    HomeCleaningType.deep       => '${tr("deep_clean_label")} ${o.sqm.toStringAsFixed(0)} ${tr("unit_sqm")}',
    HomeCleaningType.specialist => '${tr("specialist_label")} ${o.specialistQty.length} ${tr("unit_item")}',
    null                        => tr('svc_house_clean'),
  };
}

String _roomTypeLabel(String? r) => switch (r) {
  'studio' => 'Studio',
  '1bed'   => tr('room_type_1bed'),
  '2bed'   => tr('room_type_2bed'),
  _        => '–',
};

class _BillRow extends StatelessWidget {
  final String label, value;
  final bool   bold, orange, green;
  const _BillRow(this.label, this.value,
      {this.bold = false, this.orange = false, this.green = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: (bold ? AppTypography.heading : AppTypography.label).copyWith(
          fontSize: bold ? 16 : 13,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: bold ? C.textPrimary : C.textSecondary)),
      // ✅ [Brand color audit 2026-07-27 v2] green ຫຼຸດລາຄາ = Success (#22C55E)
      Text(value, style: (bold ? AppTypography.title : AppTypography.label).copyWith(
          fontSize: bold ? 20 : 13,
          fontWeight: FontWeight.w800,
          color: orange ? C.orange : (green ? C.success : C.textPrimary))),
    ],
  );
}

// ════════════════════════════════════════════════════════════
//  COUPON — ໃສ່ລະຫັດສ່ວນຫຼຸດຕອນຈອງ
// ════════════════════════════════════════════════════════════

class _CouponBox extends StatefulWidget {
  final BookingOrder order;
  final VoidCallback onChanged;
  const _CouponBox({required this.order, required this.onChanged});

  @override
  State<_CouponBox> createState() => _CouponBoxState();
}

class _CouponBoxState extends State<_CouponBox> {
  final _ctrl = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _checking = true; _error = null; });
    final result = await CouponRepository.instance
        .validate(code, widget.order.grandTotal);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (result == null) {
        _error = tr('coupon_invalid_or_expired');
      } else {
        widget.order.couponCode = result.code;
        widget.order.couponDiscount = result.discountAmount;
        // 🔒 [AUDIT CUST-1 / 2026-08-06] ບັນທຶກ grandTotal ຕອນນີ້ໄວ້ — ໃຊ້
        // ກວດຄວາມສົດຂອງສ່ວນຫຼຸດນີ້ພາຍຫຼັງ (_invalidateStaleCoupon()).
        widget.order._couponBaseTotal = widget.order.grandTotal;
      }
    });
    widget.onChanged();
  }

  void _clear() {
    setState(() {
      widget.order.couponCode = null;
      widget.order.couponDiscount = null;
      widget.order._couponBaseTotal = null;
      _ctrl.clear();
      _error = null;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    // 🔒 [AUDIT CUST-1 / 2026-08-06] ຖ້າຜູ້ໃຊ້ແກ້ໄຂລາຍການ (ປ່ຽນຈຳນວນ/
    // ແພັກເກັດ) ຫຼັງຈາກ apply coupon ແລ້ວກັບມາໜ້ານີ້, badge "coupon applied"
    // ຕ້ອງບໍ່ຄ້າງສະແດງສ່ວນຫຼຸດທີ່ບໍ່ໄດ້ຫັກອີກຕໍ່ໄປ — ກວດ/ລ້າງກ່ອນ build ທຸກຄັ້ງ.
    order._invalidateStaleCoupon();
    if (order.couponCode != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: C.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: C.green.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.local_offer, color: C.green, size: 16),
          const SizedBox(width: AppSpacing.sm),
          // ✅ [Phase 2 / Batch B] fontSize matches AppTypography.label.
          Expanded(
              child: Text(
                  '${order.couponCode} · -${AppPricing.fmt((order.couponDiscount ?? 0).round())} ${tr("kip_currency")}',
                  style: AppTypography.label.copyWith(
                      fontWeight: FontWeight.w700, color: C.green))),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: C.green),
            tooltip: tr('cancel'),
            onPressed: _clear,
          ),
        ]),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: TextField(
          controller: _ctrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: tr('hint_discount_code'),
            errorText: _error,
            filled: true, fillColor: C.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(color: C.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(color: C.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: const BorderSide(color: C.primary, width: 1.5)),
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: _checking ? null : _check,
          style: ElevatedButton.styleFrom(
              backgroundColor: C.primary, foregroundColor: Colors.white),
          child: _checking
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(tr('checking')),
        ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════
//  BOOKING REVIEW CARD — ສະຫຼຸບໃຫ້ກວດກ່ອນຢືນຢັນ
// ════════════════════════════════════════════════════════════

class _BookingReviewCard extends StatelessWidget {
  final BookingOrder  order;
  final VoidCallback   onEditService;
  final VoidCallback   onEditSchedule;
  final VoidCallback   onEditAddress;
  const _BookingReviewCard({
    required this.order,
    required this.onEditService,
    required this.onEditSchedule,
    required this.onEditAddress,
  });

  String get _scheduleLabel {
    if (order.isNow) return '${tr('now_option_title')} (30–60 ${tr('minutes_unit')})';
    final dt = order.scheduledAt;
    if (dt == null) return '–';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      boxShadow: [BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 8, offset: const Offset(0, 3),
      )],
    ),
    child: Column(children: [
      _ReviewRow(
        icon: Icons.build_outlined, label: tr('step_label_service'),
        value: bookingCatLabel(order), onEdit: onEditService,
      ),
      const Divider(height: 20),
      _ReviewRow(
        icon: Icons.event_outlined, label: tr('step_label_schedule'),
        value: _scheduleLabel, onEdit: onEditSchedule,
      ),
      const Divider(height: 20),
      _ReviewRow(
        icon: Icons.location_on_outlined, label: tr('address'),
        value: order.address.isEmpty ? '–' : order.address,
        sub: order.landmark.isNotEmpty ? order.landmark : null,
        onEdit: onEditAddress,
      ),
    ]),
  );
}

class _ReviewRow extends StatelessWidget {
  final IconData       icon;
  final String         label, value;
  final String?        sub;
  final VoidCallback?  onEdit;
  const _ReviewRow({
    required this.icon, required this.label, required this.value,
    this.sub, this.onEdit,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: C.primary),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.label.copyWith(fontWeight: FontWeight.w700)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: AppTypography.caption),
          ],
        ],
      )),
      if (onEdit != null)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
              // ✅ [Phase 2 / Batch B] fontSize matches AppTypography.caption.
              child: Text(tr('edit'), style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700, color: C.primary)),
            ),
          ),
        ),
    ],
  );
}

// ════════════════════════════════════════════════════════════
//  JOB PHOTO PICKER — ຮູບໜ້າວຽກ (ທາງເລືອກ)
// ════════════════════════════════════════════════════════════

class _JobPhotoPicker extends StatelessWidget {
  final String        photoUrl;
  final bool          uploading;
  final VoidCallback  onPick;
  final VoidCallback  onRemove;
  const _JobPhotoPicker({
    required this.photoUrl, required this.uploading,
    required this.onPick,   required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (uploading) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: C.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: C.primary.withValues(alpha: 0.2)),
        ),
        child: const Center(child: SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: C.primary),
        )),
      );
    }

    if (photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(children: [
          // 🔒 [AUDIT PERF-5 / 2026-08-02 — Medium, fresh re-audit] cacheHeight
          // ຈຳກັດ decode ຢູ່ຂະໜາດສະແດງຈິງ (job_workflow_Screen.dart ໃຊ້ pattern
          // ດຽວກັນ) — ຮູບທີ່ upload ໄປແລ້ວຖືກຈຳກັດ 1600px (booking_form_screen.dart's
          // picker), ແຕ່ສະແດງຢູ່ນີ້ພຽງແຕ່ 140dp ສູງ, ບໍ່ຈຳກັດ decode size ຈະໃຊ້
          // memory ເກີນຄວາມຈຳເປັນ.
          Image.network(photoUrl, height: 140, width: double.infinity,
              fit: BoxFit.cover, cacheHeight: 280),
          Positioned(
            top: 6, right: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.5),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ]),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: C.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
                color: C.primary.withValues(alpha: 0.25),
                style: BorderStyle.solid),
          ),
          child: Column(children: [
            const Icon(Icons.add_a_photo_outlined, color: C.primary, size: 22),
            const SizedBox(height: 6),
            Text(tr('job_photo_optional_hint'), style: AppTypography.caption.copyWith(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: C.primary)),
          ]),
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const dashWidth = 5.0, dashSpace = 4.0;
      final count = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
      return Row(
        children: List.generate(count, (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: dashSpace / 2),
          child: Container(width: dashWidth, height: 1, color: C.border),
        )),
      );
    },
  );
}

// ════════════════════════════════════════════════════════════
//  PAYMENT
// ════════════════════════════════════════════════════════════

class _PaymentCard extends StatelessWidget {
  final String       method, emoji, title, sub;
  final bool         selected;
  final VoidCallback onTap;
  final IconData?    icon;
  const _PaymentCard({
    required this.method, required this.emoji,
    required this.title,  required this.sub,
    required this.selected, required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? C.primary.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: selected ? C.primary : C.border,
              width: selected ? 2 : 1),
        ),
        child: Row(children: [
          if (icon != null)
            Icon(icon, size: 26, color: selected ? C.primary : C.textSecondary)
          else
            Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.body.copyWith(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: selected ? C.primary : C.textPrimary)),
              Text(sub, style: AppTypography.caption),
            ],
          )),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? C.primary : C.muted),
        ]),
      ),
    ),
  );
}

class _BcelQrBox extends ConsumerWidget {
  final BookingOrder order;
  const _BcelQrBox({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ [Dynamic payment config] admin ຕັ້ງຄ່າຜ່ານ lintho-admin (Settings >
    // Payment) — ຖ້າຍັງບໍ່ທັນຕັ້ງ (qrImageUrl null), fallback ໄປໃຊ້ QR ສ້າງເອງ
    // ຈາກ order.bcelQrData ຄືເກົ່າ (ບໍ່ໃຫ້ໜ້ານີ້ຫວ່າງເປົ່າ).
    final cfg = ref.watch(paymentConfigProvider).valueOrNull ?? PaymentConfig.fallback;

    return Container(
      // ✅ [Premium redesign / Batch 3 / P2-5] 20 → AppSpacing.xl(24)
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: C.categoryAcBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
            color: C.categoryAcAccent.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(tr('bcel_qr_title'), style: AppTypography.body.copyWith(
            fontSize: 14, fontWeight: FontWeight.w800,
            color: C.categoryAcAccent)),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
                color: C.categoryAcAccent.withValues(alpha: 0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: cfg.qrImageUrl != null
                ? Image.network(
                    cfg.qrImageUrl!,
                    width: 160, height: 160, fit: BoxFit.contain,
                    cacheWidth: 320, cacheHeight: 320, // 🔒 [AUDIT PERF-5 / 2026-08-02]
                    errorBuilder: (_, __, ___) => QrImageView(
                      data:    order.bcelQrData,
                      version: QrVersions.auto,
                      size:    160,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: C.categoryAcAccent,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: C.categoryAcAccent,
                      ),
                    ),
                  )
                : QrImageView(
                    data:    order.bcelQrData,
                    version: QrVersions.auto,
                    size:    160,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: C.categoryAcAccent,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: C.categoryAcAccent,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          order.isQuote
              ? tr('bcel_qr_confirm_note')
              // 🔒 [AUDIT CUST-1 / 2026-08-02] discountedTotal ດຽວກັນກັບ
              // bcelQrData ຂ້າງເທິງ ແລະ Bill Card — ບໍ່ໃຊ້ grandTotal ອີກຕໍ່ໄປ.
              : '${AppPricing.fmt(order.discountedTotal.round())} ${tr("kip_currency")}',
          style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w700,
              color: C.categoryAcAccent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(tr('bcel_qr_scan_hint'),
            style: AppTypography.caption),
        Text(tr('bcel_qr_generate_note'),
            style: AppTypography.caption),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
                color: C.categoryAcAccent.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _BcelAccountRow(label: tr('bank_name'), value: cfg.bankName),
            _BcelAccountRow(label: tr('account_holder'), value: cfg.accountName),
            _BcelAccountRow(
                label: tr('account_no'), value: cfg.accountNumber, copyable: true),
          ]),
        ),
      ]),
    );
  }
}

class _BcelAccountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool   copyable;
  const _BcelAccountRow({
    required this.label, required this.value, this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption),
          Flexible(child: InkWell(
            onTap: !copyable ? null : () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr('copied_to_clipboard')), // 🔒 [AUDIT UI-10 / 2026-08-02]
                    duration: const Duration(seconds: 1)),
              );
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(value, textAlign: TextAlign.right,
                  style: AppTypography.label.copyWith(
                      fontWeight: FontWeight.w800,
                      color: C.categoryAcAccent))),
              if (copyable) ...[
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.copy_rounded, size: 13, color: C.categoryAcAccent),
              ],
            ]),
          )),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  SMALL WIDGETS
// ════════════════════════════════════════════════════════════

class _QuickBookCard extends StatelessWidget {
  // ✅ [FIX ME-7] emoji -> icon — Step 0 ແມ່ນໜ້າທຳອິດທີ່ຜູ້ໃຊ້ທຸກຄົນເຫັນ,
  // ໃຫ້ກົງກັນກັບ Material icon migration ທີ່ເລີ່ມຢູ່ _BtuSelector/_AcTypeCard
  final IconData icon;
  final String title, sub;
  final Color  color, accent;
  final String? badge;
  final VoidCallback onTap;
  const _QuickBookCard({
    required this.icon, required this.title, required this.sub,
    required this.color, required this.accent,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(clipBehavior: Clip.none, children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 26, color: accent),
                const Spacer(),
                Icon(Icons.arrow_forward_rounded, size: 18, color: accent),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Text(title, style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w800, fontSize: 14, color: accent)),
              const SizedBox(height: 2),
              Text(sub, style: AppTypography.caption.copyWith(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: accent.withValues(alpha: 0.75))),
            ]),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -8, right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: C.red,
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                // ✅ [Premium redesign / Batch 3 / P2-4] 0.35 → 0.15 — this
                // badge is already solid red; the shadow only needs to lift
                // it off the card, not add a second layer of red saturation.
                // Brought in line with _BigCatCard's own legitimate 0.15
                // colored selected-state shadow elsewhere on this screen.
                boxShadow: [BoxShadow(
                  color: C.red.withValues(alpha: 0.15),
                  blurRadius: 6, offset: const Offset(0, 2),
                )],
              ),
              child: Text(badge!, style: AppTypography.caption.copyWith(
                  fontSize: 9.5, fontWeight: FontWeight.w800,
                  color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}

class _BigCatCard extends StatelessWidget {
  // ✅ [FIX ME-7] emoji -> icon, ຄືກັນກັບ _QuickBookCard
  final IconData     icon;
  final String       title, sub, note;
  final List<String> bullets;
  final Color        color, accent;
  final bool         selected;
  final VoidCallback onTap;
  const _BigCatCard({
    required this.icon,    required this.title,
    required this.sub,     required this.note,
    required this.bullets, required this.color,
    required this.accent,  required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? C.green.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: selected ? C.green : Colors.transparent,
              width: 2),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10, offset: const Offset(0, 4),
          )],
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: Icon(icon, size: 32, color: accent)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AppText.heading(title, fontWeight: FontWeight.w800, color: C.textPrimary),
                  Text(sub, style: AppTypography.caption.copyWith(
                      fontSize: 11, color: C.textSecondary)),
                ])),
              ]),
              const SizedBox(height: 14),
              ...bullets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: C.green.withValues(alpha: 0.85)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(b, style: AppTypography.caption.copyWith(
                      fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4,
                      color: C.textSecondary))),
                ]),
              )),
              const SizedBox(height: AppSpacing.xs),
              Text(note, style: AppTypography.heading.copyWith(
                  fontSize: 16, fontWeight: FontWeight.w600, color: C.green)),
            ],
          ),
          if (selected)
            Positioned(
              top: -6, right: -6,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, size: 24, color: C.green),
              ),
            ),
        ]),
      ),
    ),
  );
}

class _AcTypeCard extends StatelessWidget {
  final AcServiceType type;
  final bool          selected;
  final VoidCallback  onTap;
  const _AcTypeCard({required this.type, required this.selected, required this.onTap});

  // ✅ [i18n] 'title'/'desc'/'price'/'priceNote' ໃນນີ້ຄື tr() KEY (const map
  // ບໍ່ສາມາດເອີ້ນ tr() runtime function ໄດ້) — tr() ຈິ່ງຖືກເອີ້ນຢູ່ build() ຂ້າງລຸ່ມ.
  static const _data = {
    AcServiceType.standard: {
      'icon': Icons.water_drop_outlined, 'title': 'ac_card_standard_title',
      'desc': 'ac_card_standard_desc',
      'price': 'ac_card_standard_price',
      'priceNote': 'ac_card_price_note_by_btu',
    },
    AcServiceType.deepFull: {
      'icon': Icons.build_outlined, 'title': 'ac_card_deep_title',
      'desc': 'ac_card_deep_desc',
      'price': 'ac_card_deep_price',
      'priceNote': 'ac_card_price_note_by_btu',
    },
    AcServiceType.refill: {
      'icon': Icons.science_outlined, 'title': 'ac_card_refill_title',
      'desc': 'ac_card_refill_desc',
      'price': 'ac_card_refill_price',
      'priceNote': 'ac_card_refill_price_note',
    },
    AcServiceType.relocate: {
      'icon': Icons.local_shipping_outlined, 'title': 'ac_card_relocate_title',
      'desc': 'ac_card_relocate_desc',
      'price': 'ac_card_relocate_price',
      'priceNote': 'ac_card_relocate_price_note',
    },
  };

  @override
  Widget build(BuildContext context) {
    final d = _data[type]!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? C.primary.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
                color: selected ? C.primary : C.border,
                width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: C.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(d['icon'] as IconData, size: 22, color: C.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(d['title'] as String), style: AppTypography.label.copyWith(fontWeight: FontWeight.w800, color: selected ? C.primary : C.textPrimary)),
                const SizedBox(height: 3),
                Text(tr(d['desc'] as String),
                    style: AppTypography.caption),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(child: Text(tr(d['price'] as String),
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: selected ? C.primary : C.categoryAcAccent))),
                    const SizedBox(width: AppSpacing.xs),
                    Text(tr(d['priceNote'] as String), style: AppTypography.caption.copyWith(
                        fontSize: 10, fontWeight: FontWeight.w400, color: C.muted)),
                  ],
                ),
              ],
            )),
            const SizedBox(width: AppSpacing.sm),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 22,
                color: selected ? C.primary : C.border),
          ]),
        ),
      ),
    );
  }
}

class _BtuSelector extends StatelessWidget {
  final AcBtuSize               selected;
  final ValueChanged<AcBtuSize> onChanged;
  const _BtuSelector({required this.selected, required this.onChanged});

  // ✅ [i18n] 3rd tuple element ຄື tr() KEY — ເບິ່ງ comment ຢູ່ _AcTypeCard._data
  // ✅ ປ່ຽນຈາກ emoji (🧊❄️🏢) ມາໃຊ້ Line Icon ໂທນດຽວກັນກັບ _AcTypeCard ຂ້າງເທິງ
  // ✅ [FIX ME-6] small/large ເຄີຍໃຊ້ icon ດຽວກັນ (ac_unit_outlined ຊ້ຳ), ແລະ
  // cabinet ໃຊ້ dns_outlined (ຮູບ server rack ບໍ່ກ່ຽວກັບແອ) — ຕອນນີ້ໃຫ້ 3 tier
  // ມີ icon ແຍກກັນຢ່າງຊັດເຈນ: small=outline snowflake, large=filled snowflake
  // (ນ້ຳໜັກສາຍຕາໜັກກວ່າ = ຂະໜາດໃຫຍ່ກວ່າ), cabinet=ອາຄານ (ຄືຄວາມໝາຍເດີມຂອງ 🏢)
  static const _items = [
    (AcBtuSize.small,   Icons.ac_unit_outlined,   'ac_btu_small_title',   '9,000–13,000 BTU'),
    (AcBtuSize.large,   Icons.ac_unit,            'ac_btu_large_title',   '18,000–24,000 BTU'),
    (AcBtuSize.cabinet, Icons.apartment_outlined, 'ac_btu_cabinet_title', '30,000+ BTU'),
  ];

  @override
  // ✅ [FIX LO-2] crossAxisAlignment.start ກັນ icon ບໍ່ຢູ່ລະດັບດຽວກັນ ຖ້າ
  // title ຂອງບາງ tier ຍາວກວ່າ tier ອື່ນ (ໂດຍສະເພາະພາສາລາວ) ຈົນເຮັດໃຫ້ card
  // ສູງບໍ່ເທົ່າກັນ — Row ແບບເກົ່າ (default center) ຈະຈັດ card ສັ້ນກວ່າໃຫ້ຢູ່
  // ກາງແທນ ເຮັດໃຫ້ icon ແຕ່ລະຄໍລໍາເບ້ບໍ່ກົງກັນ
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: _items.asMap().entries.map((e) {
      final i = e.key; final item = e.value;
      final sel = selected == item.$1;
      return Expanded(child: Padding(
        padding: EdgeInsets.only(right: i < _items.length - 1 ? 8 : 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(item.$1),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: sel ? C.primary.withValues(alpha: 0.07) : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                    color: sel ? C.primary : C.border, width: sel ? 2 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: C.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.$2, size: 20, color: C.primary),
                ),
                const SizedBox(height: 6),
                Text(tr(item.$3), textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: sel ? C.primary : C.textPrimary)),
                const SizedBox(height: AppSpacing.xs),
                Text(item.$4, textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(fontSize: 10, color: C.muted)),
              ]),
            ),
          ),
        ),
      ));
    }).toList(),
  );
}

class _SmallTypeCard extends StatelessWidget {
  final IconData      icon;
  final String        title;
  final bool          selected;
  final VoidCallback  onTap;
  const _SmallTypeCard({
    required this.icon, required this.title,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? C.primary.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: selected ? C.primary : C.border, width: selected ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: C.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: C.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, textAlign: TextAlign.center, style: AppTypography.caption.copyWith(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: selected ? C.primary : C.textPrimary)),
        ]),
      ),
    ),
  );
}

class _ModeCard extends StatelessWidget {
  final String       title, sub;
  final bool         selected;
  final VoidCallback onTap;
  const _ModeCard({
    required this.title, required this.sub,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? C.primary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: selected ? C.primary : C.border, width: selected ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTypography.label.copyWith(fontWeight: FontWeight.w800, color: selected ? C.primary : C.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(sub, style: AppTypography.caption),
        ]),
      ),
    ),
  );
}

class _RoomTile extends StatelessWidget {
  final String       id, title, sub;
  final int          minP, maxP;
  final bool         selected;
  final VoidCallback onTap;
  const _RoomTile({
    required this.id, required this.title, required this.sub,
    required this.minP, required this.maxP,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? C.primary.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: selected ? C.primary : C.border, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? C.primary : C.muted, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTypography.body.copyWith(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: selected ? C.primary : C.textPrimary)),
            Text(sub, style: AppTypography.caption),
          ])),
          Text('${AppPricing.fmt(minP)}–${AppPricing.fmt(maxP)} ${tr("kip_currency")}',
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700,
                  color: selected ? C.primary : C.muted)),
        ]),
      ),
    ),
  );
}

class _SqmInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<double>  onChanged;
  final double                value, minSqm;
  const _SqmInput({
    required this.controller, required this.onChanged,
    required this.value,      required this.minSqm,
  });

  static const _presets = [50.0, 100.0, 150.0];
  // 🔒 [AUDIT EDGE-4 / 2026-08-06] see AppPricing.deepSqmMax
  static const _maxSqm = 2000.0;

  bool get _hasMinError => value > 0 && value < minSqm;
  bool get _hasMaxError => value > _maxSqm;
  bool get _hasError => _hasMinError || _hasMaxError;

  @override
  Widget build(BuildContext context) {
    final errColor = C.red.withValues(alpha: 0.6);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller:   controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged:    (v) => onChanged(double.tryParse(v) ?? 0),
        decoration: InputDecoration(
          hintText:   tr('sqm_input_hint'),
          // ✅ [Phase 2 / Batch B] every other TextField's hintStyle in this
          // file already uses AppTypography.caption — this one was the lone
          // outlier at a hardcoded 14/muted.
          hintStyle:  AppTypography.caption,
          suffixText: tr('sqm_input_suffix'),
          suffixStyle: const TextStyle(color: C.muted, fontWeight: FontWeight.w600),
          filled: true, fillColor: C.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(color: _hasError ? errColor : C.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(color: _hasError ? errColor : C.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(color: _hasError ? errColor : C.primary, width: 1.5)),
        ),
      ),
      if (_hasMinError) ...[
        const SizedBox(height: 6),
        Text('${tr("sqm_input_error_prefix")} ${minSqm.toStringAsFixed(0)} ${tr("sqm_input_error_suffix")}',
            // ✅ [Phase 2 / Batch B] fontSize matches AppTypography.caption.
            style: AppTypography.caption.copyWith(
                color: C.red.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
      ] else if (_hasMaxError) ...[
        const SizedBox(height: 6),
        Text('${tr("sqm_input_max_error_prefix")} ${_maxSqm.toStringAsFixed(0)} ${tr("sqm_input_max_error_suffix")}',
            // ✅ [Phase 2 / Batch B] fontSize matches AppTypography.caption.
            style: AppTypography.caption.copyWith(
                color: C.red.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 10),
      Row(children: _presets.map((p) {
        final selected = value == p;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sheet),
              onTap: () {
                controller.text = p.toStringAsFixed(0);
                onChanged(p);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: selected ? C.primary : C.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sheet),
                  border: Border.all(
                      color: selected ? C.primary : C.primary.withValues(alpha: 0.2)),
                ),
                child: Text('${p.toStringAsFixed(0)} ${tr("unit_sqm")}', style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : C.primary)),
              ),
            ),
          ),
        );
      }).toList()),
    ]);
  }
}

class _AddonCheckRow extends StatelessWidget {
  final String                 id;
  final Map<String, dynamic>   data;
  final bool                   checked;
  final ValueChanged<bool>     onChanged;
  const _AddonCheckRow({
    required this.id, required this.data,
    required this.checked, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: checked ? C.primary.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: checked ? C.primary : C.border, width: checked ? 2 : 1),
        ),
        child: Row(children: [
          Icon(
            checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: checked ? C.primary : C.muted, size: 22,
          ),
          const SizedBox(width: 10),
          Icon(data['icon'] as IconData, color: C.textPrimary, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(tr(data['name'] as String), style: AppTypography.label.copyWith(fontWeight: FontWeight.w700))),
          Text('+${AppPricing.fmt(data['price'] as int)} ${tr("kip_currency")}', style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: checked ? C.primary : C.muted)),
        ]),
      ),
    ),
  );
}

class _SpecialistRow extends StatelessWidget {
  final String               id;
  final Map<String, dynamic> data;
  final int                  qty;
  final ValueChanged<int>    onChanged;
  const _SpecialistRow({
    required this.id, required this.data,
    required this.qty, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final checked = qty > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: checked ? C.primary.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
            color: checked ? C.primary : C.border, width: checked ? 2 : 1),
      ),
      child: Row(children: [
        Icon(data['icon'] as IconData, color: C.textPrimary, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(data['name'] as String), style: AppTypography.label.copyWith(fontWeight: FontWeight.w700)),
          Text(
            '${AppPricing.fmt(data['min'] as int)}–'
                '${AppPricing.fmt(data['max'] as int)} ${tr("kip_currency")} / ${tr(data['unit'] as String)}',
            style: AppTypography.caption,
          ),
          if (data['sub'] != null) ...[
            const SizedBox(height: 2),
            Text(tr(data['sub'] as String),
                style: AppTypography.caption.copyWith(
                    fontSize: 10.5, color: C.muted, fontStyle: FontStyle.italic)),
          ],
        ])),
        _QtyRow(qty: qty, minQty: 0, maxQty: 20,
            label: tr(data['unit'] as String),
            onChanged: onChanged, compact: true),
      ]),
    );
  }
}

class _PestRow extends StatelessWidget {
  final double        sqm;
  final VoidCallback   onTap;
  final VoidCallback   onClear;
  const _PestRow({required this.sqm, required this.onTap, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final selected = sqm > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: selected ? C.primary.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
            color: selected ? C.primary : C.border, width: selected ? 2 : 1),
      ),
      child: Row(children: [
        const Text('🧴', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('specialist_pest_name'), style: AppTypography.label.copyWith(fontWeight: FontWeight.w700)),
          Text(
            selected
                ? '${sqm.toStringAsFixed(0)} ${tr("unit_sqm")} / ${AppPricing.fmt(AppPricing.pestSqmMin)}–'
                  '${AppPricing.fmt(AppPricing.pestSqmMax)} ${tr("kip_currency")}'
                : '${AppPricing.fmt(AppPricing.pestSqmMin)}–'
                  '${AppPricing.fmt(AppPricing.pestSqmMax)} ${tr("kip_currency")} / ${tr("unit_sqm")}',
            style: AppTypography.caption,
          ),
        ])),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _CBtn(icon: Icons.remove_rounded,
              semanticLabel: tr('qty_decrease_semantic'),
              onTap: selected ? onClear : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(selected ? sqm.toStringAsFixed(0) : '0', style: AppTypography.heading.copyWith(
                fontSize: 16, fontWeight: FontWeight.w900, color: C.textPrimary)),
          ),
          _CBtn(icon: Icons.add_rounded,
              semanticLabel: tr('qty_increase_semantic'),
              onTap: onTap),
        ]),
      ]),
    );
  }
}

class _QtyRow extends StatelessWidget {
  final int               qty, minQty;
  final String            label;
  final ValueChanged<int> onChanged;
  final bool              compact;
  // ✅ [FIX LO-7] ຂອບເຂດເທິງສຸດ — ກ່ອນໜ້ານີ້ບໍ່ມີ, ກົດ "+" ຊ້ຳໆໄດ້ຄ່າບໍ່ຈຳກັດ
  final int               maxQty;
  const _QtyRow({
    required this.qty, required this.minQty,
    required this.label, required this.onChanged,
    this.compact = false,
    this.maxQty = 99,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: compact
        ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6)
        : const EdgeInsets.all(14),
    decoration: compact ? null : BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: C.border),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _CBtn(icon: Icons.remove_rounded,
          semanticLabel: tr('qty_decrease_semantic'),
          onTap: qty > minQty ? () => onChanged(qty - 1) : null),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16),
        child: Text('$qty', style: (compact ? AppTypography.heading : AppTypography.title).copyWith(
            fontSize: compact ? 16 : 22,
            fontWeight: FontWeight.w900, color: C.textPrimary)),
      ),
      _CBtn(icon: Icons.add_rounded,
          semanticLabel: tr('qty_increase_semantic'),
          onTap: qty < maxQty ? () => onChanged(qty + 1) : null),
      if (!compact) ...[
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: AppTypography.caption),
      ],
    ]),
  );
}

class _CBtn extends StatelessWidget {
  final IconData      icon;
  final VoidCallback? onTap;
  // ✅ [FIX LO-3] ກ່ອນໜ້ານີ້ບໍ່ມີ Semantics label ເລີຍ — screen reader ອ່ານໄດ້
  // ພຽງແຕ່ "button" ບໍ່ບອກວ່າເພີ່ມ/ຫຼຸດ
  final String?       semanticLabel;
  const _CBtn({required this.icon, required this.onTap, this.semanticLabel});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        // ✅ [FIX LO-3] ຂະໜາດ tap target ເພີ່ມຈາກ 32 -> 36dp — ຍັງບໍ່ຮອດ 44dp
        // ຄາດຫວັງເຕັມທີ່ (ຈະຕ້ອງແກ້ layout compact row ອ້ອມຂ້າງນຳ) ແຕ່ດີກວ່າເກົ່າ
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: onTap != null
                ? C.primary.withValues(alpha: 0.08)
                : C.border.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Icon(icon, size: 16,
              color: onTap != null ? C.primary : C.muted),
        ),
      ),
    ),
  );
}

class _TimeToggle extends StatelessWidget {
  // ✅ [FIX ME-7] emoji -> icon — Step 2 ເຫັນໂດຍທຸກ booking, ບໍ່ຄວນເຫຼືອ emoji
  final IconData     icon;
  final String       title, sub;
  final bool         selected;
  final VoidCallback onTap;
  const _TimeToggle({
    required this.icon,  required this.title,
    required this.sub,   required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? C.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: selected ? C.primary : C.border,
              width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Icon(icon, size: 26, color: selected ? Colors.white : C.primary),
          const SizedBox(height: 6),
          Text(title, style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : C.textPrimary)),
          Text(sub, textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  color: selected ? Colors.white70 : C.muted)),
        ]),
      ),
    ),
  );
}

// ✅ [FIX-4] _TimeSlots ຮັບ baseDate ເຂົ້າມາ — ບໍ່ recompute ທຸກ rebuild
class _TimeSlots extends StatelessWidget {
  final DateTime               baseDate;
  final DateTime?              selected;
  final ValueChanged<DateTime> onSelected;
  const _TimeSlots({
    required this.baseDate,
    required this.selected,
    required this.onSelected,
  });

  static const _slots = [
    ('09:00', 9, 0),  ('10:00', 10, 0), ('11:00', 11, 0),
    ('13:00', 13, 0), ('14:00', 14, 0), ('15:00', 15, 0),
    ('16:00', 16, 0),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _slots.map((s) {
        final dt  = DateTime(
            baseDate.year, baseDate.month, baseDate.day, s.$2, s.$3);
        final sel = selected?.hour == s.$2 && selected?.minute == s.$3;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(dt),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? C.primary : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(
                    color: sel ? C.primary : C.border, width: sel ? 2 : 1),
              ),
              child: Text(s.$1, style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : C.textPrimary)),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TravelFeeBox extends StatelessWidget {
  final BookingOrder order;
  const _TravelFeeBox({required this.order});

  @override
  Widget build(BuildContext context) {
    final hasGps = order.isGpsAddress;
    final hasFee = order.hasTravelFee;
    final dist   = order.distanceKm;

    Color    bg, border;
    IconData icon;
    String   text;

    if (!hasGps) {
      bg     = C.primary.withValues(alpha: 0.05);
      border = C.primary.withValues(alpha: 0.2);
      // 🔒 [PHASE1] emoji → Icon
      icon   = Icons.info_outline_rounded;
      text   = '${tr("travel_fee_unknown_note")} '
          '(${tr("travel_fee_free_note")} ≤${AppPricing.travelFreeKm.toInt()} ${tr("km_unit")}, '
          '+${AppPricing.fmt(AppPricing.travelFee)} ${tr("kip_currency")} ${tr("travel_fee_if_farther")})';
    } else if (hasFee) {
      bg     = C.orange.withValues(alpha: 0.08);
      border = C.orange.withValues(alpha: 0.3);
      icon   = Icons.directions_car_outlined;
      text   = '${tr("distance_label")} ~${dist.toStringAsFixed(1)} ${tr("km_unit")} '
          '(${tr("travel_fee_exceeds_note")} ${AppPricing.travelFreeKm.toInt()} ${tr("km_unit")})\n'
          '+ ${tr("travel_fee_label")} ${AppPricing.fmt(AppPricing.travelFee)} ${tr("kip_currency")}';
    } else {
      // ✅ ບໍ່ມີຄ່າເດີນທາງ — ສະແດງເປັນ badge ສິດທິພິເສດ ບໍ່ແມ່ນ checkbox
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: C.mint,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: C.green.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(
              color: Colors.white, shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_outlined, color: C.green, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(
            '${tr("travel_fee_auto_free_note")} '
                '(${tr("distance_label")} ${dist.toStringAsFixed(1)} ${tr("km_unit")} ${tr("travel_fee_in_service_area_note")})',
            style: AppTypography.caption.copyWith(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: C.green, height: 1.4),
          )),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: hasFee && hasGps ? C.orange : C.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTypography.caption.copyWith(
          color: hasFee && hasGps ? C.orange : C.textSecondary,
          fontWeight: hasFee && hasGps ? FontWeight.w700 : FontWeight.w500,
          height: 1.5,
        ))),
      ]),
    );
  }
}

class _RelocateExtrasInfo extends StatelessWidget {
  const _RelocateExtrasInfo();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: C.categoryAddonBg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(
          color: C.categoryAddonBorder.withValues(alpha: 0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('📋', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text(tr('relocate_extras_header'),
            style: AppTypography.label.copyWith(fontWeight: FontWeight.w800,
                color: C.categoryAddonValueText)),
      ]),
      const SizedBox(height: 10),
      const Divider(height: 1),
      const SizedBox(height: 10),
      Text(tr('relocate_package_price_header'),
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700,
              color: C.categoryAddonValueText)),
      const SizedBox(height: 6),
      _ExtrasRow(tr('relocate_wall_small_label'), '450,000–600,000 ${tr("kip_currency")}'),
      _ExtrasRow(tr('relocate_wall_large_label'), '650,000–850,000 ${tr("kip_currency")}'),
      _ExtrasRow(tr('relocate_cabinet_label'), '950,000–1,300,000+ ${tr("kip_currency")}'),
      const SizedBox(height: 10), const Divider(height: 1), const SizedBox(height: 10),
      Text(tr('relocate_labor_only_header'), style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w700, color: C.categoryAddonValueText)),
      const SizedBox(height: 6),
      _ExtrasRow(tr('install_small_label'), '300,000–400,000 ${tr("kip_currency")}'),
      _ExtrasRow(tr('install_large_label'), '450,000–550,000 ${tr("kip_currency")}'),
      _ExtrasRow(tr('remove_any_size_label'), '150,000–250,000 ${tr("kip_currency")}'),
      const SizedBox(height: 10), const Divider(height: 1), const SizedBox(height: 10),
      Text(tr('spare_parts_header'), style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w700, color: C.categoryAddonValueText)),
      const SizedBox(height: 6),
      _ExtrasRow(tr('copper_pipe_label'), '150,000–250,000 ${tr("kip_currency")}/${tr("unit_meter")}'),
      _ExtrasRow(tr('electric_wire_label'), '20,000–35,000 ${tr("kip_currency")}/${tr("unit_meter")}'),
      _ExtrasRow(tr('pvc_pipe_label'), '15,000–25,000 ${tr("kip_currency")}/${tr("unit_meter")}'),
      _ExtrasRow(tr('outdoor_bracket_label'), '80,000–120,000 ${tr("kip_currency")}/${tr("unit_set")}'),
      _ExtrasRow(tr('breaker_box_label'), '50,000–80,000 ${tr("kip_currency")}/${tr("unit_set")}'),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: C.categoryAddonBorder.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 14, color: C.categoryAddonValueText),
          const SizedBox(width: 6),
          Expanded(child: Text(
            tr('relocate_pipe_included_note'),
            style: AppTypography.caption.copyWith(fontSize: 11, color: C.categoryAddonValueText),
          )),
        ]),
      ),
    ]),
  );
}

class _ExtrasRow extends StatelessWidget {
  final String label, value;
  const _ExtrasRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.caption.copyWith(
            fontSize: 11, color: C.categoryAddonLabelText)),
        Text(value, style: AppTypography.caption.copyWith(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: C.categoryAddonValueText)),
      ],
    ),
  );
}

class _RefillInfoCard extends StatelessWidget {
  final AcBtuSize btuSize;
  const _RefillInfoCard({required this.btuSize});

  @override
  Widget build(BuildContext context) {
    final range = AppPricing.acRefillPrice[btuSize]!;
    return Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: C.noteWarningBg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: C.orange.withValues(alpha: 0.4)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('🧪', style: TextStyle(fontSize: 20)),
        const SizedBox(width: AppSpacing.sm),
        Text(tr('refill_price_header'), style: AppTypography.body.copyWith(
            fontSize: 14, fontWeight: FontWeight.w800,
            color: C.noteWarningText)),
      ]),
      const SizedBox(height: AppSpacing.md),
      _RefillLine(tr('refill_minor_leak_label'), tr('free_check_label')),
      const SizedBox(height: 6),
      _RefillLine('${tr("refill_major_leak_prefix")} (${btuLabel(btuSize)})',
          '${AppPricing.fmt(range.$1)}–'
              '${AppPricing.fmt(range.$2)} ${tr("kip_currency")}'),
      const SizedBox(height: 6),
      _RefillLine(tr('refill_per_psi_label'), '20,000–30,000 ${tr("kip_currency")}'),
      const SizedBox(height: AppSpacing.md),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: C.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 14, color: C.noteWarningText),
          const SizedBox(width: 6),
          Expanded(child: Text(
            tr('refill_confirm_note'),
            style: AppTypography.caption.copyWith(color: C.noteWarningText),
          )),
        ]),
      ),
    ]),
    );
  }
}

class _RefillLine extends StatelessWidget {
  final String label, value;
  const _RefillLine(this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label, style: AppTypography.caption.copyWith(
          color: C.noteWarningTextDark))),
      const SizedBox(width: AppSpacing.sm),
      Text(value, style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: C.noteWarningText)),
    ],
  );
}

class _PriceInfoBox extends StatelessWidget {
  final Color            color;
  final List<_PriceLine> lines;
  const _PriceInfoBox({required this.color, required this.lines});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(AppRadius.card)),
    child: Column(
      children: lines.expand((l) => [l, const SizedBox(height: 6)]).toList()
        ..removeLast(),
    ),
  );
}

class _PriceLine extends StatelessWidget {
  final String label, value;
  final bool   bold, green;
  const _PriceLine(this.label, this.value,
      {this.bold = false, this.green = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      // ✅ [Brand color audit 2026-07-27 v2] green ຫຼຸດລາຄາ = Success
      // (#22C55E), ແຍກຈາກ Primary
      Expanded(child: Text(label, style: (bold ? AppTypography.body : AppTypography.caption).copyWith(
          fontSize: bold ? 14 : 12,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: green ? C.success : (bold ? C.textPrimary : C.muted)))),
      Text(value, style: (bold ? AppTypography.heading : AppTypography.caption).copyWith(
          fontSize: bold ? 17 : 12,
          fontWeight: FontWeight.w800,
          color: green ? C.success : C.textPrimary)),
    ],
  );
}

class _Label extends StatelessWidget {
  final String  text;
  final String? sub;
  const _Label(this.text, {this.sub});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ✅ [Phase 2 / Batch B] fontSize matches AppTypography.body exactly —
      // this widget is used ~30× across the file, so this single fix
      // converges every step-section header onto the token at once.
      Text(text, style: AppTypography.body.copyWith(
          fontWeight: FontWeight.w800, color: C.textPrimary)),
      if (sub != null)
        Text(sub!, style: AppTypography.caption),
    ],
  );
}

// ════════════════════════════════════════════════════════════
//  BOTTOM BAR  ✅ Skeleton loading ແທນ spinner
// ════════════════════════════════════════════════════════════

class _BottomBar extends StatelessWidget {
  final int          step;
  final bool         isLast, canNext, isLoading;
  final int?         estimatedTotal;
  final bool         showCleaningDisclaimer;
  final String?      blockedReason;
  final VoidCallback onNext;
  const _BottomBar({
    required this.step,    required this.isLast,
    required this.canNext, required this.isLoading,
    required this.onNext,  this.estimatedTotal,
    this.showCleaningDisclaimer = false,
    this.blockedReason,
  });

  void _showPriceDisclaimer(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Row(children: [
          const Icon(Icons.info_outline, color: C.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text(tr('price_disclaimer_title'),
              style: AppTypography.heading.copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        content: Text(
          tr('price_disclaimer_body'),
          style: AppTypography.caption.copyWith(
              fontSize: 13.5, color: C.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('price_disclaimer_ok'), style: const TextStyle(fontWeight: FontWeight.w700, color: C.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    // ✅ [Premium redesign / Batch 3 / P2-5] 20/16/24 → AppSpacing.xl/lg/xl
    padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: AppRadius.sheetTop,
      boxShadow: [BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 16, offset: const Offset(0, -4),
      )],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // ✅ ລາຄາລວມໂດຍປະມານ — Update real-time ທຸກຄັ້ງທີ່ມີການປ່ຽນແປງ
      if (estimatedTotal != null) ...[
        if (showCleaningDisclaimer) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(tr('cleaning_price_disclaimer'),
                style: AppTypography.caption.copyWith(fontSize: 10.5)),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            // ✅ [Phase 2 / Batch B] fontSize+weight matches AppTypography.label.
            Text(tr('bottom_bar_estimated_total'),
                style: AppTypography.label.copyWith(color: C.muted)),
            const SizedBox(width: AppSpacing.xs),
            // 🔒 [PHASE1] ເຄີຍ GestureDetector ດິບ (ບໍ່ມີ ripple/Semantics,
            // hit area ~15px) — ຝ່າຝືນ house rule "InkWell + Material ทุก tap
            // target" ຂອງໄຟລ໌ນີ້ເອງ. ຫຸ້ມ Material+InkWell ພ້ອມ padding ໃຫ້ hit
            // area ໃກ້ 44dp ໂດຍບໍ່ຂະຫຍາຍ icon ທີ່ເຫັນ
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                onTap: () => _showPriceDisclaimer(context),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Semantics(
                    button: true,
                    label: tr('price_disclaimer_title'),
                    child: const Icon(Icons.info_outline, size: 15, color: C.muted),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text('${AppPricing.fmt(estimatedTotal!)} ${tr("kip_currency")}',
                style: AppTypography.heading.copyWith(
                    fontSize: 18, fontWeight: FontWeight.w900, color: C.textPrimary)),
          ]),
        ),
      ],
      // ✅ [Premium redesign / Batch 3 / P1-2] presentation-only hint —
      // disappears the moment canNext becomes true, does not affect onNext
      if (blockedReason != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: AppText.caption(blockedReason!,
              textAlign: TextAlign.center, color: C.orange),
        ),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: canNext && !isLoading ? onNext : null,
          // 🔒 [PHASE1] elevation:4/shadowColor ຝ່າຝືນ convention ຂອງທັງແອັບ
          // (ElevatedButtonTheme.elevation: 0 — flat) ທີ່ທຸກປຸ່ມອື່ນໃນໜ້ານີ້ເອງ
          // (Add-to-list, coupon Apply, pest-sqm OK) ຄົງໄວ້. ບໍ່ປ່ຽນເປັນ
          // AppButton ບ່ອນນີ້ໂດຍເຈດຕະນາ — _ButtonSkeleton (loading state) ເປັນ
          // pattern ທີ່ດີກວ່າ CircularProgressIndicator ຂອງ AppButton ຢູ່ແລ້ວ,
          // ພຽງແຕ່ລຶບ elevation override ອອກໃຫ້ກົງກັບ theme flat convention
          style: ElevatedButton.styleFrom(
            backgroundColor: C.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: C.border,
            disabledForegroundColor: C.muted,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card)),
          ),
          child: isLoading
              ? const _ButtonSkeleton()
              : AppText.body(
              isLast ? tr('confirm_book') : tr('next_arrow_btn'),
              textAlign: TextAlign.center,
              color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    ]),
  );
}

class _ButtonSkeleton extends StatefulWidget {
  const _ButtonSkeleton();
  @override
  State<_ButtonSkeleton> createState() => _ButtonSkeletonState();
}

class _ButtonSkeletonState extends State<_ButtonSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.8)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _anim.value),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 80, height: 14,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _anim.value * 0.7),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
        ),
      ],
    ),
  );
}