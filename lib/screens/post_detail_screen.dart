import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/daily_post.dart';
import '../widgets/post_image.dart';

/// Detail view for a [DailyPost].
class PostDetailScreen extends StatelessWidget {
  final DailyPost post;
  final String? heroTag;

  const PostDetailScreen({super.key, required this.post, this.heroTag});

  // ── Share ────────────────────────────────────────────────────────────────────

  Future<void> _share(BuildContext context) async {
    // Build text content
    final buf = StringBuffer();
    buf.writeln(post.title);
    if (post.arabic.isNotEmpty) {
      buf.writeln();
      buf.writeln(post.arabic);
    }
    if (post.text.isNotEmpty) {
      buf.writeln();
      buf.writeln(post.text);
    }
    if (post.translation.isNotEmpty) {
      buf.writeln();
      buf.writeln(post.translation);
    }
    if (post.source.isNotEmpty) {
      buf.writeln();
      buf.writeln('— ${post.source}');
    }
    final text = buf.toString().trim();

    // If there's an image, include it in the share
    if (post.imageUrl.isNotEmpty) {
      try {
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/shared_post_${post.id}.jpg');

        if (post.imageUrl.startsWith('data:')) {
          // base64 data-URI → decode bytes directly
          final commaIdx = post.imageUrl.indexOf(',');
          final b64 = commaIdx >= 0
              ? post.imageUrl.substring(commaIdx + 1)
              : post.imageUrl;
          await file.writeAsBytes(base64Decode(b64));
        } else {
          // Remote URL → download
          final resp = await http
              .get(Uri.parse(post.imageUrl))
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
          await file.writeAsBytes(resp.bodyBytes);
        }

        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/jpeg')],
          text: text,
        );
        return;
      } catch (_) {
        // fall through to text-only share
      }
    }
    await Share.share(text);
  }

  // ── Full-screen image viewer ─────────────────────────────────────────────────

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImagePage(url: post.imageUrl),
        fullscreenDialog: true,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = _typeTheme(post.type);
    final theme  = Theme.of(context);

    // Tappable image — Hero keeps transition from list card
    Widget imageWidget = GestureDetector(
      onTap: () => _openFullScreen(context),
      child: PostImage(
        src: post.imageUrl,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.zero,
      ),
    );
    if (heroTag != null) {
      // Wrap in Hero so the card→detail transition still animates,
      // but the full-screen viewer uses a plain route (avoids Hero conflicts).
      imageWidget = Hero(tag: heroTag!, child: imageWidget);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ── Gradient app bar ─────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: colors.gradient.first,
            foregroundColor: Colors.white,
            title: Text(
              post.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              // Share button
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share',
                onPressed: () => _share(context),
              ),
              // Type badge
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${post.type.icon} ${post.type.label}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image (tap → full-screen) ────────────────────────────
                if (post.imageUrl.isNotEmpty)
                  Stack(
                    children: [
                      imageWidget,
                      // Small hint overlay bottom-right
                      Positioned(
                        right: 10,
                        bottom: 10,
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
                              Icon(Icons.zoom_out_map,
                                  size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Tap to expand',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                // ── Meta chips ───────────────────────────────────────────
                if (post.time.isNotEmpty || post.hasLocation)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (post.time.isNotEmpty)
                          _chip(
                            icon: Icons.access_time,
                            label: post.time,
                            bg: colors.border.withValues(alpha: 0.18),
                            fg: colors.accent,
                          ),
                        if (post.hasLocation)
                          _chip(
                            icon: Icons.location_on,
                            label: post.locationName.isNotEmpty
                                ? post.locationName
                                : 'Local',
                            bg: colors.border.withValues(alpha: 0.18),
                            fg: colors.accent,
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // ── Body ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Arabic
                      if (post.arabic.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colors.gradient.first
                                    .withValues(alpha: 0.08),
                                colors.gradient.last
                                    .withValues(alpha: 0.04),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: colors.border
                                    .withValues(alpha: 0.35)),
                          ),
                          child: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Text(
                              post.arabic,
                              style: TextStyle(
                                fontSize: 26,
                                height: 2.1,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Main text
                      if (post.text.isNotEmpty) ...[
                        Text(
                          post.text,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(height: 1.7),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Source
                      if (post.source.isNotEmpty) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.bookmark_outline,
                                size: 16, color: colors.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                post.source,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.accent,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Translation
                      if (post.translation.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.border.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            post.translation,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.75),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Share button at bottom
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _share(context),
                        icon: const Icon(Icons.share),
                        label: const Text('Share this post'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.accent,
                          side: BorderSide(
                              color: colors.border, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: fg)),
          ],
        ),
      );
}

// ── Full-screen image page ─────────────────────────────────────────────────────

class _FullScreenImagePage extends StatelessWidget {
  final String url;

  const _FullScreenImagePage({required this.url});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen zoomable image — tap background to close
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: SizedBox.expand(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                panEnabled: true,
                child: Center(
                  // Reuse PostImage — handles both data: URIs and network URLs
                  child: PostImage(
                    src: url,
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
            ),
          ),

          // Close button — top-left, above status bar
          Positioned(
            top: topPad + 8,
            left: 12,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Theme helper ───────────────────────────────────────────────────────────────

class _TypeTheme {
  final List<Color> gradient;
  final Color border;
  final Color accent;
  const _TypeTheme(
      {required this.gradient, required this.border, required this.accent});
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
