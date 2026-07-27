// ============================================================
// profile_tab.dart — LinTho Provider App
//
// Fixes:
//   ✅ withOpacity → withValues(alpha:)
//   ✅ GestureDetector → Material + InkWell
//   ✅ CircularProgressIndicator → Skeleton loading
//   ✅ Image.network → errorBuilder fallback
//   ✅ Avatar upload → Cloudinary (ແທນ Firebase Storage)
//   ✅ _uploading state + _AvatarUploadingSkeleton
//   ✅ mounted check ຫຼັງ async
//   ✅ KYC upload → Cloudinary
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'Booking.dart';
import 'booking_provider.dart';
import 'cloudinary_service.dart';
import 'language_selector.dart';
import 'widgets/stat_card.dart';

// ════════════════════════════════════════════════════════════
// PROFILE TAB
// ════════════════════════════════════════════════════════════

class ProviderProfileTab extends ConsumerWidget {
  const ProviderProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        final profileAsync = ref.watch(profileStreamProvider);
        final user         = FirebaseAuth.instance.currentUser;

        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation:       0,
            centerTitle:     true,
            title: Text(tr('provider_profile'), style: const TextStyle(
              color: C.text, fontWeight: FontWeight.w800, fontSize: 18,
            )),
          ),
          body: profileAsync.when(
            loading: () => const _SkeletonProfile(),
            error:   (e, st) {
              debugPrint('profileStreamProvider error: $e\n$st');
              return _ProfileBody(profile: null, user: user);
            },
            data:    (p)     => _ProfileBody(profile: p,    user: user),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
// PROFILE BODY
// ════════════════════════════════════════════════════════════

class _ProfileBody extends ConsumerWidget {
  final ProviderProfile? profile;
  final User?            user;
  const _ProfileBody({required this.profile, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _ProfileCard(profile: p, user: user),
        const SizedBox(height: 14),
        Row(children: [
          _profileStat('${p?.totalJobs ?? 0}',         tr('total_jobs'),  Icons.work_outline,        C.navy),
          _profileStat(p?.ratingLabel         ?? '0.0', tr('reviews'),     Icons.star_rounded,        C.yellow),
          _profileStat(p?.completionRateLabel ?? '0%',  tr('completed'),   Icons.check_circle_outline, C.green),
        ]),
        const SizedBox(height: 14),
        _MenuItem(
          icon:     Icons.edit_outlined,
          label:    tr('edit_profile'),
          subtitle: tr('edit_profile_sub'),
          onTap:    () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => EditProfileScreen(profile: p, user: user),
          )),
        ),
        _MenuItem(
          icon:     Icons.build_outlined,
          label:    tr('my_services'),
          subtitle: tr('my_services_sub'),
          onTap:    () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ServicesScreen(profile: p),
          )),
        ),
        _MenuItem(
          icon:     Icons.schedule_outlined,
          label:    tr('work_schedule'),
          subtitle: tr('work_schedule_sub'),
          onTap:    () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const ScheduleScreen(),
          )),
        ),
        _MenuItem(
          icon:     Icons.reviews_outlined,
          label:    tr('reviews_comments'),
          subtitle: '${p?.totalJobs ?? 0} ${tr("reviews")} · ${p?.ratingLabel ?? '0.0'}★',
          onTap:    () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const ReviewsScreen(),
          )),
        ),
        _MenuItem(
          icon:     Icons.verified_user_outlined,
          label:    tr('kyc'),
          subtitle: _kycLabel(p?.kycStatus),
          onTap:    () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => KycScreen(profile: p),
          )),
        ),
        _MenuItem(
          icon:     Icons.language_outlined,
          label:    tr('language'),
          subtitle: _langLabel(),
          onTap:    () => LanguageSelector.show(context),
        ),
        _MenuItem(
          icon:     Icons.help_outline,
          label:    tr('help'),
          subtitle: tr('contact_support'),
          onTap:    () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const HelpScreen(),
          )),
        ),
        _MenuItem(
          icon:   Icons.logout,
          label:  tr('logout'),
          danger: true,
          onTap:  () => _confirmLogout(context),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(tr('logout'), style: const TextStyle(
          fontWeight: FontWeight.w800, color: C.text,
        )),
        content: Text(tr('confirm_logout_msg'),
            style: const TextStyle(color: C.muted, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel'),
                style: const TextStyle(color: C.muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: C.red, elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(tr('logout'), style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700,
            )),
          ),
        ],
      ),
    );
  }

  String _langLabel() => switch (AppLocale.instance.lang) {
    AppLang.lo => 'ພາສາລາວ',
    AppLang.en => 'English',
    AppLang.th => 'ภาษาไทย',
    AppLang.zh => '中文',
  };

  String _kycLabel(KycStatus? s) => switch (s) {
    KycStatus.none     => tr('kyc_none'),
    KycStatus.pending  => tr('kyc_pending'),
    KycStatus.verified => tr('kyc_verified'),
    KycStatus.rejected => tr('kyc_rejected'),
    null               => tr('kyc_none'),
  };
}

