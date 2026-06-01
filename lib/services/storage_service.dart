import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';
import 'auth_service.dart';

class StorageService {
  static const _buckets = [
    '${FirebaseConfig.projectId}.firebasestorage.app',
    '${FirebaseConfig.projectId}.appspot.com',
  ];

  static String _baseUrl(String bucket) =>
      'https://firebasestorage.googleapis.com/v0/b/$bucket/o';

  /// Upload [file] to Firebase Storage, or fall back to a base64 data-URI
  /// stored directly in Firestore (works without Firebase Storage being enabled).
  static Future<String> uploadImage(File file, String path) async {
    final token = AuthService.instance.idToken;
    if (token == null) throw Exception('Not authenticated');

    final ext = file.path.toLowerCase();
    final mime = ext.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final bytes = await file.readAsBytes();
    final encoded = Uri.encodeComponent(path);

    // ── Try Firebase Storage (both bucket name formats) ──────────────────
    for (final bucket in _buckets) {
      try {
        final res = await http.post(
          Uri.parse('${_baseUrl(bucket)}?uploadType=media&name=$encoded'),
          headers: {'Content-Type': mime, 'Authorization': 'Bearer $token'},
          body: bytes,
        );

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final dlToken = data['downloadTokens'] as String;
          return '${_baseUrl(bucket)}/$encoded?alt=media&token=$dlToken';
        }

        if (res.statusCode == 404) continue; // bucket not found → try next
        throw Exception('Upload failed (${res.statusCode}): ${res.body}');
      } catch (e) {
        if (e.toString().contains('Upload failed')) rethrow;
        continue;
      }
    }

    // ── Firebase Storage not available → store as base64 data-URI ────────
    // Firestore document limit is 1 MB; base64 adds ~33%, so cap at 720 KB.
    if (bytes.length > 720 * 1024) {
      throw Exception(
        'Image is too large (${(bytes.length / 1024).round()} KB).\n'
        'Please pick a smaller image or paste a URL instead.\n'
        '(Firebase Storage is not enabled — see console.firebase.google.com → Storage)',
      );
    }

    // Encode and return as a data URI — works everywhere, no Storage needed.
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  /// Delete a file from Firebase Storage by its download URL.
  /// No-op for base64 data-URIs.
  static Future<void> deleteByUrl(String downloadUrl) async {
    if (downloadUrl.startsWith('data:')) return; // stored in Firestore, not Storage
    try {
      final token = AuthService.instance.idToken;
      if (token == null) return;
      final bucketMatch = RegExp(r'/b/([^/]+)/').firstMatch(downloadUrl);
      final bucket = bucketMatch?.group(1) ?? _buckets.first;
      final encoded = Uri.parse(downloadUrl).pathSegments.last;
      await http.delete(
        Uri.parse('${_baseUrl(bucket)}/$encoded'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {}
  }
}
