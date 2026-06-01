import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';
import '../models/area_contact.dart';
import 'auth_service.dart';

class ContactService {
  static const _fallback = '46762214444'; // central number

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (AuthService.instance.idToken != null)
          'Authorization': 'Bearer ${AuthService.instance.idToken}',
      };

  // ── Fetch all area contacts ───────────────────────────────────────────────

  static Future<List<AreaContact>> fetchAll() async {
    final res = await http.get(
      Uri.parse(FirebaseConfig.collection('area_contacts')),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final docs = body['documents'] as List? ?? [];
    return docs
        .map((d) => AreaContact.fromFirestore(d as Map<String, dynamic>))
        .toList();
  }

  // ── Find nearest WhatsApp number for a given location ────────────────────

  static Future<String> findNearest(double? lat, double? lng) async {
    final contact = await findNearestContact(lat, lng);
    return contact?.whatsapp ?? _fallback;
  }

  /// Returns the full [AreaContact] nearest to [lat]/[lng], or null if none
  /// is within range (fallback to central).
  static Future<AreaContact?> findNearestContact(
      double? lat, double? lng) async {
    if (lat == null || lng == null) return null;
    try {
      final contacts = await fetchAll();
      AreaContact? best;
      double bestDist = double.infinity;
      for (final c in contacts) {
        if (c.whatsapp.isEmpty) continue;
        final dist = _haversineKm(lat, lng, c.latitude, c.longitude);
        if (dist <= c.radiusKm && dist < bestDist) {
          bestDist = dist;
          best = c;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  // ── Admin CRUD ────────────────────────────────────────────────────────────

  /// Returns the contact owned by [email], or null if none exists.
  static Future<AreaContact?> getMyContact(String email) async {
    final all = await fetchAll();
    try {
      return all.firstWhere((c) => c.adminEmail == email);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AreaContact contact) async {
    if (contact.id.isNotEmpty) {
      // Update existing
      await http.patch(
        Uri.parse(
            '${FirebaseConfig.collection('area_contacts')}/${contact.id}'),
        headers: _headers,
        body: jsonEncode(contact.toFirestoreFields()),
      );
    } else {
      // Create new
      await http.post(
        Uri.parse(FirebaseConfig.collection('area_contacts')),
        headers: _headers,
        body: jsonEncode(contact.toFirestoreFields()),
      );
    }
  }

  static Future<void> delete(String id) async {
    await http.delete(
      Uri.parse('${FirebaseConfig.collection('area_contacts')}/$id'),
      headers: _headers,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