// ════════════════════════════════════════════════════════════
// PROFILE CARD
// ════════════════════════════════════════════════════════════

class _ProfileCard extends StatelessWidget {
  final ProviderProfile? profile;
  final User?            user;
  const _ProfileCard({required this.profile, required this.user});

  @override
  Widget build(BuildContext context) {
    final p    = profile;
    final name = p?.displayName.isNotEmpty == true
        ? p!.displayName
        : (user?.displayName ?? tr('provider'));

    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [C.navy, C.blue],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        Stack(alignment: Alignment.bottomRight, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color:        Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5), width: 2,
              ),
            ),
            child: p?.photoUrl != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(26),
              // 🔒 [AUDIT H-5 / 2026-07-27] cacheWidth/Height — ນີ້ແມ່ນ avatar
              // 90x90, ບໍ່ຈຳເປັນຕ້ອງ decode ຮູບເຕັມຄວາມລະອຽດເຂົ້າ memory
              child: Image.network(
                p!.photoUrl!,
                fit: BoxFit.cover,
                cacheWidth: 180, cacheHeight: 180,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(p.avatarLetter, style: const TextStyle(
                    fontSize: 36, color: Colors.white,
                    fontWeight: FontWeight.w800,
                  )),
                ),
              ),
            )
                : Center(child: Text(
                p?.avatarLetter ?? '🔧',
                style: const TextStyle(
                  fontSize: 36, color: Colors.white,
                  fontWeight: FontWeight.w800,
                ))),
          ),
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color:        C.blue,
              shape:        BoxShape.circle,
              border:       Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.camera_alt,
                color: Colors.white, size: 14),
          ),
        ]),
        const SizedBox(height: 12),
        Text(name, style: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
        )),
        Text(user?.email ?? '', style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7), fontSize: 12,
        )),
        if (p != null && p.serviceTypes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: p.serviceTypes.take(3).map((s) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:        Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(s, style: const TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
            )).toList(),
          ),
        ],
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// EDIT PROFILE SCREEN
// ════════════════════════════════════════════════════════════

class EditProfileScreen extends ConsumerStatefulWidget {
  final ProviderProfile? profile;
  final User?            user;
  const EditProfileScreen({super.key, this.profile, this.user});

