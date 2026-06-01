import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Displays a post image from either a remote URL or a base64 data-URI.
/// Uses a StatefulWidget to cache decoded bytes so base64 is only decoded once,
/// preventing re-decoding on every parent rebuild (e.g. clock ticks).
class PostImage extends StatefulWidget {
  final String src;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;

  const PostImage({
    super.key,
    required this.src,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  State<PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<PostImage> {
  Uint8List? _bytes;
  bool _decodeError = false;

  @override
  void initState() {
    super.initState();
    _decodeIfNeeded(widget.src);
  }

  @override
  void didUpdateWidget(PostImage old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) {
      _bytes = null;
      _decodeError = false;
      _decodeIfNeeded(widget.src);
    }
  }

  void _decodeIfNeeded(String src) {
    if (!src.startsWith('data:')) return;
    try {
      final commaIdx = src.indexOf(',');
      final b64 = commaIdx >= 0 ? src.substring(commaIdx + 1) : src;
      _bytes = base64Decode(b64);
    } catch (_) {
      _decodeError = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.src.isEmpty) return const SizedBox.shrink();

    Widget img;

    if (widget.src.startsWith('data:')) {
      if (_decodeError || _bytes == null) {
        img = const SizedBox.shrink();
      } else {
        img = Image.memory(
          _bytes!,
          fit: widget.fit,
          width: double.infinity,
          height: widget.height,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      }
    } else {
      img = CachedNetworkImage(
        imageUrl: widget.src,
        fit: widget.fit,
        width: double.infinity,
        height: widget.height,
        placeholder: (_, __) => SizedBox(
          height: widget.height ?? 120,
          child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: img,
    );
  }
}
