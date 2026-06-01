import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import 'auth_service.dart';

class AdminService {
  static const _adminsCol      = 'admins';
  static const _requestsCol    = 'admin_requests';
  static const _lastCountKey   = 'sa_last_request_count';

  static Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (AuthService.instance.idToken != null)
          'Authorization': 'Bearer ${AuthService.instance.idToken}',
      };

  // ── Role ──────────────────────────────────────────────────────────────────

  /// Returns 'superadmin', 'admin', or null (not approved).
  static Future<String?> fetchRole(String email) async {
    final url = '${FirebaseConfig.collection(_adminsCol)}/${_docId(email)}';
    try {
      final res = await http.get(Uri.parse(url), headers: _authHeaders);
      if (res.statusCode == 404) return null;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final fields = data['fields'] as Map<String, dynamic>?;
        return fields?['role']?['stringValue'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// True if the admins collection has no documents yet (first setup).
  static Future<bool> noAdminsExist() async {
    final url = '${FirebaseConfig.collection(_adminsCol)}?pageSize=1';
    try {
      final res = await http.get(Uri.parse(url), headers: _authHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final docs = data['documents'] as List?;
        return docs == null || docs.isEmpty;
      }
    } catch (_) {}
    return false;
  }

  /// Create an admin document. Role must be 'superadmin' or 'admin'.
  static Future<void> createAdmin(
      String email, String displayName, String role) async {
    final url =
        '${FirebaseConfig.collection(_adminsCol)}/${_docId(email)}?'
        'updateMask.fieldPaths=email&updateMask.fieldPaths=displayName'
        '&updateMask.fieldPaths=role&updateMask.fieldPaths=createdAt';
    await http.patch(
      Uri.parse(url),
      headers: _authHeaders,
      body: jsonEncode({
        'fields': {
          'email':       {'stringValue': email},
          'displayName': {'stringValue': displayName},
          'role':        {'stringValue': role},
          'createdAt':   {'stringValue': DateTime.now().toIso8601String()},
        }
      }),
    );
  }

  // ── Registration requests ─────────────────────────────────────────────────

  /// Write a pending registration request using [token] (the new user's token).
  static Future<void> submitRequest(
      String email, String displayName, String token) async {
    final url =
        '${FirebaseConfig.collection(_requestsCol)}/${_docId(email)}?'
        'updateMask.fieldPaths=email&updateMask.fieldPaths=displayName'
        '&updateMask.fieldPaths=requestedAt&updateMask.fieldPaths=status';
    final res = await http.patch(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'fields': {
          'email':       {'stringValue': email},
          'displayName': {'stringValue': displayName},
          'requestedAt': {'stringValue': DateTime.now().toIso8601String()},
          'status':      {'stringValue': 'pending'},
        }
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Could not submit request (${res.statusCode}): ${res.body}');
    }
  }

  /// Check if an email has a pending request.
  static Future<bool> hasPendingRequest(String email) async {
    final url =
        '${FirebaseConfig.collection(_requestsCol)}/${_docId(email)}';
    try {
      final res = await http.get(Uri.parse(url), headers: _authHeaders);
      if (res.statusCode == 404) return false;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final fields = data['fields'] as Map<String, dynamic>?;
        return (fields?['status']?['stringValue'] as String?) == 'pending';
      }
    } catch (_) {}
    return false;
  }

  /// Fetch all pending requests (super admin only).
  static Future<List<Map<String, String>>> getPendingRequests() async {
    final url = FirebaseConfig.collection(_requestsCol);
    try {
      final res = await http.get(Uri.parse(url), headers: _authHeaders);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final docs = data['documents'] as List? ?? [];
      final result = <Map<String, String>>[];
      for (final doc in docs) {
        final fields = (doc as Map<String, dynamic>)['fields']
            as Map<String, dynamic>?;
        if (fields == null) continue;
        if ((fields['status']?['stringValue'] as String?) != 'pending') continue;
        result.add({
          'email':       fields['email']?['stringValue']       as String? ?? '',
          'displayName': fields['displayName']?['stringValue'] as String? ?? '',
          'requestedAt': fields['requestedAt']?['stringValue'] as String? ?? '',
        });
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Approve a request: creates admin doc, deletes request.
  static Future<void> approveRequest(
      String email, String displayName) async {
    await createAdmin(email, displayName, 'admin');
    await _deleteRequest(email);
  }

  /// Deny a request: deletes the request document.
  static Future<void> denyRequest(String email) => _deleteRequest(email);

  static Future<void> _deleteRequest(String email) async {
    final url =
        '${FirebaseConfig.collection(_requestsCol)}/${_docId(email)}';
    await http.delete(Uri.parse(url), headers: _authHeaders);
  }

  // ── Notification badge tracking ───────────────────────────────────────────

  static Future<int> getLastSeenCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastCountKey) ?? 0;
  }

  static Future<void> saveLastSeenCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCountKey, count);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Encode email safely for use as a Firestore document ID.
  /// Replaces '.' with '·' and '@' with '·at·' to avoid issues.
  static String _docId(String email) =>
      Uri.encodeComponent(email.toLowerCase());
}