  @override
  ConsumerState<EditProfileScreen> createState() =>
      _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _bioCtrl;
  late String _gender;
  // ✅ ເພີ່ມ uploading state
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final p   = widget.profile;
    _nameCtrl    = TextEditingController(
        text: p?.displayName ?? widget.user?.displayName ?? '');
    _phoneCtrl   = TextEditingController(text: p?.phone   ?? '');
    _ageCtrl     = TextEditingController(text: p?.age     ?? '');
    _addressCtrl = TextEditingController(text: p?.address ?? '');
    _bioCtrl     = TextEditingController(text: p?.bio     ?? '');
    _gender      = p?.gender ?? tr('male');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _addressCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // ✅ ໃຊ້ Cloudinary ແທນ Firebase Storage
  // 🔒 [AUDIT H-5 / 2026-07-27] ກ່ອນໜ້ານີ້ບໍ່ມີ maxWidth/maxHeight — ຮູບໂປຣໄຟລ໌
  // ຈາກກ້ອງ (ຕົວຢ່າງ 4000x3000) ຖືກອັບໂຫລດເຕັມຄວາມລະອຽດ ທັງໆທີ່ສະແດງເປັນ
  // avatar ນ້ອຍໆ (90x90) ເທົ່ານັ້ນ — ຈຳກັດ 800px ໃຫ້ກົງກັບຂະໜາດສະແດງຈິງ.
  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery, imageQuality: 75,
      maxWidth: 800, maxHeight: 800,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await CloudinaryService.instance
          .uploadProviderPhoto(File(picked.path));
      if (url == null) throw Exception('Upload failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text(tr('save_success')),
        backgroundColor: C.green,
        behavior:        SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text('${tr("error")}: $e'),
        backgroundColor: C.red,
      ));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: C.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('edit_profile'), style: const TextStyle(
          color: C.text, fontWeight: FontWeight.w800, fontSize: 18,
        )),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ✅ Avatar picker — Material + InkWell + Cloudinary
              Center(child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap:        _pickPhoto,
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(alignment: Alignment.bottomRight, children: [
                    Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        gradient:     const LinearGradient(
                            colors: [C.navy, C.blue]),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      // ✅ _uploading → skeleton
                      child: _uploading
                          ? const _AvatarUploadingSkeleton()
                          : p?.photoUrl != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.network(
                          p!.photoUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 180, cacheHeight: 180,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              p.avatarLetter,
                              style: const TextStyle(
                                fontSize: 40,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      )
                          : Center(child: Text(
                          p?.avatarLetter ?? '🔧',
                          style: const TextStyle(
                            fontSize: 40, color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ))),
                    ),
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color:        C.yellow,
                        borderRadius: BorderRadius.circular(9),
                        border:       Border.all(
                            color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: C.navy, size: 14),
                    ),
                  ]),
                ),
              )),
              const SizedBox(height: 6),
              Center(child: Text(tr('tap_change_photo'),
                  style: const TextStyle(fontSize: 11, color: C.muted))),
              const SizedBox(height: 24),

              _PField(_nameCtrl,  tr('name'),  Icons.person_outline),
              const SizedBox(height: 14),
              _PField(_phoneCtrl, tr('phone'), Icons.phone_outlined,
                  keyboard: TextInputType.phone),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _PField(_ageCtrl, tr('age'),
                    Icons.cake_outlined,
                    keyboard: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('gender'), style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: C.text,
                    )),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color:        Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: C.border, width: 1.5),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value:      _gender,
                          isExpanded: true,
                          items: [tr('male'), tr('female'), tr('other')]
                              .map((g) => DropdownMenuItem(
                              value: g, child: Text(g)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _gender = v!),
                          style: const TextStyle(
                              fontSize: 14, color: C.text),
                        ),
                      ),
                    ),
                  ],
                )),
              ]),
              const SizedBox(height: 14),
              _PField(_addressCtrl, tr('address'),
                  Icons.location_on_outlined),
              const SizedBox(height: 14),
              Text(tr('about_me'), style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: C.text,
              )),
              const SizedBox(height: 6),
              TextField(
                controller: _bioCtrl, maxLines: 4,
                style: const TextStyle(fontSize: 14, color: C.text),
                decoration: InputDecoration(
                  hintText:  tr('bio_hint'),
                  hintStyle: const TextStyle(
                      color: C.muted, fontSize: 13),
                  filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:   const BorderSide(color: C.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: C.border, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: C.sky, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () async {
                  if (_nameCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:         Text(tr('fill_all')),
                      backgroundColor: C.red,
                    ));
                    return;
                  }
                  final phone = _phoneCtrl.text.trim();
                  if (phone.isNotEmpty &&
                      !RegExp(r'^[0-9]{8,10}$').hasMatch(phone)) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:         Text(tr('invalid_phone')),
                      backgroundColor: C.red,
                    ));
                    return;
                  }
                  final age = int.tryParse(_ageCtrl.text.trim());
                  if (_ageCtrl.text.trim().isNotEmpty &&
                      (age == null || age < 1 || age > 120)) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:         Text(tr('fill_all')),
                      backgroundColor: C.red,
                    ));
                    return;
                  }
                  final ok = await ref
                      .read(profileNotifierProvider.notifier)
                      .updateProfile({
                    'displayName': _nameCtrl.text.trim(),
                    'phone':       _phoneCtrl.text.trim(),
                    'age':         _ageCtrl.text.trim(),
                    'gender':      _gender,
                    'address':     _addressCtrl.text.trim(),
                    'bio':         _bioCtrl.text.trim(),
                  });
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:         Text(
                        ok ? tr('save_success') : tr('error')),
                    backgroundColor: ok ? C.green : C.red,
                    behavior:        SnackBarBehavior.floating,
                  ));
                  if (ok) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.navy, elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(tr('save'), style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800,
                  fontSize: 16,
                )),
              )),
            ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// AVATAR UPLOADING SKELETON
