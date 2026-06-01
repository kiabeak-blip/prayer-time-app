import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/daily_post.dart';
import '../services/content_service.dart';
import '../services/location_cache.dart';
import '../utils/date_utils.dart';
import '../widgets/post_image.dart';
import 'post_detail_screen.dart';

class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

enum _PostFilter { nearby, all }

class _DailyScreenState extends State<DailyScreen> {
  late Future<List<DailyPost>> _future;
  double? _userLat;
  double? _userLng;
  _PostFilter _filter = _PostFilter.nearby;

  // Local cache for this screen
  static double? _cachedLat;
  static double? _cachedLng;

  @override
  void initState() {
    super.initState();
    // Restore last known position immediately
    _userLat = _cachedLat;
    _userLng = _cachedLng;
    _future = _loadPosts();
    _refreshGpsInBackground();
  }

  /// Fetches posts immediately using whatever position we already have.
  Future<List<DailyPost>> _loadPosts() {
    return ContentService.getTodayPosts(
      userLat: _userLat,
      userLng: _userLng,
      showAll: _filter == _PostFilter.all,
    );
  }

  /// Silently updates GPS in background — used on next fetch.
  void _refreshGpsInBackground() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      // Try last-known first (instant)
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _userLat = _cachedLat = LocationCache.lat = last.latitude;
        _userLng = _cachedLng = LocationCache.lng = last.longitude;
      }
      // Then get fresh position quietly
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 5));
      _userLat = _cachedLat = LocationCache.lat = fresh.latitude;
      _userLng = _cachedLng = LocationCache.lng = fresh.longitude;
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadPosts());
  }

  void _setFilter(_PostFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _future = _loadPosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter toggle ─────────────────────────────────────────────
        _FilterBar(current: _filter, onChanged: _setFilter),

        // ── Content ───────────────────────────────────────────────────
        Expanded(
          child: FutureBuilder<List<DailyPost>>(
            future: _future,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text('Could not load content: ${snap.error}',
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final posts = snap.data ?? [];

              if (posts.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    children: [
                      SizedBox(
                        height: 300,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🌙',
                                  style: TextStyle(
                                      fontSize: 56,
                                      color: Colors.grey.shade300)),
                              const SizedBox(height: 16),
                              Text(
                                _filter == _PostFilter.nearby
                                    ? 'No nearby content for today.'
                                    : 'No content for today yet.',
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              const Text('Pull down to refresh.',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: posts.length,
                  itemBuilder: (_, i) => _PostCard(post: posts[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final _PostFilter current;
  final ValueChanged<_PostFilter> onChanged;
  const _FilterBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SegmentedButton<_PostFilter>(
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.grey.shade100,
          foregroundColor: Colors.grey.shade700,
          selectedForegroundColor: Colors.white,
          selectedBackgroundColor: const Color(0xFF2E7D32),
          side: const BorderSide(color: Color(0xFF2E7D32)),
          textStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
        ),
        segments: const [
          ButtonSegment(
            value: _PostFilter.nearby,
            label: Text('📍  Nearby'),
          ),
          ButtonSegment(
            value: _PostFilter.all,
            label: Text('🌍  All Posts'),
          ),
        ],
        selected: {current},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  final DailyPost post;
  const _PostCard({required this.post});

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: post,
          heroTag: post.imageUrl.isNotEmpty ? 'daily_img_${post.id}' : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _typeTheme(post.type);

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors.gradient),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(post.type.icon,
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    post.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
                if (post.time.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time,
                            size: 11, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                            DateUtilsHelper.formatTimeString(post.time,
                                use24h: MediaQuery.alwaysUse24HourFormatOf(context)),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    post.type.label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11),
                  ),
                ),
                if (post.hasLocation) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on,
                            size: 10, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(
                          post.locationName.isNotEmpty
                              ? post.locationName
                              : 'Local',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Image — shown right below the header, above any text
          // Tapping the image opens the zoom viewer directly
          if (post.imageUrl.isNotEmpty)
            Hero(
              tag: 'daily_img_${post.id}',
              child: PostImage(
                src: post.imageUrl,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.zero,
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Arabic text
                if (post.arabic.isNotEmpty) ...[
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text(
                      post.arabic,
                      style: const TextStyle(
                          fontSize: 22,
                          height: 2.0,
                          fontWeight: FontWeight.w500),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const Divider(height: 24),
                ],

                // Main text
                Text(
                  post.text,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                ),

                // Source
                if (post.source.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.bookmark_outline,
                          size: 14, color: colors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          post.source,
                          style: TextStyle(
                              fontSize: 12,
                              color: colors.accent,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ],

                // Translation / notes
                if (post.translation.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.border.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      post.translation,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ), // GestureDetector
    );
  }

  _TypeTheme _typeTheme(PostType t) => switch (t) {
        PostType.verse => _TypeTheme(
            gradient: [const Color(0xFF1B5E20), const Color(0xFF388E3C)],
            border: const Color(0xFF81C784),
            accent: const Color(0xFF2E7D32),
          ),
        PostType.hadith => _TypeTheme(
            gradient: [const Color(0xFF4A148C), const Color(0xFF7B1FA2)],
            border: const Color(0xFFCE93D8),
            accent: const Color(0xFF6A1B9A),
          ),
        PostType.reminder => _TypeTheme(
            gradient: [const Color(0xFF1565C0), const Color(0xFF1976D2)],
            border: const Color(0xFF90CAF9),
            accent: const Color(0xFF1565C0),
          ),
        PostType.dua => _TypeTheme(
            gradient: [const Color(0xFF880E4F), const Color(0xFFC2185B)],
            border: const Color(0xFFF48FB1),
            accent: const Color(0xFF880E4F),
          ),
      };
}

class _TypeTheme {
  final List<Color> gradient;
  final Color border;
  final Color accent;
  const _TypeTheme(
      {required this.gradient, required this.border, required this.accent});
}
