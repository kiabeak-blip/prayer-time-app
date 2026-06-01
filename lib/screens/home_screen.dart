import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/custom_prayer_times.dart';
import '../models/daily_post.dart';
import '../services/content_service.dart';
import '../services/prayer_calculator.dart';
import '../services/prayer_times_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/azan_service.dart';
import '../utils/date_utils.dart';
import '../widgets/post_image.dart';
import 'post_detail_screen.dart';

// ── Hijri calendar conversion ─────────────────────────────────────────────────

class _Hijri {
  final int year, month, day;
  const _Hijri(this.year, this.month, this.day);

  static const _months = [
    'Muharram', 'Safar', "Rabi' al-Awwal", "Rabi' al-Thani",
    'Jumada al-Awwal', 'Jumada al-Thani', 'Rajab', "Sha'ban",
    'Ramadan', 'Shawwal', "Dhu al-Qi'dah", 'Dhu al-Hijjah',
  ];

  static _Hijri fromGregorian(DateTime d) {
    final y = d.year; final m = d.month; final dd = d.day;
    // Gregorian → Julian Day Number
    int jd = (1461 * (y + 4800 + (m - 14) ~/ 12)) ~/ 4 +
        (367 * (m - 2 - 12 * ((m - 14) ~/ 12))) ~/ 12 -
        (3 * ((y + 4900 + (m - 14) ~/ 12) ~/ 100)) ~/ 4 +
        dd - 32075;
    // JDN → Hijri (Kuwaiti algorithm)
    int l = jd - 1948440 + 10632;
    int n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    int j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
    int hm = (24 * l) ~/ 709;
    int hd = l - (709 * hm) ~/ 24;
    int hy = 30 * n + j - 30;
    return _Hijri(hy, hm, hd);
  }

  String get monthName => _months[month - 1];

  @override
  String toString() => '$day $monthName $year AH';
}

// ── Per-prayer visual + multilingual description data ─────────────────────────

class _PrayerVisual {
  final List<Color> gradient;
  final IconData icon;
  final String skyLabel;
  final Map<String, String> starts; // lang → description of when it begins
  final Map<String, String> ends;   // lang → description of when it ends

  const _PrayerVisual({
    required this.gradient,
    required this.icon,
    required this.skyLabel,
    required this.starts,
    required this.ends,
  });

  String startsFor(String lang) => starts[lang] ?? starts['en']!;
  String endsFor(String lang) => ends[lang] ?? ends['en']!;
}