// ════════════════════════════════════════════════════════════

class _AvatarUploadingSkeleton extends StatefulWidget {
  const _AvatarUploadingSkeleton();

  @override
  State<_AvatarUploadingSkeleton> createState() =>
      _AvatarUploadingSkeletonState();
}

class _AvatarUploadingSkeletonState
    extends State<_AvatarUploadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: const Center(
          child: Icon(Icons.cloud_upload_outlined,
              color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SERVICES SCREEN
// ════════════════════════════════════════════════════════════

class ServicesScreen extends ConsumerStatefulWidget {
  final ProviderProfile? profile;
  const ServicesScreen({super.key, this.profile});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  late Set<String> _selected;

  final _all = const [
    {'emoji': '❄️', 'key': 'ac_install'},
    {'emoji': '🔧', 'key': 'ac_repair'},
    {'emoji': '💧', 'key': 'ac_clean'},
    {'emoji': '🧹', 'key': 'house_clean'},
    {'emoji': '👩', 'key': 'maid'},
    {'emoji': '💄', 'key': 'beauty'},
    {'emoji': '✨', 'key': 'spa'},
    {'emoji': '💆', 'key': 'massage'},
  ];

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.profile?.serviceTypes ?? []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: C.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('my_services'), style: const TextStyle(
          color: C.text, fontWeight: FontWeight.w800, fontSize: 18,
        )),
        centerTitle: true,
      ),
      body: Column(children: [
        Expanded(child: ListView(
          padding: const EdgeInsets.all(16),
          children: _all.map((s) {
            final key  = s['key']!;
            final name = tr('svc_$key');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color:        Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                  color:      Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6, offset: const Offset(0, 2),
                )],
              ),
              child: SwitchListTile(
                secondary:   Text(s['emoji']!,
                    style: const TextStyle(fontSize: 26)),
                title:       Text(name, style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: C.text, fontSize: 14,
                )),
                value:       _selected.contains(key),
                activeColor: C.navy,
                onChanged:   (v) => setState(() =>
                v ? _selected.add(key) : _selected.remove(key)),
              ),
            );
          }).toList(),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await ref.read(profileNotifierProvider.notifier)
                      .updateProfile(
                      {'serviceTypes': _selected.toList()});
                  if (mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.navy, elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(tr('save'), style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800,
                  fontSize: 16,
                )),
              )),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SCHEDULE SCREEN
