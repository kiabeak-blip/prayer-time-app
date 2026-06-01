import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import 'admin_service.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  String? _idToken;
  String? _email;
  String? _role; // 'superadmin' | 'admin' | null

  bool get isSignedIn  => _idToken != null;
  String? get email    => _email;
  String? get idToken  => _idToken;
  String? get role     => _role;
  bool get isSuperAdmin => _role == 'superadmin';
  bool get isAdmin      => _role == 'admin' || _role == 'superadmin';

  static const _savedEmailKey = 'saved_admin_email';

  // ── Saved email ──────────────────────────────────────────────────────────

  Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedEmailKey);
  }

  Future<void> _saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedEmailKey, email);
  }

  Future<void> clearSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedEmailKey);
  }

  // ── Sign in ──────────────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) async {
    final res = await http.post(
      Uri.parse(FirebaseConfig.authUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final msg = body['error']['message'] as String? ?? 'Login failed';
      throw Exception(_friendlyError(msg));
    }

    _idToken = body['idToken'] as String;
    _email   = body['email']   as String;

    // ── First setup: if no admins exist yet, this user becomes super admin ──
    final firstTime = await AdminService.noAdminsExist();
    if (firstTime) {
      await AdminService.createAdmin(_email!, _email!, 'superadmin');
      _role = 'superadmin';
      await _saveEmail(_email!);
      return;
    }

    // ── Normal login: fetch role from admins collection ──────────────────
    _role = await AdminService.fetchRole(_email!);
    if (_role == null) {
      // Check if they have a pending request
      final pending = await AdminService.hasPendingRequest(_email!);
      _idToken = null;
      _email   = null;
      if (pending) {
        throw Exception(
            'Your registration is pending approval by the super admin.');
      } else {
        throw Exception(
            'This account has not been approved as an admin.\n'
            'Use "Register as Admin" to submit a request.');
      }
    }

    await _saveEmail(_email!);
  }

  // ── Register new Firebase Auth user ─────────────────────────────────────

  /// Creates a Firebase Auth account. Returns the idToken of the new user.
  Future<String> register(String email, String password) async {
    final url =
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp'
        '?key=${FirebaseConfig.apiKey}';
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final msg = body['error']['message'] as String? ?? 'Registration failed';
      throw Exception(_friendlyRegisterError(msg));
    }
    return body['idToken'] as String;
  }

  // ── Sign out ─────────────────────────────────────────────────────────────

  void signOut() {
    _idToken = null;
    _email   = null;
    _role    = null;
  }

  // ── Error messages ────────────────────────────────────────────────────────

  String _friendlyError(String code) => switch (code) {
        'EMAIL_NOT_FOUND'           => 'No account found with that email.',
        'INVALID_PASSWORD'          => 'Incorrect password.',
        'USER_DISABLED'             => 'This account has been disabled.',
        'INVALID_LOGIN_CREDENTIALS' => 'Invalid email or password.',
        _                           => code,
      };

  String _friendlyRegisterError(String code) {
    if (code.startsWith('WEAK_PASSWORD')) return 'Password must be at least 6 characters.';
    return switch (code) {
      'EMAIL_EXISTS'  => 'An account with this email already exists.',
      'INVALID_EMAIL' => 'Please enter a valid email address.',
      _               => code,
    };
  }
}
