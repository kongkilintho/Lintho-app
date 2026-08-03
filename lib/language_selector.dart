// ============================================================
// language_selector.dart — LinTho App
// ============================================================

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_locale.dart';

// ✅ [Customer UX pass 2026-08-03] ຍົກ flag/ຊື່ພາສາອອກເປັນ extension ກາງ —
// ໃຫ້ບ່ອນອື່ນ (ເຊັ່ນ Profile menu trailing text) ໃຊ້ label ດຽວກັນນີ້ໄດ້ ໂດຍບໍ່
// ຕ້ອງ hardcode ຊ້ຳ. _LangTile ຍັງໃຊ້ literal ຂອງຕົນເອງຄືເກົ່າ (ບໍ່ແຕະ, ເຮັດວຽກຢູ່ແລ້ວ).
extension AppLangLabel on AppLang {
  String get flag => switch (this) {
        AppLang.lo => '🇱🇦',
        AppLang.en => '🇬🇧',
        AppLang.th => '🇹🇭',
        AppLang.zh => '🇨🇳',
      };
  String get displayName => switch (this) {
        AppLang.lo => 'ພາສາລາວ',
        AppLang.en => 'English',
        AppLang.th => 'ภาษาไทย',
        AppLang.zh => '中文',
      };
}

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const LanguageSelector(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppLocale.instance,
      builder: (context, _) {
        final current = AppLocale.instance.lang;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: C.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(tr('language'), style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: C.text)),
            const SizedBox(height: 20),
            _LangTile(
              flag: '🇱🇦', name: 'ພາສາລາວ', native: 'Lao',
              lang: AppLang.lo, selected: current == AppLang.lo,
            ),
            const SizedBox(height: 10),
            _LangTile(
              flag: '🇬🇧', name: 'English', native: 'English',
              lang: AppLang.en, selected: current == AppLang.en,
            ),
            const SizedBox(height: 10),
            _LangTile(
              flag: '🇹🇭', name: 'ภาษาไทย', native: 'Thai',
              lang: AppLang.th, selected: current == AppLang.th,
            ),
            const SizedBox(height: 10),
            _LangTile(
              flag: '🇨🇳', name: '中文', native: 'Chinese',
              lang: AppLang.zh, selected: current == AppLang.zh,
            ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }
}

class _LangTile extends StatelessWidget {
  final String  flag;
  final String  name;
  final String  native;
  final AppLang lang;
  final bool    selected;

  const _LangTile({
    required this.flag,    required this.name,
    required this.native,  required this.lang,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ GestureDetector → Material + InkWell
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppLocale.instance.setLang(lang);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color:        selected ? C.navy : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? C.navy : C.border, width: 1.5),
            boxShadow: selected
                ? [BoxShadow(
              // ✅ withOpacity → withValues
              color:      C.navy.withValues(alpha: 0.15),
              blurRadius: 8,
              offset:     const Offset(0, 3),
            )]
                : [],
          ),
          child: Row(children: [
            Text(flag, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : C.text)),
                Text(native, style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white60 : C.muted)),
              ],
            )),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: C.yellow, size: 22),
          ]),
        ),
      ),
    );
  }
}