// ════════════════════════════════════════════════════════════

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedAsync = ref.watch(scheduleProvider);
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: C.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('work_schedule'), style: const TextStyle(
          color: C.text, fontWeight: FontWeight.w800, fontSize: 18,
        )),
        centerTitle: true,
      ),
      body: schedAsync.when(
        // ✅ CircularProgressIndicator → Skeleton
        loading: () => const _SkeletonList(),
        error:   (e, st) {
          debugPrint('scheduleProvider error: $e\n$st');
          return Center(child: Text(tr('load_failed')));
        },
        data:    (sched) => _ScheduleBody(sched: sched),
      ),
    );
  }
}

class _ScheduleBody extends ConsumerStatefulWidget {
  final WorkSchedule sched;
  const _ScheduleBody({required this.sched});

  @override
  ConsumerState<_ScheduleBody> createState() => _ScheduleBodyState();
}

class _ScheduleBodyState extends ConsumerState<_ScheduleBody> {
  late Map<String, bool> _days;

  @override
  void initState() {
    super.initState();
    _days = Map<String, bool>.from(widget.sched.availableDays);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.all(16),
        children: _days.entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
              color:      Colors.black.withValues(alpha: 0.04),
              blurRadius: 6, offset: const Offset(0, 2),
            )],
          ),
          child: SwitchListTile(
            title: Text(e.key, style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: C.text, fontSize: 15,
            )),
            value:       e.value,
            activeColor: C.navy,
            onChanged:   (v) => setState(() => _days[e.key] = v),
          ),
        )).toList(),
      )),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await ref.read(profileNotifierProvider.notifier)
                    .saveSchedule(WorkSchedule(
                  availableDays: _days,
                  blockedDates:  widget.sched.blockedDates,
                  workStartTime: widget.sched.workStartTime,
                  workEndTime:   widget.sched.workEndTime,
                ));
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: C.navy, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(tr('save'), style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800,
                fontSize: 16,
              )),
            )),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════
// REVIEWS SCREEN
// ════════════════════════════════════════════════════════════

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(reviewsProvider);
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: C.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('reviews_comments'), style: const TextStyle(
          color: C.text, fontWeight: FontWeight.w800, fontSize: 18,
        )),
        centerTitle: true,
      ),
      body: reviewsAsync.when(
        // ✅ CircularProgressIndicator → Skeleton
        loading: () => const _SkeletonList(),
        error:   (e, st) {
          debugPrint('reviewsProvider error: $e\n$st');
          return Center(child: Text(tr('load_failed')));
        },
        data: (reviews) => reviews.isEmpty
            ? Center(child: Text(tr('no_reviews'),
            style: const TextStyle(
                color: C.muted, fontSize: 15)))
            : ListView.builder(
          padding:     const EdgeInsets.all(16),
          itemCount:   reviews.length,
          itemBuilder: (_, i) =>
              _ReviewCard(review: reviews[i]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// KYC SCREEN — ✅ ໃຊ້ Cloudinary
// ════════════════════════════════════════════════════════════

class KycScreen extends ConsumerStatefulWidget {
  final ProviderProfile? profile;
  const KycScreen({super.key, this.profile});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: C.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('kyc'), style: const TextStyle(
          color: C.text, fontWeight: FontWeight.w800, fontSize: 18,
        )),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: widget.profile?.kycStatus == KycStatus.verified
            ? Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color:        C.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.verified_user,
                color: C.green, size: 32),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('kyc_verified'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: C.green, fontSize: 16,
                    )),
                Text(tr('kyc_verified_sub'),
                    style: const TextStyle(
                        fontSize: 13, color: C.muted)),
              ],
            )),
          ]),
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('kyc_upload_hint'),
                style: const TextStyle(
                    color: C.muted, fontSize: 14)),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _uploading ? null : () async {
                    final picker = ImagePicker();
                    final id = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 75);
                    if (!mounted) return;
                    final selfie = await picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 75);
                    if (id == null || selfie == null ||
                        !mounted) return;

                    setState(() => _uploading = true);
                    try {
                      await ref.read(profileRepoProvider)
                          .uploadKyc(
                        idPhoto:     File(id.path),
                        selfiePhoto: File(selfie.path),
                      );

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:         Text(tr('kyc_sent')),
                          backgroundColor: C.green,
                        ),
                      );
                      Navigator.pop(context);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${tr("error")}: $e'),
                          backgroundColor: C.red,
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _uploading = false);
                    }
                  },
                  icon: _uploading
                      ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2,
                      ))
                      : const Icon(Icons.upload_file,
                      color: Colors.white),
                  label: Text(
                      _uploading ? '...' : tr('kyc_upload_btn'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      )),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.navy, elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 16),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// HELP SCREEN
