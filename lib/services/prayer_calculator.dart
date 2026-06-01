import 'package:adhan_dart/adhan_dart.dart';
import '../models/custom_prayer_times.dart';
import '../utils/date_utils.dart';

class PrayerCalculator {
  // Localized display names for each prayer key
  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'fajr': 'Fajr',
      'sunrise': 'Sunrise',
      'dhuhr': 'Dhuhr',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
    },
    'sv': {
      'fajr': 'Gryning',
      'sunrise': 'Soluppgång',
      'dhuhr': 'Dhohor',
      'asr': 'Asr',
      'maghrib': 'Solnedgång',
      'isha': 'Ishaa',
    },
    'ar': {
      'fajr': 'الفجر',
      'sunrise': 'الشروق',
      'dhuhr': 'الظهر',
      'asr': 'العصر',
      'maghrib': 'المغرب',
      'isha': 'العشاء',
    },
    'am': {
      'fajr': 'ፋጅር',
      'sunrise': 'ፀሐይ መውጣት',
      'dhuhr': 'ዙህር',
      'asr': 'አሥር',
      'maghrib': 'ማጥቢ',
      'isha': 'ዒሻ',
    },
  };

  static Map<String, String> getLocalizedNames(String lang) {
    return _translations[lang] ?? _translations['en']!;
  }

  static PrayerTimesResult calculate({
    required double latitude,
    required double longitude,
    required DateTime date,
    String calculationMethod = 'muslimWorldLeague',
  }) {
    final coordinates = Coordinates(latitude, longitude);
    final params = _getParams(calculationMethod);

    final pt = PrayerTimes(
      date: date,
      coordinates: coordinates,
      calculationParameters: params,
      precision: true,
    );

    // adhan_dart returns UTC; convert to local for display and scheduling
    return PrayerTimesResult(
      fajr: pt.fajr.toLocal(),
      sunrise: pt.sunrise.toLocal(),
      dhuhr: pt.dhuhr.toLocal(),
      asr: pt.asr.toLocal(),
      maghrib: pt.maghrib.toLocal(),
      isha: pt.isha.toLocal(),
    );
  }

  static CalculationParameters _getParams(String method) {
    switch (method) {
      case 'egyptian':
        return CalculationMethodParameters.egyptian();
      case 'karachi':
        return CalculationMethodParameters.karachi();
      case 'ummAlQura':
        return CalculationMethodParameters.ummAlQura();
      case 'northAmerica':
        return CalculationMethodParameters.northAmerica();
      default:
        return CalculationMethodParameters.muslimWorldLeague();
    }
  }
}

class PrayerTimesResult {
  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  const PrayerTimesResult({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  // Ordered list of (key, DateTime) for display
  List<MapEntry<String, DateTime>> get ordered => [
        MapEntry('fajr', fajr),
        MapEntry('sunrise', sunrise),
        MapEntry('dhuhr', dhuhr),
        MapEntry('asr', asr),
        MapEntry('maghrib', maghrib),
        MapEntry('isha', isha),
      ];

  // Returns the key of the next upcoming prayer, or null if all have passed
  String? nextPrayerKey() {
    final now = DateTime.now();
    for (final entry in ordered) {
      if (entry.value.isAfter(now)) return entry.key;
    }
    return null;
  }

  Map<String, DateTime> toDateTimeMap() => {
        'fajr': fajr,
        'sunrise': sunrise,
        'dhuhr': dhuhr,
        'asr': asr,
        'maghrib': maghrib,
        'isha': isha,
      };

  /// Formats time using the device's clock preference.
  /// Pass [use24h] from MediaQuery.alwaysUse24HourFormatOf(context).
  static String formatTime(DateTime dt, {bool use24h = true}) =>
      DateUtilsHelper.formatTime(dt, use24h: use24h);

  /// Return a new result where any prayer that has a custom time is overridden.
  PrayerTimesResult applyCustom(CustomPrayerTimes custom) {
    DateTime override(DateTime base, String key) {
      final t = custom.timeFor(key);
      if (t == null) return base;
      final parts = t.split(':');
      return DateTime(base.year, base.month, base.day,
          int.parse(parts[0]), int.parse(parts[1]));
    }

    return PrayerTimesResult(
      fajr: override(fajr, 'fajr'),
      sunrise: override(sunrise, 'sunrise'),
      dhuhr: override(dhuhr, 'dhuhr'),
      asr: override(asr, 'asr'),
      maghrib: override(maghrib, 'maghrib'),
      isha: override(isha, 'isha'),
    );
  }
}
