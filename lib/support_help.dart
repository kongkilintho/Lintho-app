// ============================================================
// support_help.dart — LinTho
// Shared "Call Support / WhatsApp / Chat / FAQ" actions used by both the
// customer Help sheet (main.dart _showHelp) and the provider Help screen
// (profile_tab.dart HelpScreen). Contact info + FAQ content now come from
// Firestore (settings/support, faqs) via support_provider.dart — see that
// file for the schema — instead of being hardcoded here.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'support_provider.dart';
import 'theme/app_theme.dart' show AppTypography, AppRadius;

Future<void> callSupport(BuildContext context, String phone) async {
  if (phone.isEmpty) return;
  final uri = Uri.parse('tel:$phone');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('call_failed'))));
  }
}

Future<void> whatsappSupport(BuildContext context, String whatsapp) async {
  if (whatsapp.isEmpty) return;
  final uri = Uri.parse('https://wa.me/$whatsapp');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('chat_unavailable'))));
  }
}

Future<void> chatSupport(BuildContext context, String email) async {
  if (email.isEmpty) return;
  final uri = Uri.parse('mailto:$email?subject=LinTho%20Support');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('chat_unavailable'))));
  }
}

void showFaqSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // ✅ [Phase 2 / Batch C] AppRadius.sheetTop is exactly this shape
    // (BorderRadius.vertical(top: Radius.circular(sheet))) — was hand-rolled.
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Consumer(
        builder: (ctx, ref, _) {
          final faqAsync = ref.watch(faqListProvider);
          return ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: C.border, borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
              )),
              const SizedBox(height: 16),
              // ✅ fontSize+weight match AppTypography.appBarTitle exactly.
              Text(tr('faq_title'), style: AppTypography.appBarTitle),
              const SizedBox(height: 12),
              ...faqAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return [Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text(tr('faq_empty'),
                          style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: C.muted))),
                    )];
                  }
                  return _groupedFaqTiles(items);
                },
                loading: () => [const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )],
                error: (_, __) => [Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(tr('faq_load_error'),
                      style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: C.muted))),
                )],
              ),
            ],
          );
        },
      ),
    ),
  );
}

List<Widget> _groupedFaqTiles(List<FaqItem> items) {
  final widgets = <Widget>[];
  String? lastCategory;
  for (final item in items) {
    final category = item.category.isEmpty ? tr('faq_category_general') : item.category;
    if (category != lastCategory) {
      if (lastCategory != null) widgets.add(const SizedBox(height: 8));
      // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.caption.
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(category, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w800)),
      ));
      lastCategory = category;
    }
    widgets.add(ExpansionTile(
      title: Text(item.question, style: const TextStyle(
          fontWeight: FontWeight.w700, color: C.text, fontSize: 14)),
      childrenPadding: const EdgeInsets.only(bottom: 12),
      children: [
        // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.label.
        Align(
          alignment: Alignment.centerLeft,
          child: Text(item.answer, style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w400, color: C.muted, height: 1.4)),
        ),
      ],
    ));
  }
  return widgets;
}