// ════════════════════════════════════════════════════════════

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: C.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('help'), style: const TextStyle(
          color: C.text, fontWeight: FontWeight.w800, fontSize: 18,
        )),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HelpTile(Icons.phone,         tr('call_support'),
              '020 XXXX XXXX'),
          _HelpTile(Icons.chat_outlined,  tr('chat_support'),
              'LinTho Support'),
          _HelpTile(Icons.info_outline,   'FAQ', tr('help')),
        ],
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   sub;
  const _HelpTile(this.icon, this.title, this.sub);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2),
        )],
      ),
      child: Material(
        color:        Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {},
          child: ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color:        C.navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: C.navy, size: 20),
            ),
            title:    Text(title, style: const TextStyle(
              fontWeight: FontWeight.w700, color: C.text,
            )),
            subtitle: Text(sub, style: const TextStyle(
              fontSize: 12, color: C.muted,
            )),
            trailing: const Icon(Icons.chevron_right,
                color: C.muted),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ════════════════════════════════════════════════════════════

// Same "icon + value + label" card shape as home_tab.dart's stat header —
// via the shared StatCard (lib/widgets/stat_card.dart), with overrides to
// keep this page's white-card-with-shadow look unchanged.
Widget _profileStat(String value, String label, IconData icon, Color iconColor) =>
    Expanded(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: StatCard(
        value: value,
        label: label,
        icon:  icon,
        color: iconColor,
        backgroundColor: Colors.white,
        iconColor:  iconColor,
        valueColor: C.navy,
        labelColor: C.muted,
        iconSize:      18,
        valueFontSize: 18,
        labelFontSize: 10,
        valueFontWeight: FontWeight.w800,
        padding:      const EdgeInsets.symmetric(vertical: 14),
        borderRadius: 14,
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.06),
          blurRadius: 8, offset: const Offset(0, 3),
        )],
        crossAxisAlignment: CrossAxisAlignment.center,
        iconSpacing: 4,
        valueLabelSpacing: 0,
      ),
    ));

class _MenuItem extends StatelessWidget {
  final IconData      icon;
  final String        label;
  final String?       subtitle;
  final bool          danger;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? C.red : C.navy;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: danger
            ? C.red.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: danger ? [] : [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2),
        )],
      ),
      child: Material(
        color:        Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color:        color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: danger ? C.red : C.text,
                  )),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(
                      fontSize: 11,
                      color: danger ? C.red.withValues(alpha: 0.7) : Colors.grey[600],
                    )),
                ],
              )),
              Align(
                alignment: Alignment.center,
                child: Icon(Icons.chevron_right, color: color, size: 20),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PField extends StatelessWidget {
  final TextEditingController ctrl;
  final String                label;
  final IconData              icon;
  final TextInputType?        keyboard;
  const _PField(this.ctrl, this.label, this.icon, {this.keyboard});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: C.text,
          )),
          const SizedBox(height: 6),
          TextField(
            controller:   ctrl,
            keyboardType: keyboard,
            style: const TextStyle(fontSize: 14, color: C.text),
            decoration: InputDecoration(
              prefixIcon:     Icon(icon, color: C.muted, size: 18),
              filled:         true,
              fillColor:      Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:   const BorderSide(color: C.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: C.border, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: C.sky, width: 2),
              ),
            ),
          ),
        ]);
  }
}

