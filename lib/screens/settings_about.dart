import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/area_contact.dart';
import '../services/contact_service.dart';
import '../services/location_cache.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';
import '../services/azan_service.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';

// ──────────────────────────────────────────────
// Settings Screen
// ──────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  String _language = 'en';
  String _calculationMethod = 'muslimWorldLeague';
  bool _notificationsEnabled = false;
  bool _azanEnabled = false;
  bool _azanPlaying = false;
  bool _useAdminTimes = false;
  Set<String> _enabledPrayers = SettingsService.defaultEnabledPrayers;

  /// Called by the global AppBar language switcher.
  void setLanguage(String lang) => setState(() => _language = lang);

  // ── Translations ─────────────────────────────────────────────────────────

  static const Map<String, Map<String, String>> _tr = {
    'display': {
      'en': 'Display',
      'sv': 'Visning',
      'ar': 'العرض',
      'am': 'ማሳያ',
    },
    'language': {
      'en': 'Language',
      'sv': 'Språk',
      'ar': 'اللغة',
      'am': 'ቋንቋ',
    },
    'prayer_calculation': {
      'en': 'Prayer Calculation',
      'sv': 'Bönberäkning',
      'ar': 'حساب أوقات الصلاة',
      'am': 'የሶላት ስሌት',
    },
    'calculation_method': {
      'en': 'Calculation Method',
      'sv': 'Beräkningsmetod',
      'ar': 'طريقة الحساب',
      'am': 'የስሌት ዘዴ',
    },
    'use_admin_times': {
      'en': 'Use Admin Prayer Times',
      'sv': 'Använd administratörstider',
      'ar': 'استخدام أوقات المشرف',
      'am': 'የአስተዳዳሪ ጊዜ ተጠቀም',
    },
    'admin_times_on': {
      'en': 'Showing times set by the administrator',
      'sv': 'Visar tider satta av administratören',
      'ar': 'عرض الأوقات التي حددها المشرف',
      'am': 'በአስተዳዳሪ የተቀናጀ ጊዜ እያሳየ ነው',
    },
    'admin_times_off': {
      'en': 'Showing automatically calculated times',
      'sv': 'Visar automatiskt beräknade tider',
      'ar': 'عرض الأوقات المحسوبة تلقائياً',
      'am': 'ራሱ በራሱ የተሰላ ጊዜ እያሳየ ነው',
    },
    'notifications': {
      'en': 'Notifications',
      'sv': 'Aviseringar',
      'ar': 'الإشعارات',
      'am': 'ማሳወቂያዎች',
    },
    'enable_reminders': {
      'en': 'Enable Prayer Reminders',
      'sv': 'Aktivera bönpåminnelser',
      'ar': 'تفعيل تذكير الصلاة',
      'am': 'የሶላት ማስታወሻ አንቃ',
    },
    'notify_at_prayer': {
      'en': 'Notify at each prayer time',
      'sv': 'Meddela vid varje bönstid',
      'ar': 'إشعار عند كل وقت صلاة',
      'am': 'በእያንዳንዱ የሶላት ጊዜ አሳውቅ',
    },
    'notify_denied': {
      'en': 'Notification permission denied. Enable it in app settings.',
      'sv': 'Aviseringsbehörighet nekad. Aktivera i appinställningarna.',
      'ar': 'تم رفض إذن الإشعارات. يرجى تفعيله في إعدادات التطبيق.',
      'am': 'የማሳወቂያ ፍቃድ ተከልክሏል። በመተግበሪያ ቅንብሮች ውስጥ ያስቃኙ።',
    },
    'notify_for': {
      'en': 'Notify for:',
      'sv': 'Meddela för:',
      'ar': 'إشعار لـ:',
      'am': 'ማሳወቂያ ለ:',
    },
    'azan': {
      'en': 'Azan',
      'sv': 'Azan',
      'ar': 'الأذان',
      'am': 'አዛን',
    },
    'play_azan': {
      'en': 'Play Azan at Prayer Time',
      'sv': 'Spela Azan vid bönstid',
      'ar': 'تشغيل الأذان عند وقت الصلاة',
      'am': 'በሶላት ጊዜ አዛን አጫውት',
    },
    'azan_subtitle': {
      'en': 'Audio Azan when Fajr, Dhuhr, Asr, Maghrib or Isha is due',
      'sv': 'Azan-ljud vid Fajr, Dhuhr, Asr, Maghrib eller Isha',
      'ar': 'صوت الأذان عند الفجر أو الظهر أو العصر أو المغرب أو العشاء',
      'am': 'ፋጅር፣ ዙህር፣ አሥር፣ ማግሪብ ወይም ዒሻ ሲደርስ የሰዓት አዛን',
    },
    'play_now': {
      'en': 'Play Azan Now',
      'sv': 'Spela Azan nu',
      'ar': 'تشغيل الأذان الآن',
      'am': 'አሁን አዛን አጫውት',
    },
    'stop_azan': {
      'en': 'Stop Azan',
      'sv': 'Stoppa Azan',
      'ar': 'إيقاف الأذان',
      'am': 'አዛን አቁም',
    },
  };

  static const Map<String, Map<String, String>> _prayerNames = {
    'fajr':    {'en': 'Fajr',    'sv': 'Fajr',    'ar': 'الفجر',   'am': 'ፋጅር'},
    'dhuhr':   {'en': 'Dhuhr',   'sv': 'Dhuhr',   'ar': 'الظهر',   'am': 'ዙህር'},
    'asr':     {'en': 'Asr',     'sv': 'Asr',     'ar': 'العصر',   'am': 'አሥር'},
    'maghrib': {'en': 'Maghrib', 'sv': 'Maghrib', 'ar': 'المغرب',  'am': 'ማግሪብ'},
    'isha':    {'en': 'Isha',    'sv': 'Isha',    'ar': 'العشاء',  'am': 'ዒሻ'},
  };

  static const Map<String, Map<String, String>> _langNames = {
    'en': {'en': 'English',  'sv': 'Engelska',  'ar': 'الإنجليزية', 'am': 'እንግሊዝኛ'},
    'sv': {'en': 'Swedish',  'sv': 'Svenska',   'ar': 'السويدية',   'am': 'ስዊድንኛ'},
    'ar': {'en': 'Arabic',   'sv': 'Arabiska',  'ar': 'العربية',    'am': 'አረብኛ'},
    'am': {'en': 'Amharic',  'sv': 'Amhariska', 'ar': 'الأمهرية',   'am': 'አማርኛ'},
  };

  static const _methods = {
    'muslimWorldLeague': 'Muslim World League',
    'egyptian':          'Egyptian General Authority',
    'karachi':           'University of Islamic Sciences, Karachi',
    'ummAlQura':         'Umm Al-Qura (Mecca)',
    'northAmerica':      'Islamic Society of North America',
  };

  static const _prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

  String _t(String key) => _tr[key]?[_language] ?? _tr[key]?['en'] ?? key;
  String _prayerName(String key) =>
      _prayerNames[key]?[_language] ?? _prayerNames[key]?['en'] ?? key;
  String _langName(String code) =>
      _langNames[code]?[_language] ?? _langNames[code]?['en'] ?? code;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lang = await SettingsService.getLanguage();
    final method = await SettingsService.getCalculationMethod();
    final notifEnabled = await SettingsService.getNotificationsEnabled();
    final enabledPrayers = await SettingsService.getEnabledPrayerNotifs();
    final azanEnabled = AzanService.instance.isEnabled;
    final useAdminTimes = await SettingsService.getUseAdminTimes();
    if (mounted) {
      setState(() {
        _language = lang;
        _calculationMethod = method;
        _notificationsEnabled = notifEnabled;
        _enabledPrayers = enabledPrayers;
        _azanEnabled = azanEnabled;
        _useAdminTimes = useAdminTimes;
      });
    }
  }

  void _setMethod(String? value) async {
    if (value == null) return;
    await SettingsService.setCalculationMethod(value);
    setState(() => _calculationMethod = value);
  }

  void _toggleNotifications(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('notify_denied'))),
        );
        return;
      }
    } else {
      await NotificationService.cancelAll();
    }
    await SettingsService.setNotificationsEnabled(value);
    setState(() => _notificationsEnabled = value);
  }

  void _toggleUseAdminTimes(bool value) async {
    await SettingsService.setUseAdminTimes(value);
    setState(() => _useAdminTimes = value);
  }

  void _togglePrayer(String key, bool value) async {
    final updated = Set<String>.of(_enabledPrayers);
    value ? updated.add(key) : updated.remove(key);
    await SettingsService.setEnabledPrayerNotifs(updated);
    setState(() => _enabledPrayers = updated);
  }

  void _toggleAzan(bool value) async {
    await AzanService.instance.setEnabled(value);
    setState(() => _azanEnabled = value);
  }

  Future<void> _playAzanNow() async {
    setState(() => _azanPlaying = true);
    await AzanService.instance.playNow();
    if (mounted) setState(() => _azanPlaying = false);
  }

  Future<void> _stopAzan() async {
    await AzanService.instance.stop();
    if (mounted) setState(() => _azanPlaying = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = _language == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Display ───────────────────────────────────────────────────
          _SectionHeader(_t('display')),
          ListTile(
            title: Text(_t('language')),
            subtitle: Text(_langName(_language)),
            trailing: DropdownButton<String>(
              value: _language,
              underline: const SizedBox(),
              icon: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                    value: 'en',
                    child: Text('🇬🇧', style: TextStyle(fontSize: 22))),
                DropdownMenuItem(
                    value: 'sv',
                    child: Text('🇸🇪', style: TextStyle(fontSize: 22))),
                DropdownMenuItem(
                    value: 'ar',
                    child: Text('🇸🇦', style: TextStyle(fontSize: 22))),
                DropdownMenuItem(
                    value: 'am',
                    child: Text('🇪🇹', style: TextStyle(fontSize: 22))),
              ],
              onChanged: (lang) {
                if (lang == null) return;
                setState(() => _language = lang);
                SettingsService.setLanguage(lang);
                // Notify the global AppBar via root context is not needed;
                // SettingsService persists it for next load.
              },
            ),
          ),

          const Divider(),

          // ── Prayer Calculation ────────────────────────────────────────
          _SectionHeader(_t('prayer_calculation')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              value: _calculationMethod,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t('calculation_method'),
                border: const OutlineInputBorder(),
              ),
              items: _methods.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _setMethod,
            ),
          ),
          const Divider(),

          // ── Notifications ─────────────────────────────────────────────
          _SectionHeader(_t('notifications')),
          SwitchListTile(
            title: Text(_t('enable_reminders')),
            subtitle: Text(_t('notify_at_prayer')),
            value: _notificationsEnabled,
            onChanged: _toggleNotifications,
          ),
          if (_notificationsEnabled) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: Text(
                _t('notify_for'),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
            ..._prayerKeys.map((key) => CheckboxListTile(
                  title: Text(_prayerName(key)),
                  value: _enabledPrayers.contains(key),
                  onChanged: (v) => _togglePrayer(key, v ?? false),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 32),
                )),
          ],

          const Divider(),

          // ── Azan ──────────────────────────────────────────────────────
          _SectionHeader(_t('azan')),
          SwitchListTile(
            title: Text(_t('play_azan')),
            subtitle: Text(_t('azan_subtitle')),
            value: _azanEnabled,
            onChanged: _toggleAzan,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _azanPlaying ? null : _playAzanNow,
                    icon: _azanPlaying
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_circle_outline),
                    label: Text(_t('play_now')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _stopAzan,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(_t('stop_azan')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // ── Local Admin / Mosque ───────────────────────────────────────
          _SectionHeader('Local Mosque & Contact'),
          const _LocalAdminTile(),

          const Divider(),

          // ── Contact / Support ──────────────────────────────────────────
          _SectionHeader('Contact & Support'),
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF25D366),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chat, color: Colors.white, size: 22),
            ),
            title: const Text('WhatsApp',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Chat with us for questions & support'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => launchUrl(
              Uri.parse('https://wa.me/46762214444'),
              mode: LaunchMode.externalApplication,
            ),
          ),

          const Divider(),

          // ── Admin Access ───────────────────────────────────────────────
          _SectionHeader('Admin'),
          _AdminAccessTile(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Admin access tile ─────────────────────────────────────────────────────────

class _AdminAccessTile extends StatefulWidget {
  @override
  State<_AdminAccessTile> createState() => _AdminAccessTileState();
}

class _AdminAccessTileState extends State<_AdminAccessTile> {
  bool get _isSignedIn => AuthService.instance.isSignedIn;
  String? get _email   => AuthService.instance.email;
  bool get _isSuper    => AuthService.instance.isSuperAdmin;

  void _openAdmin({bool register = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminScreen(startOnRegister: register),
      ),
    ).then((_) => setState(() {})); // refresh tile after returning
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Sign out from admin account?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) {
      AuthService.instance.signOut();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isSignedIn) {
      // Already signed in — show account info + sign-out
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFF81C784).withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings,
                      color: Color(0xFF2E7D32), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isSuper ? 'Super Admin' : 'Admin',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                  if (_isSuper)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('SUPER',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (_email != null) ...[
                const SizedBox(height: 4),
                Text(_email!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openAdmin(),
                      icon: const Icon(Icons.dashboard, size: 16),
                      label: const Text('Open Dashboard'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _signOut,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Not signed in — show request / login options
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Request access button (prominent)
          FilledButton.icon(
            onPressed: () => _openAdmin(register: true),
            icon: const Icon(Icons.how_to_reg),
            label: const Text('Request Admin Access'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          // Already have an account
          OutlinedButton.icon(
            onPressed: () => _openAdmin(register: false),
            icon: const Icon(Icons.login, size: 16),
            label: const Text('Admin Login'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Request admin access to post content, manage prayer times, '
            'and approve other admins. A super admin will review your request.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Local admin tile ──────────────────────────────────────────────────────────

class _LocalAdminTile extends StatefulWidget {
  const _LocalAdminTile();

  @override
  State<_LocalAdminTile> createState() => _LocalAdminTileState();
}

class _LocalAdminTileState extends State<_LocalAdminTile> {
  AreaContact? _contact;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final contact = await ContactService.findNearestContact(
      LocationCache.lat,
      LocationCache.lng,
    );
    if (mounted) setState(() { _contact = contact; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Looking up your local admin…',
              style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    if (_contact == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          'No local admin found for your area yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1B5E20).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF81C784).withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Area name
            Row(
              children: [
                const Icon(Icons.mosque, color: Color(0xFF2E7D32), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _contact!.areaName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ],
            ),

            // Address (if set)
            if (_contact!.address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _contact!.address,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],

            // WhatsApp button
            if (_contact!.whatsapp.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://wa.me/${_contact!.whatsapp}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.chat,
                      color: Color(0xFF25D366), size: 18),
                  label: const Text('Contact on WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// About Screen
// ──────────────────────────────────────────────

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Icon(Icons.mosque,
                size: 64, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('Prayer Times App',
                style: theme.textTheme.headlineSmall),
          ),
          Center(
            child: Text('Version 1.0.0',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ),
          const SizedBox(height: 24),
          Text('Features', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _BulletPoint(
              'Dynamic prayer time calculation for any location and date'),
          const _BulletPoint('Qibla direction with live compass and map'),
          const _BulletPoint('Prayer time notifications'),
          const _BulletPoint('Multiple calculation methods'),
          const _BulletPoint(
              'English, Swedish, Arabic, and Amharic display'),
          const _BulletPoint('Dhikr counter'),
          const SizedBox(height: 24),
          Text('Calculation Methods', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _BulletPoint('Muslim World League (default)'),
          const _BulletPoint('Egyptian General Authority of Survey'),
          const _BulletPoint('University of Islamic Sciences, Karachi'),
          const _BulletPoint('Umm Al-Qura University, Mecca'),
          const _BulletPoint('Islamic Society of North America'),
        ],
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
