import 'package:intl/intl.dart';

class DateUtilsHelper {
  /// Formats date as 'May 21, 2025'
  static String formatReadable(DateTime date) {
    return DateFormat('MMMM dd, yyyy').format(date);
  }

  /// Formats date as '2025-05-21'
  static String formatCompact(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// Localized format like 'May 21, 2025' depending on language code
  static String formatLocalized(DateTime date, String localeCode) {
    return DateFormat.yMMMMd(localeCode).format(date);
  }

  /// Formats a DateTime to a time string respecting the device's clock format.
  /// [use24h] should come from MediaQuery.alwaysUse24HourFormatOf(context).
  static String formatTime(DateTime dt, {bool use24h = true}) {
    if (use24h) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final h      = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m      = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  /// Parses a stored "HH:mm" string and reformats it per device clock format.
  static String formatTimeString(String hhmm, {bool use24h = true}) {
    if (hhmm.isEmpty) return hhmm;
    try {
      final parts = hhmm.split(':');
      final hour  = int.parse(parts[0]);
      final min   = int.parse(parts[1]);
      final dt    = DateTime(0, 1, 1, hour, min);
      return formatTime(dt, use24h: use24h);
    } catch (_) {
      return hhmm; // return as-is if parse fails
    }
  }
}