// ════════════════════════════════════════════════════════════
// REVIEW CARD
// ════════════════════════════════════════════════════════════

class _ReviewCard extends ConsumerStatefulWidget {
  final Review review;
  const _ReviewCard({required this.review});

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _replying = false;
  final _ctrl    = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    return Container(
      margin:  const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius:          18,
                backgroundColor: C.navy.withValues(alpha: 0.1),
                child: Text(r.customerName[0].toUpperCase(),
                    style: const TextStyle(
                        color: C.navy,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.customerName, style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: C.text, fontSize: 13,
                  )),
                  Text(r.formattedDate, style: const TextStyle(
                      fontSize: 11, color: C.muted)),
                ],
              )),
              Row(children: List.generate(5, (i) => Icon(
                i < r.rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 14, color: C.yellow,
              ))),
            ]),
            const SizedBox(height: 8),
            Text(r.comment, style: const TextStyle(
                fontSize: 13, color: C.text)),
            if (r.providerReply != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:        C.navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🔧 ',
                          style: TextStyle(fontSize: 13)),
                      Expanded(child: Text(r.providerReply!,
                          style: const TextStyle(
                              fontSize: 12, color: C.text))),
                    ]),
              ),
            ],
            if (r.providerReply == null) ...[
              if (_replying) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _ctrl, maxLines: 2,
                  decoration: InputDecoration(
                    hintText:  tr('reply_hint'),
                    hintStyle: const TextStyle(
                        color: C.muted, fontSize: 12),
                    filled: true, fillColor: C.bg,
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: C.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: C.border, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: C.sky, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _replying = false),
                        child: Text(tr('cancel'),
                            style: const TextStyle(color: C.muted)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          if (_ctrl.text.trim().isEmpty) return;
                          await ref
                              .read(profileNotifierProvider.notifier)
                              .replyToReview(r.id, _ctrl.text.trim());
                          if (mounted) setState(() => _replying = false);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: C.navy, elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                        child: Text(tr('send'), style: const TextStyle(
                          color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.w700,
                        )),
                      ),
                    ]),
              ] else
                TextButton.icon(
                  onPressed: () => setState(() => _replying = true),
                  icon:  const Icon(Icons.reply,
                      size: 14, color: C.sky),
                  label: Text(tr('reply'), style: const TextStyle(
                    color: C.sky, fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
                ),
            ],
          ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SKELETON WIDGETS
// ════════════════════════════════════════════════════════════

class _SkeletonProfile extends StatefulWidget {
  const _SkeletonProfile();

  @override
  State<_SkeletonProfile> createState() => _SkeletonProfileState();
}

class _SkeletonProfileState extends State<_SkeletonProfile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            width: double.infinity, height: 180,
            decoration: BoxDecoration(
              color: C.border.withValues(alpha: _anim.value),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: List.generate(3, (_) => Expanded(
            child: Container(
              margin:  const EdgeInsets.symmetric(horizontal: 4),
              height:  70,
              decoration: BoxDecoration(
                color: C.border.withValues(alpha: _anim.value),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ))),
          const SizedBox(height: 14),
          ...List.generate(6, (_) => Container(
            margin:  const EdgeInsets.only(bottom: 8),
            height:  64,
            decoration: BoxDecoration(
              color: C.border.withValues(alpha: _anim.value),
              borderRadius: BorderRadius.circular(14),
            ),
          )),
        ]),
      ),
    );
  }
}

class _SkeletonList extends StatefulWidget {
  const _SkeletonList();

  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.builder(
        padding:     const EdgeInsets.all(16),
        itemCount:   5,
        itemBuilder: (_, __) => Container(
          margin:  const EdgeInsets.only(bottom: 8),
          height:  64,
          decoration: BoxDecoration(
            color: C.border.withValues(alpha: _anim.value),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}