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
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                  color: C.border, borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(height: 16),
              const Text('FAQ', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
              const SizedBox(height: 12),
              ...faqAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return [Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text(tr('faq_empty'),
                          style: const TextStyle(color: C.muted, fontSize: 13))),
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
                      style: const TextStyle(color: C.muted, fontSize: 13))),
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
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(category, style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: C.muted)),
      ));
      lastCategory = category;
    }
    widgets.add(ExpansionTile(
      title: Text(item.question, style: const TextStyle(
          fontWeight: FontWeight.w700, color: C.text, fontSize: 14)),
      childrenPadding: const EdgeInsets.only(bottom: 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(item.answer, style: const TextStyle(
              color: C.muted, fontSize: 13, height: 1.4)),
        ),
      ],
    ));
  }
  return widgets;
}
