import 'dart:convert';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';
import '../models/custom_prayer_times.dart';
import 'auth_service.dart';

class PrayerTimesService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (AuthService.instance.idToken != null)
          'Authorization': 'Bearer ${AuthService.instance.idToken}',
      };

  static String _docUrl(String date) =>
      '${FirebaseConfig.collection('custom_prayer_times')}/$date';

  /// Fetch custom times for a specific date. Returns null if none set.
  static Future<CustomPrayerTimes?> getForDate(String date) async {
    try {
      final res = await http.get(Uri.parse(_docUrl(date)));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) return null;
      final doc = jsonDecode(res.body) as Map<String, dynamic>;
      return CustomPrayerTimes.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  /// List all dates that have custom times, sorted newest first.
  static Future<List<CustomPrayerTimes>> getAll() async {
    final res = await http.post(
      Uri.parse(FirebaseConfig.runQuery()),
      headers: _headers,
      body: jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': 'custom_prayer_times'}
          ],
          'orderBy': [
            {'field': {'fieldPath': 'date'}, 'direction': 'DESCENDING'}
          ],
          'limit': 500,
        }
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Fetch failed (${res.statusCode}): ${res.body}');
    }
    final list = jsonDecode(res.body) as List;
    return list
        .where((e) => e['document'] != null)
        .map((e) =>
            CustomPrayerTimes.fromFirestore(e['document'] as Map<String, dynamic>))
        .toList();
  }

  /// Create or replace custom times for a date.
  static Future<void> save(CustomPrayerTimes times) async {
    final res = await http.patch(
      Uri.parse(_docUrl(times.date)),
      headers: _headers,
      body: jsonEncode(times.toFirestoreFields()),
    );
    if (res.statusCode != 200) {
      throw Exception('Save failed: ${res.body}');
    }
  }

  /// Delete custom times for a date.
  static Future<void> delete(String date) async {
    final res = await http.delete(
      Uri.parse(_docUrl(date)),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Delete failed: ${res.body}');
    }
  }
}
