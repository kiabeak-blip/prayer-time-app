import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _langKey = 'language';
  static const _methodKey = 'calculation_method';
  static const _notifEnabledKey = 'notifications_enabled';
  static const _notifPrayersKey = 'notif_prayers';
  static const _useAdminTimesKey = 'use_admin_times';

  static const defaultEnabledPrayers = {'fajr', 'dhuhr', 'asr', 'maghrib', 'isha'};

  // Language

  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_langKey) ?? 'en';
  }

  static Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, lang);
  }

  // Calculation method

  static Future<String> getCalculationMethod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_methodKey) ?? 'muslimWorldLeague';
  }

  static Future<void> setCalculationMethod(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_methodKey, method);
  }

  // Notifications master toggle

  static Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notifEnabledKey) ?? false;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifEnabledKey, enabled);
  }

  // Admin prayer times toggle

  static Future<bool> getUseAdminTimes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useAdminTimesKey) ?? false;
  }

  static Future<void> setUseAdminTimes(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useAdminTimesKey, value);
  }

  // Per-prayer notification toggles

  static Future<Set<String>> getEnabledPrayerNotifs() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_notifPrayersKey);
    if (stored == null) return Set.of(defaultEnabledPrayers);
    return stored.split(',').where((s) => s.isNotEmpty).toSet();
  }

  static Future<void> setEnabledPrayerNotifs(Set<String> prayers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notifPrayersKey, prayers.join(','));
  }
}