const Map<String, _PrayerVisual> _visuals = {
  'fajr': _PrayerVisual(
    gradient: [Color(0xFF1B1464), Color(0xFF4A2070)],
    icon: Icons.brightness_3,
    skyLabel: 'Pre-Dawn',
    starts: {
      'en': 'Begins at true dawn (Fajr Ṣādiq) — when a white thread of light '
          'first stretches across the horizon, distinguishable from the darkness.',
      'sv': 'Börjar vid den sanna gryningen (Fajr Ṣādiq) — när ett vitt '
          'ljussken sträcker sig längs horisonten och kan urskiljas från mörkret.',
      'ar': 'تبدأ عند الفجر الصادق — حين يمتد خيط أبيض من النور على الأفق '
          'يتميز عن سواد الليل.',
      'am': 'ከእውነተኛ ፍርሃ (ፋጅር ሷዲቅ) ይጀምራል — የብርሃን ነጭ ክር በአድማስ ላይ ሲወጣ '
          'ከጨለማ ሲለይ።',
    },
    ends: {
      'en': 'Ends at sunrise (Shuruq).',
      'sv': 'Slutar vid soluppgången (Shuruq).',
      'ar': 'تنتهي عند شروق الشمس.',
      'am': 'ፀሐይ ስትወጣ (ሹሩቅ) ያበቃል።',
    },
  ),
  'sunrise': _PrayerVisual(
    gradient: [Color(0xFF8B2500), Color(0xFFE8600A)],
    icon: Icons.wb_twilight,
    skyLabel: 'Sunrise',
    starts: {
      'en': 'The moment the sun\'s upper limb clears the horizon.',
      'sv': 'Det ögonblick solen stiger upp ovanför horisonten.',
      'ar': 'لحظة ظهور حافة الشمس العليا فوق الأفق.',
      'am': 'ፀሐይ ከአድማስ በላይ ስትወጣ ያለው ቅጽበት።',
    },
    ends: {
      'en': 'Marks the close of Fajr time. Prayer is disliked from sunrise '
          'until the sun rises one spear\'s length (roughly 20 minutes).',
      'sv': 'Markerar slutet av Fajr-tid. Bön är ogillad från soluppgången '
          'tills solen stigit ungefär 20 minuter.',
      'ar': 'تُعلن انتهاء وقت الفجر. تُكره الصلاة عند الشروق حتى ترتفع '
          'الشمس قيد رمح (نحو ٢٠ دقيقة).',
      'am': 'የፋጅርን ጊዜ ማብቂያ ያሳያል። ፀሐይ ከወጣ ከ20 ደቂቃ ያህል ድረስ ስግደት ይጠላል።',
    },
  ),
  'dhuhr': _PrayerVisual(
    gradient: [Color(0xFFB8860B), Color(0xFFFFD700)],
    icon: Icons.wb_sunny,
    skyLabel: 'Midday',
    starts: {
      'en': 'Begins when the sun passes its zenith and declines westward '
          'from the middle of the sky.',
      'sv': 'Börjar när solen passerar sin zenit och lutar västerut '
          'från mitten av himlen.',
      'ar': 'تبدأ حين تزول الشمس عن وسط السماء وتميل غرباً.',
      'am': 'ፀሐይ ዜኒቷን አልፋ ወደ ምዕራብ ስትወዘወዝ ይጀምራል።',
    },
    ends: {
      'en': 'Ends when the shadow of any object equals its own length, plus '
          'the length of its shadow cast when the sun was at its zenith.',
      'sv': 'Slutar när ett föremåls skugga är lika lång som föremålet självt, '
          'plus skugglängden vid middagen.',
      'ar': 'تنتهي حين يساوي ظل الشيء طوله، مضافاً إليه ظله وقت الزوال.',
      'am': 'የቁሱ ጥላ ርዝማኔ ከቁሱ ርዝማኔ ጋር ሲስተካከል፣ ከቀትር ጊዜ ጥላ ጋር ተደምሮ፣ ያበቃል።',
    },
  ),
  'asr': _PrayerVisual(
    gradient: [Color(0xFFC05200), Color(0xFFFF8C42)],
    icon: Icons.sunny,
    skyLabel: 'Afternoon',
    starts: {
      'en': 'Begins immediately when Dhuhr ends — when the shadow of an object '
          'equals its own length plus its noon shadow.',
      'sv': 'Börjar direkt när Dhuhr slutar — när ett föremåls skugga är lika '
          'lång som föremålet plus middagsskuggan.',
      'ar': 'تبدأ فور انتهاء وقت الظهر — حين يساوي ظل الشيء طوله '
          'مضافاً إليه ظله الزوالي.',
      'am': 'ዙህር ሲያበቃ ወዲያው ይጀምራል — የቁሱ ጥላ ከቁሱ ርዝማኔ ጋር ሲስተካከል።',
    },
    ends: {
      'en': 'Ends at sunset.',
      'sv': 'Slutar vid solnedgången.',
      'ar': 'تنتهي بغروب الشمس.',
      'am': 'ፀሐይ ስትጠልቅ ያበቃል።',
    },
  ),
  'maghrib': _PrayerVisual(
    gradient: [Color(0xFF7B0000), Color(0xFFDD3A00)],
    icon: Icons.landscape,
    skyLabel: 'Sunset',
    starts: {
      'en': 'Begins immediately after the sun sets below the horizon.',
      'sv': 'Börjar direkt efter att solen sjunker under horisonten.',
      'ar': 'تبدأ فور غروب الشمس تحت الأفق.',
      'am': 'ፀሐይ ከአድማስ በታች ስትጠልቅ ወዲያው ይጀምራል።',
    },
    ends: {
      'en': 'Ends when the redness of twilight (shafaq aḥmar) disappears '
          'from the western horizon.',
      'sv': 'Slutar när det röda skymningsljuset (shafaq aḥmar) försvinner '
          'från den västra horisonten.',
      'ar': 'تنتهي بغياب الشفق الأحمر من ناحية الغرب.',
      'am': 'ቀይው ምሽት ደመና (ሸፈቅ አሕመር) ከምዕራብ አድማስ ሲጠፋ ያበቃል።',
    },
  ),
  'isha': _PrayerVisual(
    gradient: [Color(0xFF050A30), Color(0xFF0D1B5E)],
    icon: Icons.nightlight_round,
    skyLabel: 'Night',
    starts: {
      'en': 'Begins when the red twilight vanishes from the western horizon '
          'and true darkness falls.',
      'sv': 'Börjar när det röda skymningsljuset försvunnit från den västra '
          'horisonten och verkligt mörker infaller.',
      'ar': 'تبدأ حين يغيب الشفق الأحمر من الأفق الغربي ويحلّ الظلام الحقيقي.',
      'am': 'ቀይው ምሽት ደመና ከምዕራቡ አድማስ ሲጠፋ እና ጨለማ ሲሰፍን ይጀምራል።',
    },
    ends: {
      'en': 'Ends at the appearance of true dawn (Fajr Ṣādiq), '
          'completing the cycle of the night.',
      'sv': 'Slutar vid den sanna gryningens inträde (Fajr Ṣādiq), '
          'och avslutar nattens cykel.',
      'ar': 'تنتهي بطلوع الفجر الصادق، مكتملةً بذلك دورة الليل.',
      'am': 'እውነተኛ ፍርሃ (ፋጅር ሷዲቅ) ሲወጣ ያበቃል፣ የሌሊቱን ዑደት ሙሉ ያደርጋል።',
    },
  ),
};

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  /// Called by parent after returning from admin screen so times are refreshed.
  Future<void> refreshAdminTimes() => _fetchCustomTimes();

  /// Full refresh — re-fetches location and recalculates prayer times.
  Future<void> refresh() => _loadLocation();

  /// Called by the global AppBar language switcher.
  void setLanguage(String lang) {
    setState(() => _selectedLanguage = lang);
    SettingsService.setLanguage(lang);
  }
  _LoadState _loadState = _LoadState.loading;
  String? _errorMessage;

  Position? _position;
  String? _cityName;
  DateTime _selectedDate = DateTime.now();
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  List<DailyPost> _dailyPosts = [];
  bool _postsLoading = false;
  String _selectedLanguage = 'en';
  String _calculationMethod = 'muslimWorldLeague';
  PrayerTimesResult? _prayerTimes;
  CustomPrayerTimes? _customPrayerTimes;
  bool _showAllPrayers = false;

  _Hijri get _hijriDate => _Hijri.fromGregorian(_selectedDate);

  /// Auto-calculated times are always the base.
  /// Admin times override individual prayers when available;
  /// any prayer the admin hasn't set falls back to the auto time.
  /// So this set is always empty — no prayer is ever truly "unset".
  Set<String> get _unsetAdminPrayers => {};

  PrayerTimesResult? get _effectiveTimes {
    if (_prayerTimes == null) return null;
    // applyCustom already falls back to auto for any prayer the admin didn't set
    if (_customPrayerTimes == null || _customPrayerTimes!.isEmpty) {
      return _prayerTimes;
    }
    return _prayerTimes!.applyCustom(_customPrayerTimes!);
  }

  /// Next prayer key, skipping admin-unset prayers.
  String? get _nextPrayerKey {
    if (_effectiveTimes == null) return null;
    final unset = _unsetAdminPrayers;
    for (final e in _effectiveTimes!.ordered) {
      if (unset.contains(e.key)) continue;
      if (e.value.isAfter(_now)) return e.key;
    }
    return null;
  }

  /// Prayer list rotated so the current prayer is first, then upcoming ones,
  /// then past ones. Only rotates when viewing today.
  List<MapEntry<String, DateTime>> get _orderedFromCurrent {
    if (_effectiveTimes == null) return [];
    final all = _effectiveTimes!.ordered;
    final isToday = _selectedDate.year == _now.year &&
        _selectedDate.month == _now.month &&
        _selectedDate.day == _now.day;
    if (!isToday) return all;

    // Find the next prayer: first one still in the future
    int nextIdx = -1;
    for (int i = 0; i < all.length; i++) {
      if (all[i].value.isAfter(_now)) { nextIdx = i; break; }
    }
    if (nextIdx <= 0) return all; // next prayer is Fajr or all passed — no rotation
    return [...all.sublist(nextIdx), ...all.sublist(0, nextIdx)];
  }

  @override
  void initState() {
    super.initState();
    // Delay init until after the first frame so the activity is fully in the
    // foreground — Android silently drops permission dialogs that fire too early.
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final prev = _now;
      _now = DateTime.now();
      setState(() {});
      // Update the status-bar countdown notification once per minute
      if (_now.minute != prev.minute) _updateCountdownNotif();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final lang = await SettingsService.getLanguage();
    final method = await SettingsService.getCalculationMethod();
    if (mounted) {
      setState(() {
        _selectedLanguage = lang;
        _calculationMethod = method;
      });
    }
    await _loadLocation();
  }

  Future<void> _loadLocation() async {
    setState(() {
      _loadState = _LoadState.loading;
      _errorMessage = null;
    });

    try {
      // Step 1: check current status — never call requestPermission() blindly.
      LocationPermission permission = await Geolocator.checkPermission();

      // Step 2: ask only when genuinely not yet granted.
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // Step 3: handle outcomes.
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _loadState = _LoadState.error;
            _errorMessage =
                'Location permission permanently denied.\nEnable it in Settings → Apps → Prayer Times → Permissions.';
          });
        }
        return;
      }

      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _loadState = _LoadState.error;
            _errorMessage =
                'Location permission denied. Prayer times require your location.';
          });
        }
        return;
      }

      // Step 4: permission is granted — get position with a generous timeout
      // so we don't hang forever if GPS is slow on first fix.
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception(
            'Location timed out. Make sure GPS is enabled and try again.'),
      );

      if (!mounted) return;
      setState(() {
        _position = position;
        _loadState = _LoadState.ready;
      });
      _calculate();
      _fetchCityName(position.latitude, position.longitude);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadState = _LoadState.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _fetchCityName(double lat, double lon) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json');
      final res = await http.get(uri,
          headers: {'User-Agent': 'PrayerTimesApp/1.0'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        final city = addr?['city'] ??
            addr?['town'] ??
            addr?['village'] ??
            addr?['county'] ??
            data['display_name']?.toString().split(',').first;
        if (mounted && city != null) {
          setState(() => _cityName = city.toString());
        }
      }
    } catch (_) {}
  }

  void _calculate() {
    if (_position == null) return;
    final result = PrayerCalculator.calculate(
      latitude: _position!.latitude,
      longitude: _position!.longitude,
      date: _selectedDate,
      calculationMethod: _calculationMethod,
    );
    setState(() {
      _prayerTimes = result;
      _customPrayerTimes = null; // reset while fetching
    });
    _fetchCustomTimes();
    _rescheduleNotificationsIfToday();
    _fetchDailyPosts();
    _updateCountdownNotif();
  }

  Future<void> _fetchDailyPosts() async {
    if (mounted) setState(() => _postsLoading = true);
    try {
      final posts = await ContentService.getTodayPosts(
        userLat: _position?.latitude,
        userLng: _position?.longitude,
      );
      if (mounted) setState(() => _dailyPosts = posts);
    } catch (_) {
      // keep existing list on error
    } finally {
      if (mounted) setState(() => _postsLoading = false);
    }
  }

  /// Pushes the current next-prayer countdown to the status-bar notification.
  void _updateCountdownNotif() {
    final nextKey = _nextPrayerKey;
    if (nextKey == null || _effectiveTimes == null) {
      NotificationService.cancelCountdownNotification();
      return;
    }
    final nextEntry =
        _effectiveTimes!.ordered.firstWhere((e) => e.key == nextKey);
    final names = PrayerCalculator.getLocalizedNames(_selectedLanguage);
    NotificationService.updateCountdownNotification(
      prayerName: names[nextKey] ?? nextKey,
      prayerTime: nextEntry.value,
    );
  }

  Future<void> _fetchCustomTimes() async {
    final dateStr = _dateKey(_selectedDate);
    final custom = await PrayerTimesService.getForDate(dateStr);
    if (!mounted) return;

    // ── Location filter ──────────────────────────────────────────────────────
    // If the admin saved a location with their times, only apply those times
    // to users within the configured radius (default 50 km).
    // If no location is stored (legacy docs), apply to everyone.
    CustomPrayerTimes? filtered = custom;
    if (custom != null &&
        custom.adminLat != null &&
        custom.adminLng != null &&
        _position != null) {
      final dist = _haversineKm(
        _position!.latitude, _position!.longitude,
        custom.adminLat!, custom.adminLng!,
      );
      if (dist > custom.radiusKm) {
        filtered = null; // user is too far — fall back to calculated times
      }
    }

    setState(() => _customPrayerTimes = filtered);
    _updateAzanIfToday();
    _rescheduleNotificationsIfToday();
  }

  /// Haversine distance in kilometres between two GPS coordinates.
  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1 * math.pi / 180) *
        math.cos(lat2 * math.pi / 180) *
        math.pow(math.sin(dLon / 2), 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  void _updateAzanIfToday() {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    if (!isToday || _effectiveTimes == null) return;
    // Exclude admin-unset prayers so Azan never fires for them
    final unset = _unsetAdminPrayers;
    final times = Map<String, DateTime>.from(_effectiveTimes!.toDateTimeMap());
    for (final k in unset) times.remove(k);
    AzanService.instance.updatePrayerTimes(times);
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _rescheduleNotificationsIfToday() async {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    if (!isToday || _effectiveTimes == null) return;

    final enabled = await SettingsService.getNotificationsEnabled();
    if (!enabled) return;

    final enabledPrayers = await SettingsService.getEnabledPrayerNotifs();
    // Exclude admin-unset prayers from notifications too
    final unset = _unsetAdminPrayers;
    final times = Map<String, DateTime>.from(_effectiveTimes!.toDateTimeMap());
    for (final k in unset) times.remove(k);
    await NotificationService.schedulePrayerNotifications(
      prayerTimes: times,
      enabledPrayers: enabledPrayers,
    );
  }

  Widget _buildCountdown(ThemeData theme, Map<String, String> names) {
    final nextKey = _nextPrayerKey;
    if (nextKey == null) {
      return const SizedBox.shrink();
    }
    final nextTime = _effectiveTimes!.ordered
        .firstWhere((e) => e.key == nextKey).value;
    final diff = nextTime.difference(_now);
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    final s = diff.inSeconds.remainder(60);
    final countdown = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final visual = _visuals[nextKey];
    final color = visual?.gradient.first ?? theme.colorScheme.primary;

    return Center(
      child: Column(
        children: [
          Text(
            countdown,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w300,
              letterSpacing: 4,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_untilLabel(_selectedLanguage)} ${names[nextKey] ?? nextKey}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color.withValues(alpha: 0.8),
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCurrentAndNextCards(Map<String, String> names,
      {bool use24h = true}) {
    if (_effectiveTimes == null) return [];
    final nextKey = _nextPrayerKey;
    final unset = _unsetAdminPrayers;
    final ordered = _effectiveTimes!.ordered;

    // Current prayer = the one just before next in original order
    String? currentKey;
    if (nextKey != null) {
      final nextIdx = ordered.indexWhere((e) => e.key == nextKey);
      if (nextIdx > 0) currentKey = ordered[nextIdx - 1].key;
    } else {
      currentKey = ordered.last.key;
    }

    final cards = <Widget>[];

    for (final entry in ordered) {
      final isCurrent = entry.key == currentKey;
      final isNext    = entry.key == nextKey;

      // Default (collapsed): show only current + next
      if (!_showAllPrayers && !isCurrent && !isNext) continue;

      final isUnset = unset.contains(entry.key);
      cards.add(_PrayerCard(
        displayName: names[entry.key] ?? entry.key,
        timeStr: isUnset ? null : PrayerTimesResult.formatTime(entry.value, use24h: use24h),
        isNext: isNext,
        visual: _visuals[entry.key],
        language: _selectedLanguage,
        isCustomTime: !isUnset && _customPrayerTimes?.timeFor(entry.key) != null,
      ));
    }

    // Expand / Collapse button
    cards.add(
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _showAllPrayers = !_showAllPrayers),
            icon: Icon(
              _showAllPrayers ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              _showAllPrayers ? 'Show less' : 'Show all prayers',
              style: const TextStyle(fontSize: 13),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2E7D32),
            ),
          ),
        ),
      ),
    );

    return cards;
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _calculate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadState == _LoadState.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Getting your location…'),
          ],
        ),
      );
    }

    if (_loadState == _LoadState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final names = PrayerCalculator.getLocalizedNames(_selectedLanguage);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date picker
          ElevatedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(DateUtilsHelper.formatReadable(_selectedDate)),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // City + Hijri date
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _cityName ??
                      '${_position!.latitude.toStringAsFixed(4)}, '
                          '${_position!.longitude.toStringAsFixed(4)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.brightness_5_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                _hijriDate.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF1B3A2D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Countdown to next prayer
          if (_effectiveTimes != null) _buildCountdown(theme, names),
          const SizedBox(height: 14),

          // ── Current + Next prayer cards only ──────────────────────────
          if (_effectiveTimes != null)
            ..._buildCurrentAndNextCards(names,
                use24h: MediaQuery.alwaysUse24HourFormatOf(context)),

          // ── Today's post images ────────────────────────────────────────
          const SizedBox(height: 8),
          if (_postsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_dailyPosts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No posts for today yet.',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ),
            )
          else ...[
            ...(_dailyPosts.where((p) => p.imageUrl.isNotEmpty).map(
                  (post) => _DailyPostCard(post: post),
                )),
            if (_dailyPosts.isNotEmpty &&
                _dailyPosts.every((p) => p.imageUrl.isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    "Today's posts have no images.",
                    style:
                        TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Prayer card widget ────────────────────────────────────────────────────────

class _PrayerCard extends StatefulWidget {
  final String displayName;
  final String? timeStr; // null = admin-unset, shows '—'
  final bool isNext;
  final _PrayerVisual? visual;
  final String language;
  final bool isCustomTime;

  const _PrayerCard({
    required this.displayName,
    required this.timeStr,
    required this.isNext,
    required this.visual,
    required this.language,
    this.isCustomTime = false,
  });

  @override
  State<_PrayerCard> createState() => _PrayerCardState();
}

class _PrayerCardState extends State<_PrayerCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isNext;
  }

  @override
  void didUpdateWidget(_PrayerCard old) {
    super.didUpdateWidget(old);
    if (widget.isNext && !old.isNext) _expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final visual = widget.visual;
    final accentA = visual?.gradient.first ?? theme.colorScheme.primary;
    final accentB = visual?.gradient.last ?? theme.colorScheme.primary;

    final bgColor = Color.lerp(accentA, accentB, 0.4)!
        .withValues(alpha: isDark ? 0.22 : 0.10);
    final borderColor =
        widget.isNext ? accentA.withValues(alpha: 0.85) : Colors.transparent;

    // Use RTL text direction for Arabic
    final isRtl = widget.language == 'ar';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: bgColor,
          border: Border.all(color: borderColor, width: 1.8),
          boxShadow: widget.isNext
              ? [
                  BoxShadow(
                    color: accentA.withValues(alpha: isDark ? 0.45 : 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left sky strip ──────────────────────────────────────────
                Container(
                  width: 62,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accentA, accentB],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),
                      Icon(
                        visual?.icon ?? Icons.access_time,
                        color: Colors.white,
                        size: 26,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        visual?.skyLabel ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),

                // ── Content ─────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + time row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.displayName,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                      fontWeight: widget.isNext
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  if (widget.isNext)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [accentA, accentB],
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'Next prayer',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.isCustomTime)
                                      Tooltip(
                                        message: 'Admin-set time',
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: accentA.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                                color: accentA.withValues(alpha: 0.4),
                                                width: 0.8),
                                          ),
                                          child: Icon(Icons.admin_panel_settings,
                                              size: 11, color: accentA),
                                        ),
                                      ),
                                    Text(
                                      widget.timeStr ?? '—',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: widget.timeStr != null
                                            ? FontWeight.bold
                                            : FontWeight.w400,
                                        color: widget.timeStr != null
                                            ? accentA
                                            : Colors.grey,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Icon(
                                  _expanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                  color: accentA.withValues(alpha: 0.7),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // ── Expandable description ──────────────────────────
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 220),
                          crossFadeState: _expanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: const SizedBox(width: double.infinity),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Directionality(
                              textDirection: isRtl
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Divider(
                                    height: 1,
                                    color: accentA.withValues(alpha: 0.25),
                                  ),
                                  const SizedBox(height: 8),
                                  _DescriptionRow(
                                    label: _beginLabel(widget.language),
                                    text: visual?.startsFor(widget.language) ?? '',
                                    color: accentA,
                                  ),
                                  const SizedBox(height: 6),
                                  _DescriptionRow(
                                    label: _endLabel(widget.language),
                                    text: visual?.endsFor(widget.language) ?? '',
                                    color: accentB,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _beginLabel(String lang) {
  switch (lang) {
    case 'sv': return 'Börjar';
    case 'ar': return 'تبدأ';
    case 'am': return 'ይጀምራል';
    default:   return 'Begins';
  }
}

String _endLabel(String lang) {
  switch (lang) {
    case 'sv': return 'Slutar';
    case 'ar': return 'تنتهي';
    case 'am': return 'ያበቃል';
    default:   return 'Ends';
  }
}

String _untilLabel(String lang) {
  switch (lang) {
    case 'sv': return 'tills';
    case 'ar': return 'حتى';
    case 'am': return 'እስከ';
    default:   return 'until';
  }
}

class _DescriptionRow extends StatelessWidget {
  final String label;
  final String text;
  final Color color;

  const _DescriptionRow({
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label  ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
                TextSpan(
                  text: text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _LoadState { loading, ready, error }

// ── Image-only post card for home screen ─────────────────────────────────────

class _DailyPostCard extends StatelessWidget {
  final DailyPost post;
  const _DailyPostCard({required this.post});

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: post,
          heroTag: 'post_img_${post.id}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _open(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Full image with Hero animation
                  Hero(
                    tag: 'post_img_${post.id}',
                    child: PostImage(
                      src: post.imageUrl,
                      fit: BoxFit.contain,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  // Title bar below the image
                  if (post.title.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      color: Colors.black87,
                      child: Text(
                        post.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              // "Tap to view" hint overlay — top-right corner
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full,
                          size: 11, color: Colors.white),
                      SizedBox(width: 4),
                      Text('View',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
