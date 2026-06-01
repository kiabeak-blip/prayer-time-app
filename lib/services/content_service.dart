import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';
import '../models/daily_post.dart';
import 'auth_service.dart';

class ContentService {
  // ── In-memory cache (5 min TTL) ───────────────────────────────────────────
  static List<DailyPost>? _cachedPosts;
  static DateTime?        _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  static bool get _cacheValid =>
      _cachedPosts != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _cacheTtl;

  static String todayDate() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (AuthService.instance.idToken != null)
          'Authorization': 'Bearer ${AuthService.instance.idToken}',
      };

  // ── Query helpers ──────────────────────────────────────────────────────────

  static Future<List<DailyPost>> _runQuery(Map<String, dynamic> query) async {
    final res = await http.post(
      Uri.parse(FirebaseConfig.runQuery()),
      headers: _headers,
      body: jsonEncode({'structuredQuery': query}),
    );
    if (res.statusCode != 200) {
      throw Exception('Firestore query failed (${res.statusCode}): ${res.body}');
    }
    final list = jsonDecode(res.body) as List;
    return list
        .where((e) => e['document'] != null)
        .map((e) => DailyPost.fromFirestore(
            e['document'] as Map<String, dynamic>))
        .toList();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch today's posts that have reached their scheduled time.
  ///
  /// [showAll] = false (default): location-filtered — only posts whose radius
  ///   covers the user's position, plus global posts (no location set).
  /// [showAll] = true: returns every post for today regardless of location.
  static Future<List<DailyPost>> getTodayPosts({
    double? userLat,
    double? userLng,
    bool showAll = false,
  }) async {
    // Use cache if fresh; otherwise fetch and store
    List<DailyPost> posts;
    if (_cacheValid) {
      posts = _cachedPosts!;
    } else {
      posts = await _runQuery({
        'from': [
          {'collectionId': 'daily_posts'}
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'date'},
            'op': 'EQUAL',
            'value': {'stringValue': todayDate()},
          }
        },
      });
      posts.sort((a, b) => a.postedAt.compareTo(b.postedAt));
      _cachedPosts = posts;
      _cacheTime   = DateTime.now();
    }

    final now = DateTime.now();
    final timePassed = posts.where((p) {
      if (p.time.isEmpty) return true;
      final parts = p.time.split(':');
      final scheduled = DateTime(
          now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]));
      return now.isAfter(scheduled) || now.isAtSameMomentAs(scheduled);
    }).toList();

    if (showAll) return timePassed;
    return _filterByLocation(timePassed, userLat, userLng);
  }

  static List<DailyPost> _filterByLocation(
      List<DailyPost> posts, double? userLat, double? userLng) {
    final local = <({DailyPost post, double dist})>[];
    final global = <DailyPost>[];

    for (final post in posts) {
      if (!post.hasLocation) {
        global.add(post);
      } else if (userLat != null && userLng != null) {
        final dist = _haversineKm(userLat, userLng, post.locationLat, post.locationLng);
        if (dist <= post.radiusKm) {
          local.add((post: post, dist: dist));
        }
      }
      // location post but no user coords → skip (can't verify proximity)
    }

    local.sort((a, b) => a.dist.compareTo(b.dist));
    return [...local.map((e) => e.post), ...global];
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static Future<List<DailyPost>> getRecent({int limit = 30}) async {
    final posts = await _runQuery({
      'from': [
        {'collectionId': 'daily_posts'}
      ],
      'orderBy': [
        {'field': {'fieldPath': 'postedAt'}, 'direction': 'DESCENDING'}
      ],
      'limit': limit,
    });
    return posts;
  }

  static Future<void> createPost(DailyPost post) async {
    final res = await http.post(
      Uri.parse(FirebaseConfig.collection('daily_posts')),
      headers: _headers,
      body: jsonEncode(post.toFirestoreFields()),
    );
    if (res.statusCode != 200) {
      throw Exception('Create failed: ${res.body}');
    }
  }

  static Future<void> updatePost(DailyPost post) async {
    final url =
        '${FirebaseConfig.collection('daily_posts')}/${post.id}';
    final res = await http.patch(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode(post.toFirestoreFields()),
    );
    if (res.statusCode != 200) {
      throw Exception('Update failed: ${res.body}');
    }
  }

  static Future<void> deletePost(String id) async {
    final url = '${FirebaseConfig.collection('daily_posts')}/$id';
    final res = await http.delete(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200) {
      throw Exception('Delete failed: ${res.body}');
    }
  }
}
