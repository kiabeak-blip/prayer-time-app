import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../models/area_contact.dart';
import '../models/daily_post.dart';
import '../models/custom_prayer_times.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/contact_service.dart';
import '../services/content_service.dart';
import '../services/notification_service.dart';
import '../services/prayer_times_service.dart';
import '../services/storage_service.dart';
import 'timetable_upload_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  /// When true the register form is shown immediately instead of the login form.
  final bool startOnRegister;
  const AdminScreen({super.key, this.startOnRegister = false});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  void initState() {
    super.initState();
    // If the caller requested the register page, open it after first frame
    if (widget.startOnRegister && !AuthService.instance.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const _RegisterScreen()),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService.instance.isSignedIn) {
      return _AdminDashboard(onSignOut: () => setState(() {}));
    }
    return _AdminLogin(onSignedIn: () => setState(() {}));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Login
// ─────────────────────────────────────────────────────────────────────────────

class _AdminLogin extends StatefulWidget {
  final VoidCallback onSignedIn;
  const _AdminLogin({required this.onSignedIn});

  @override
  State<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<_AdminLogin> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading  = false;
  bool _obscure  = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillEmail();
  }

  Future<void> _prefillEmail() async {
    final saved = await AuthService.instance.getSavedEmail();
    if (saved != null && mounted) {
      setState(() => _emailCtrl.text = saved);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance
          .signIn(_emailCtrl.text.trim(), _passCtrl.text);
      widget.onSignedIn();
    } catch (e) {
      setState(() =>
          _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.admin_panel_settings,
                        size: 52, color: Color(0xFF1B5E20)),
                    const SizedBox(height: 16),
                    const Text('Admin Access',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),

                    // Email
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Sign in
                    ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Sign In',
                              style: TextStyle(fontSize: 16)),
                    ),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Register link
                    OutlinedButton.icon(
                      onPressed: _goRegister,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Register as Admin'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'New admin requests need approval from the super admin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register screen
// ─────────────────────────────────────────────────────────────────────────────

class _RegisterScreen extends StatefulWidget {
  const _RegisterScreen();

  @override
  State<_RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<_RegisterScreen> {
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading  = false;
  bool _obscure  = true;
  bool _success  = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name     = _nameCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final pass     = _passCtrl.text;
    final confirm  = _confirmCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      // 1. Create Firebase Auth account → get token
      final token = await AuthService.instance.register(email, pass);
      // 2. Submit pending request using that token
      await AdminService.submitRequest(email, name, token);
      setState(() => _success = true);
    } catch (e) {
      setState(
          () => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register as Admin')),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _success ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.check_circle_outline,
            size: 72, color: Color(0xFF2E7D32)),
        const SizedBox(height: 20),
        const Text('Request Submitted!',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text(
          'Your registration request has been sent to the super admin.\n'
          'You will be able to log in once it is approved.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.person_add_outlined,
            size: 48, color: Color(0xFF1B5E20)),
        const SizedBox(height: 16),
        const Text('Create Admin Account',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Your request will be reviewed and approved by the super admin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),

        _field(_nameCtrl,  'Full Name',       Icons.person_outline,
            type: TextInputType.name),
        const SizedBox(height: 14),
        _field(_emailCtrl, 'Email',           Icons.email_outlined,
            type: TextInputType.emailAddress),
        const SizedBox(height: 14),

        // Password
        TextField(
          controller: _passCtrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _confirmCtrl,
          obscureText: _obscure,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(_error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center),
          ),
        ],

        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Submit Request',
                  style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _AdminDashboard extends StatefulWidget {
  final VoidCallback onSignOut;
  const _AdminDashboard({required this.onSignOut});

  @override
  State<_AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<_AdminDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final bool _isSuperAdmin = AuthService.instance.isSuperAdmin;
  int _pendingCount = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: _isSuperAdmin ? 4 : 3, vsync: this);
    if (_isSuperAdmin) {
      _checkPendingRequests();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkPendingRequests(),
      );
    }
  }

  Future<void> _checkPendingRequests() async {
    final requests = await AdminService.getPendingRequests();
    final count    = requests.length;
    if (!mounted) return;

    final lastSeen = await AdminService.getLastSeenCount();
    if (count > lastSeen) {
      // New requests since last check — fire local notification
      await NotificationService.showNow(
        id: 100,
        title: 'New Admin Request',
        body: count == 1
            ? '1 new admin registration request is waiting for your approval.'
            : '$count admin registration requests are waiting for your approval.',
      );
      await AdminService.saveLastSeenCount(count);
    }

    setState(() => _pendingCount = count);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Admin Dashboard'),
            const SizedBox(width: 8),
            if (_isSuperAdmin)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('SUPER',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(
                icon: Icon(Icons.article_outlined), text: 'Daily Posts'),
            const Tab(
                icon: Icon(Icons.access_time), text: 'Prayer Times'),
            const Tab(
                icon: Icon(Icons.chat), text: 'Contact'),
            if (_isSuperAdmin)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline, size: 18),
                    const SizedBox(width: 4),
                    const Text('Requests'),
                    if (_pendingCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_pendingCount',
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(AuthService.instance.email ?? '',
                      style: const TextStyle(fontSize: 11)),
                  Text(
                    _isSuperAdmin ? 'Super Admin' : 'Admin',
                    style: TextStyle(
                        fontSize: 10,
                        color: _isSuperAdmin
                            ? Colors.amber.shade300
                            : Colors.grey.shade300),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () {
              AuthService.instance.signOut();
              widget.onSignOut();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const _DailyPostsTab(),
          const _PrayerTimesTab(),
          const _ContactTab(),
          if (_isSuperAdmin)
            _RequestsTab(onCountChanged: (c) {
              if (mounted) setState(() => _pendingCount = c);
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Requests tab (super admin only)
// ─────────────────────────────────────────────────────────────────────────────

class _RequestsTab extends StatefulWidget {
  final void Function(int count) onCountChanged;
  const _RequestsTab({required this.onCountChanged});

  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  List<Map<String, String>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await AdminService.getPendingRequests();
    if (!mounted) return;
    setState(() {
      _requests = list;
      _loading  = false;
    });
    widget.onCountChanged(list.length);
    await AdminService.saveLastSeenCount(list.length);
  }

  Future<void> _approve(Map<String, String> req) async {
    final confirm = await _confirm(
        context,
        'Approve "${req['displayName']}"?',
        'They will be able to log in as a regular admin.',
        confirmLabel: 'Approve',
        confirmColor: const Color(0xFF2E7D32));
    if (confirm != true) return;
    await AdminService.approveRequest(req['email']!, req['displayName']!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${req['displayName']} approved!')));
    }
    _load();
  }

  Future<void> _deny(Map<String, String> req) async {
    final confirm = await _confirm(
        context,
        'Deny "${req['displayName']}"?',
        'Their request will be deleted and they will not be able to log in.',
        confirmLabel: 'Deny',
        confirmColor: Colors.red);
    if (confirm != true) return;
    await AdminService.denyRequest(req['email']!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${req['displayName']} denied.')));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: Colors.green.shade300),
            const SizedBox(height: 12),
            const Text('No pending requests.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _requests[i];
          final ts = r['requestedAt'] ?? '';
          String dateStr = '';
          try {
            final dt = DateTime.parse(ts).toLocal();
            dateStr = DateFormat('dd MMM yyyy, HH:mm').format(dt);
          } catch (_) {}

          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.orange.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange.shade100,
                        child: Text(
                          (r['displayName'] ?? '?')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: TextStyle(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['displayName'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            Text(r['email'] ?? '',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            if (dateStr.isNotEmpty)
                              Text('Requested: $dateStr',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _approve(r),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _deny(r),
                          icon: const Icon(Icons.close, size: 16,
                              color: Colors.red),
                          label: const Text('Deny',
                              style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily Posts tab
// ─────────────────────────────────────────────────────────────────────────────

class _DailyPostsTab extends StatefulWidget {
  const _DailyPostsTab();

  @override
  State<_DailyPostsTab> createState() => _DailyPostsTabState();
}

class _DailyPostsTabState extends State<_DailyPostsTab> {
  List<DailyPost> _posts = [];
  bool _loading = true;
  final bool _isSuperAdmin = AuthService.instance.isSuperAdmin;
  final String _myEmail    = AuthService.instance.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final posts = await ContentService.getRecent();
      if (mounted) setState(() { _posts = posts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _canEdit(DailyPost p) =>
      _isSuperAdmin || p.postedBy == _myEmail;

  Future<void> _delete(DailyPost post) async {
    final confirm = await _confirm(
        context,
        'Delete post?',
        'Delete "${post.title}"?',
        confirmLabel: 'Delete',
        confirmColor: Colors.red);
    if (confirm == true) {
      await ContentService.deletePost(post.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'quick_post',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _QuickPostEditor()));
              _load();
            },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Quick Post'),
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'full_post',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _PostEditor()));
              _load();
            },
            icon: const Icon(Icons.edit_note),
            label: const Text('Full Post'),
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? const Center(child: Text('No posts yet. Create one!'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final p = _posts[i];
                    final canEdit = _canEdit(p);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _typeColor(p.type),
                          child: Text(p.type.icon,
                              style: const TextStyle(fontSize: 18)),
                        ),
                        title: Text(p.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${p.type.label}  •  ${p.date}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (p.postedBy.isNotEmpty)
                              Text(
                                'by ${p.postedBy}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500),
                              ),
                            if (p.hasLocation) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      size: 11,
                                      color: Color(0xFF1565C0)),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      p.locationName.isNotEmpty
                                          ? '${p.locationName}  •  ${p.radiusKm.toStringAsFixed(0)} km'
                                          : '${p.radiusKm.toStringAsFixed(0)} km radius',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF1565C0)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: p.hasLocation || p.postedBy.isNotEmpty,
                        trailing: canEdit
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                _PostEditor(post: p)),
                                      );
                                      _load();
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () => _delete(p),
                                  ),
                                ],
                              )
                            : Tooltip(
                                message: 'Only the author or super admin can edit',
                                child: Icon(Icons.lock_outline,
                                    size: 18,
                                    color: Colors.grey.shade400),
                              ),
                      ),
                    );
                  },
                ),
    );
  }

  Color _typeColor(PostType t) => switch (t) {
        PostType.verse    => const Color(0xFF1B5E20),
        PostType.hadith   => const Color(0xFF4A148C),
        PostType.reminder => const Color(0xFF1565C0),
        PostType.dua      => const Color(0xFF880E4F),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact tab — each admin manages their WhatsApp area contact
// ─────────────────────────────────────────────────────────────────────────────

class _ContactTab extends StatefulWidget {
  const _ContactTab();
  @override
  State<_ContactTab> createState() => _ContactTabState();
}

class _ContactTabState extends State<_ContactTab> {
  final _nameCtrl     = TextEditingController();
  final _addressCtrl  = TextEditingController();
  final _waCtrl       = TextEditingController();
  final _radiusCtrl   = TextEditingController(text: '30');
  double? _lat;
  double? _lng;
  String  _existingId = '';
  bool    _loading    = true;
  bool    _saving     = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _waCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final email   = AuthService.instance.email ?? '';
      final contact = await ContactService.getMyContact(email);
      if (contact != null && mounted) {
        _nameCtrl.text    = contact.areaName;
        _addressCtrl.text = contact.address;
        _waCtrl.text      = contact.whatsapp;
        _radiusCtrl.text  = contact.radiusKm.toStringAsFixed(0);
        _lat              = contact.latitude;
        _lng              = contact.longitude;
        _existingId       = contact.id;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickLocation() async {
    setState(() => _error = null);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _success = 'Location set: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not get location: $e');
    }
  }

  Future<void> _save() async {
    final name    = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final wa      = _waCtrl.text.trim().replaceAll('+', '').replaceAll(' ', '');
    final radius  = double.tryParse(_radiusCtrl.text.trim()) ?? 30;

    if (name.isEmpty) { setState(() => _error = 'Enter an area name'); return; }
    if (wa.isEmpty)   { setState(() => _error = 'Enter a WhatsApp number'); return; }
    if (_lat == null) { setState(() => _error = 'Tap "Use My Location" first'); return; }

    setState(() { _saving = true; _error = null; _success = null; });
    try {
      await ContactService.save(AreaContact(
        id:         _existingId,
        areaName:   name,
        address:    address,
        whatsapp:   wa,
        latitude:   _lat!,
        longitude:  _lng!,
        radiusKm:   radius,
        adminEmail: AuthService.instance.email ?? '',
      ));
      if (mounted) setState(() { _saving = false; _success = 'Saved!'; });
      await _load();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Save failed: $e'; });
    }
  }

  Future<void> _delete() async {
    if (_existingId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete contact?'),
        content: const Text('Users in your area will fall back to the central number.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await ContactService.delete(_existingId);
    _nameCtrl.clear();
    _waCtrl.clear();
    _radiusCtrl.text = '30';
    if (mounted) setState(() { _lat = null; _lng = null; _existingId = ''; _success = 'Deleted.'; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF81C784).withValues(alpha: 0.5)),
          ),
          child: const Text(
            'Set your area WhatsApp number here.\n'
            'Users near your location will automatically be connected to you when they tap the WhatsApp button.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),

        // Area name
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Area name (e.g. Malmö)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_city),
          ),
        ),
        const SizedBox(height: 14),

        // Address — shown to users in Settings > About
        TextField(
          controller: _addressCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Address (shown to users in About)',
            hintText: 'e.g. Storgatan 12, 211 23 Malmö',
            helperText: 'Users nearby will see this as your location',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.home),
          ),
        ),
        const SizedBox(height: 14),

        // WhatsApp number
        TextField(
          controller: _waCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'WhatsApp number (e.g. 46701234567)',
            helperText: 'Include country code, no + or spaces',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.chat, color: Color(0xFF25D366)),
          ),
        ),
        const SizedBox(height: 14),

        // Radius
        TextField(
          controller: _radiusCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Coverage radius (km)',
            helperText: 'Users within this distance will be routed to you',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.radar),
          ),
        ),
        const SizedBox(height: 14),

        // Location
        OutlinedButton.icon(
          onPressed: _pickLocation,
          icon: const Icon(Icons.my_location),
          label: Text(_lat == null
              ? 'Use My Location'
              : 'Location set ✓  (${_lat!.toStringAsFixed(3)}, ${_lng!.toStringAsFixed(3)})'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _lat == null ? null : const Color(0xFF2E7D32),
            side: BorderSide(
                color: _lat == null
                    ? Colors.grey.shade400
                    : const Color(0xFF2E7D32)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_success!,
                style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 13)),
          ),

        // Save button
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('Save Contact'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),

        if (_existingId.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Remove Contact',
                style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prayer Times tab (unchanged logic, kept as-is)
// ─────────────────────────────────────────────────────────────────────────────

class _PrayerTimesTab extends StatefulWidget {
  const _PrayerTimesTab();

  @override
  State<_PrayerTimesTab> createState() => _PrayerTimesTabState();
}

class _PrayerTimesTabState extends State<_PrayerTimesTab> {
  List<CustomPrayerTimes> _entries = [];
  bool _loading = true;
  final Set<int> _selectedIndices = {};
  bool get _selecting => _selectedIndices.isNotEmpty;
  Timer? _autoRefreshTimer;
  DateTime? _lastRefreshed;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) { if (!_selecting) _loadSilent(); },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSilent() async {
    try {
      final entries = await PrayerTimesService.getAll();
      if (mounted) setState(() {
        _entries = entries;
        _lastRefreshed = DateTime.now();
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _selectedIndices.clear(); });
    try {
      final entries = await PrayerTimesService.getAll();
      if (mounted) setState(() {
        _entries = entries;
        _loading = false;
        _lastRefreshed = DateTime.now();
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelect(int i) => setState(() {
    if (_selectedIndices.contains(i)) {
      _selectedIndices.remove(i);
    } else {
      _selectedIndices.add(i);
    }
  });

  Future<void> _deleteSelected() async {
    final count = _selectedIndices.length;
    final ok = await _confirm(context, 'Delete entries?',
        'Remove $count selected day${count == 1 ? '' : 's'}? This cannot be undone.',
        confirmLabel: 'Delete', confirmColor: Colors.red);
    if (ok != true || !mounted) return;
    final toDelete = _selectedIndices.map((i) => _entries[i].date).toList();
    setState(() => _loading = true);
    for (final d in toDelete) await PrayerTimesService.delete(d);
    _load();
  }

  Future<void> _deleteSingle(CustomPrayerTimes e) async {
    final ok = await _confirm(context, 'Delete custom times?',
        'Remove admin-set times for ${e.date}?',
        confirmLabel: 'Delete', confirmColor: Colors.red);
    if (ok == true) { await PrayerTimesService.delete(e.date); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selecting
          ? AppBar(
              backgroundColor: Colors.red.shade50,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedIndices.clear()),
              ),
              title: Text('${_selectedIndices.length} selected'),
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    if (_selectedIndices.length == _entries.length) {
                      _selectedIndices.clear();
                    } else {
                      _selectedIndices.addAll(
                          List.generate(_entries.length, (i) => i));
                    }
                  }),
                  child: Text(_selectedIndices.length == _entries.length
                      ? 'Deselect all'
                      : 'Select all'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : AppBar(
              title: _lastRefreshed == null
                  ? null
                  : Text(
                      'Updated ${_lastRefreshed!.hour.toString().padLeft(2, '0')}:'
                      '${_lastRefreshed!.minute.toString().padLeft(2, '0')}:'
                      '${_lastRefreshed!.second.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
      floatingActionButton: _selecting
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'upload',
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const TimetableUploadScreen()));
                    _load();
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Timetable'),
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'manual',
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const _PrayerTimesEditor()));
                    _load();
                  },
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Manual Entry'),
                  backgroundColor: Colors.grey.shade700,
                  foregroundColor: Colors.white,
                ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.access_time, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No custom times set yet.',
                        style: TextStyle(color: Colors.grey)),
                    SizedBox(height: 4),
                    Text('Tap + to add times for a date.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ]),
                )
              : Column(
                  children: [
                    if (!_selecting)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                        child: Text(
                          'Long-press an entry to start selecting',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final e = _entries[i];
                            final isSel = _selectedIndices.contains(i);
                            return Card(
                              color: isSel ? Colors.red.shade50 : null,
                              shape: isSel
                                  ? RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      side: BorderSide(
                                          color: Colors.red.shade300,
                                          width: 1.5))
                                  : null,
                              child: ListTile(
                                onTap: _selecting
                                    ? () => _toggleSelect(i)
                                    : null,
                                onLongPress: () {
                                  if (!_selecting) _toggleSelect(i);
                                },
                                leading: _selecting
                                    ? Checkbox(
                                        value: isSel,
                                        activeColor: Colors.red,
                                        onChanged: (_) => _toggleSelect(i),
                                      )
                                    : const CircleAvatar(
                                        backgroundColor:
                                            Color(0xFF1565C0),
                                        child: Icon(Icons.access_time,
                                            color: Colors.white, size: 20),
                                      ),
                                title: Text(e.date,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(_summary(e),
                                    style:
                                        const TextStyle(fontSize: 11)),
                                isThreeLine: true,
                                trailing: _selecting
                                    ? null
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                                Icons.edit_outlined),
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        _PrayerTimesEditor(
                                                            existing: e)),
                                              );
                                              _load();
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red),
                                            onPressed: () =>
                                                _deleteSingle(e),
                                          ),
                                        ],
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _summary(CustomPrayerTimes e) {
    final p = <String>[];
    if (e.fajr.isNotEmpty)    p.add('Fajr ${e.fajr}');
    if (e.dhuhr.isNotEmpty)   p.add('Dhuhr ${e.dhuhr}');
    if (e.asr.isNotEmpty)     p.add('Asr ${e.asr}');
    if (e.maghrib.isNotEmpty) p.add('Maghrib ${e.maghrib}');
    if (e.isha.isNotEmpty)    p.add('Isha ${e.isha}');
    if (e.sunrise.isNotEmpty) p.add('Sunrise ${e.sunrise}');
    return p.join('  ·  ');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prayer Times editor
// ─────────────────────────────────────────────────────────────────────────────

class _PrayerTimesEditor extends StatefulWidget {
  final CustomPrayerTimes? existing;
  const _PrayerTimesEditor({this.existing});

  @override
  State<_PrayerTimesEditor> createState() => _PrayerTimesEditorState();
}

class _PrayerTimesEditorState extends State<_PrayerTimesEditor> {
  late String _date;
  late Map<String, String> _times;
  bool _saving = false;

  static const _keys   = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
  static const _labels = {
    'fajr': 'Fajr', 'sunrise': 'Sunrise', 'dhuhr': 'Dhuhr',
    'asr': 'Asr', 'maghrib': 'Maghrib', 'isha': 'Isha',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date  = e?.date ?? _today();
    _times = {
      'fajr':    e?.fajr    ?? '',
      'sunrise': e?.sunrise ?? '',
      'dhuhr':   e?.dhuhr   ?? '',
      'asr':     e?.asr     ?? '',
      'maghrib': e?.maghrib ?? '',
      'isha':    e?.isha    ?? '',
    };
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  Future<void> _pickTime(String key) async {
    final cur = _times[key]!;
    final initial = cur.isNotEmpty
        ? TimeOfDay(
            hour:   int.parse(cur.split(':')[0]),
            minute: int.parse(cur.split(':')[1]))
        : TimeOfDay.now();
    final picked =
        await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      setState(() => _times[key] =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // Get the admin's current GPS location to scope these times by radius.
    double? adminLat, adminLng;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(const Duration(seconds: 10));
        adminLat = pos.latitude;
        adminLng = pos.longitude;
      }
    } catch (_) {
      // Location unavailable — save without location (applies to all users)
    }

    final entry = CustomPrayerTimes(
      date:     _date,
      fajr:     _times['fajr']!,
      sunrise:  _times['sunrise']!,
      dhuhr:    _times['dhuhr']!,
      asr:      _times['asr']!,
      maghrib:  _times['maghrib']!,
      isha:     _times['isha']!,
      adminLat: adminLat,
      adminLng: adminLng,
      radiusKm: 50,
    );
    try {
      await PrayerTimesService.save(entry);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'),
                backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.existing != null ? 'Edit Prayer Times' : 'Set Prayer Times'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Date',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(_date),
          ),
          const SizedBox(height: 8),
          Text(
            'Leave a time empty to use the calculated value for that prayer.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          ..._keys.map((key) => _PrayerTimeRow(
                label:   _labels[key]!,
                value:   _times[key]!,
                onPick:  () => _pickTime(key),
                onClear: () => setState(() => _times[key] = ''),
              )),
        ],
      ),
    );
  }
}

class _PrayerTimeRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _PrayerTimeRow({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isSet = value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPick,
              icon: Icon(Icons.access_time,
                  size: 16,
                  color: isSet ? const Color(0xFF1565C0) : Colors.grey),
              label: Text(
                isSet ? value : 'Not set (use calculated)',
                style: TextStyle(
                    color: isSet ? const Color(0xFF1565C0) : Colors.grey),
              ),
            ),
          ),
          if (isSet) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear, size: 18, color: Colors.red),
              tooltip: 'Clear (use calculated)',
              onPressed: onClear,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full Post editor
// ─────────────────────────────────────────────────────────────────────────────

class _PostEditor extends StatefulWidget {
  final DailyPost? post;
  const _PostEditor({this.post});

  @override
  State<_PostEditor> createState() => _PostEditorState();
}

class _PostEditorState extends State<_PostEditor> {
  late PostType _type;
  late String _date;
  String _time = '';
  final _titleCtrl       = TextEditingController();
  final _arabicCtrl      = TextEditingController();
  final _textCtrl        = TextEditingController();
  final _sourceCtrl      = TextEditingController();
  final _translationCtrl = TextEditingController();
  final _imageUrlCtrl    = TextEditingController();
  bool _saving = false;
  File? _pickedImage;
  String _existingImageUrl = '';
  final _picker = ImagePicker();

  double _locationLat = 0.0;
  double _locationLng = 0.0;
  final _locationNameCtrl = TextEditingController();
  double _radiusKm = 50.0;
  bool _detectingLocation = false;

  bool get _hasLocation =>
      _radiusKm > 0 && (_locationLat != 0 || _locationLng != 0);

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    _type              = p?.type ?? PostType.verse;
    _date              = p?.date ?? ContentService.todayDate();
    _time              = p?.time ?? '';
    _titleCtrl.text       = p?.title       ?? '';
    _arabicCtrl.text      = p?.arabic      ?? '';
    _textCtrl.text        = p?.text        ?? '';
    _sourceCtrl.text      = p?.source      ?? '';
    _translationCtrl.text = p?.translation ?? '';
    _existingImageUrl  = p?.imageUrl ?? '';
    _locationLat       = p?.locationLat ?? 0.0;
    _locationLng       = p?.locationLng ?? 0.0;
    _locationNameCtrl.text = p?.locationName ?? '';
    _radiusKm          = (p?.radiusKm ?? 0.0) > 0 ? p!.radiusKm : 50.0;
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _arabicCtrl.dispose(); _textCtrl.dispose();
    _sourceCtrl.dispose(); _translationCtrl.dispose();
    _locationNameCtrl.dispose(); _imageUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    setState(() => _detectingLocation = true);
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.low));
      if (mounted) setState(() {
        _locationLat = pos.latitude;
        _locationLng = pos.longitude;
        if (_locationNameCtrl.text.isEmpty) {
          _locationNameCtrl.text =
              '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')));
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (x != null && mounted) setState(() => _pickedImage = File(x.path));
  }

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 85);
    if (x != null && mounted) setState(() => _pickedImage = File(x.path));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  Future<void> _pickTime() async {
    final init = _time.isNotEmpty
        ? TimeOfDay(
            hour:   int.parse(_time.split(':')[0]),
            minute: int.parse(_time.split(':')[1]))
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked != null) {
      setState(() => _time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _textCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Title and main text are required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      String imageUrl = _existingImageUrl;
      if (_pickedImage != null) {
        imageUrl = await StorageService.uploadImage(
            _pickedImage!,
            'daily_posts/${DateTime.now().millisecondsSinceEpoch}.jpg');
      } else if (_imageUrlCtrl.text.trim().isNotEmpty) {
        imageUrl = _imageUrlCtrl.text.trim();
      }

      final post = DailyPost(
        id:           widget.post?.id,
        type:         _type,
        date:         _date,
        time:         _time,
        title:        _titleCtrl.text.trim(),
        arabic:       _arabicCtrl.text.trim(),
        text:         _textCtrl.text.trim(),
        source:       _sourceCtrl.text.trim(),
        translation:  _translationCtrl.text.trim(),
        imageUrl:     imageUrl,
        postedAt:     widget.post?.postedAt ?? DateTime.now(),
        postedBy:     widget.post?.postedBy ?? AuthService.instance.email ?? '',
        locationLat:  _hasLocation ? _locationLat : 0.0,
        locationLng:  _hasLocation ? _locationLng : 0.0,
        locationName: _hasLocation ? _locationNameCtrl.text.trim() : '',
        radiusKm:     _hasLocation ? _radiusKm : 0.0,
      );
      if (widget.post == null) {
        await ContentService.createPost(post);
      } else {
        await ContentService.updatePost(post);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.post != null ? 'Edit Post' : 'New Post'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Type',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: PostType.values
                  .map((t) => ChoiceChip(
                        label: Text('${t.icon} ${t.label}'),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                        selectedColor: const Color(0xFF2E7D32),
                        labelStyle: TextStyle(
                            color: _type == t ? Colors.white : null),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text('Date & Time',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_date),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text(_time.isEmpty ? 'No time' : _time),
                ),
                if (_time.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () => setState(() => _time = ''),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            _field(_titleCtrl, 'Title *', 'e.g. Ayah of the Day'),
            const SizedBox(height: 16),
            if (_type == PostType.verse || _type == PostType.dua) ...[
              _field(_arabicCtrl, 'Arabic text', '', rtl: true, maxLines: 4),
              const SizedBox(height: 16),
            ],
            _field(_textCtrl, 'Main text / Translation *', '',
                maxLines: 5),
            const SizedBox(height: 16),
            if (_type != PostType.reminder) ...[
              _field(_sourceCtrl, 'Source / Reference',
                  _type == PostType.hadith
                      ? 'e.g. Sahih Bukhari 6502'
                      : 'e.g. Surah Al-Baqarah 2:255'),
              const SizedBox(height: 16),
            ],
            if (_type == PostType.hadith) ...[
              _field(_translationCtrl, 'Additional notes', '',
                  maxLines: 3),
              const SizedBox(height: 16),
            ],

            // Location
            const Text('Location (optional)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Tag this post to a location. Leave unset to show everyone.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            if (_hasLocation) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 16, color: Color(0xFF1565C0)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_locationLat.toStringAsFixed(5)}, '
                            '${_locationLng.toStringAsFixed(5)}',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF1565C0)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: Colors.red),
                          onPressed: () => setState(() {
                            _locationLat = 0;
                            _locationLng = 0;
                            _locationNameCtrl.clear();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _locationNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Location name',
                        hintText: 'e.g. Mosque Al-Noor, Stockholm',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.place_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text('Radius:',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        DropdownButton<double>(
                          value: _radiusKm,
                          isDense: true,
                          items: const [
                            DropdownMenuItem(value: 10, child: Text('10 km')),
                            DropdownMenuItem(value: 25, child: Text('25 km')),
                            DropdownMenuItem(value: 50, child: Text('50 km')),
                            DropdownMenuItem(value: 100, child: Text('100 km')),
                            DropdownMenuItem(value: 250, child: Text('250 km')),
                            DropdownMenuItem(value: 500, child: Text('500 km')),
                          ],
                          onChanged: (v) => setState(() => _radiusKm = v ?? 50),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _detectingLocation ? null : _detectLocation,
                icon: _detectingLocation
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 16),
                label: const Text('Update with current GPS'),
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _detectingLocation ? null : _detectLocation,
                icon: _detectingLocation
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_location_alt_outlined, size: 16),
                label: const Text('Add my location'),
              ),
            ],
            const SizedBox(height: 20),

            // Image
            const Text('Image (optional)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _imageSection(),
            const SizedBox(height: 6),
            Text(
              'Tip: if Gallery upload fails, enable Firebase Storage at\n'
              'console.firebase.google.com → Storage → Get started',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _imageSection() {
    if (_pickedImage != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(_pickedImage!,
              height: 180, fit: BoxFit.cover, width: double.infinity),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _pickedImage = null),
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          label: const Text('Remove', style: TextStyle(color: Colors.red)),
        ),
      ]);
    }
    if (_existingImageUrl.isNotEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(_existingImageUrl,
              height: 180, fit: BoxFit.cover, width: double.infinity),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _existingImageUrl = ''),
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          label: const Text('Remove', style: TextStyle(color: Colors.red)),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: const Text('Gallery'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: const Text('Camera'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _imageUrlCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Or paste image URL (https://…)',
          prefixIcon: const Icon(Icons.link, size: 18),
          suffixIcon: _imageUrlCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () => setState(() => _imageUrlCtrl.clear()),
                )
              : null,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    ]);
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      {int maxLines = 1, bool rtl = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Post editor
// ─────────────────────────────────────────────────────────────────────────────

class _QuickPostEditor extends StatefulWidget {
  const _QuickPostEditor();

  @override
  State<_QuickPostEditor> createState() => _QuickPostEditorState();
}

class _QuickPostEditorState extends State<_QuickPostEditor> {
  PostType _type = PostType.reminder;
  final _titleCtrl    = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  File? _pickedImage;
  final _picker = ImagePicker();
  bool _saving = false;

  // ── Location tagging ──────────────────────────────────────────────────────
  bool   _tagLocation      = true;   // on by default — admin posts are local
  bool   _detectingLoc     = false;
  double _locationLat      = 0.0;
  double _locationLng      = 0.0;
  String _locationLabel    = '';
  double _radiusKm         = 500.0;  // default country-scale

  @override
  void initState() {
    super.initState();
    _autoDetectLocation(); // detect on open
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoDetectLocation() async {
    setState(() => _detectingLoc = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.low));
      if (mounted) {
        setState(() {
          _locationLat   = pos.latitude;
          _locationLng   = pos.longitude;
          _locationLabel =
              '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _tagLocation = false);
    } finally {
      if (mounted) setState(() => _detectingLoc = false);
    }
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (x != null && mounted) setState(() => _pickedImage = File(x.path));
  }

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 85);
    if (x != null && mounted) setState(() => _pickedImage = File(x.path));
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a title.')));
      return;
    }
    if (_tagLocation && _locationLat == 0.0 && _locationLng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Location not detected yet. Wait a moment or turn off location tagging.')));
      return;
    }
    setState(() => _saving = true);
    try {
      String imageUrl = '';
      if (_pickedImage != null) {
        imageUrl = await StorageService.uploadImage(
            _pickedImage!,
            'daily_posts/${DateTime.now().millisecondsSinceEpoch}.jpg');
      } else if (_imageUrlCtrl.text.trim().isNotEmpty) {
        imageUrl = _imageUrlCtrl.text.trim();
      }

      final post = DailyPost(
        type:         _type,
        date:         ContentService.todayDate(),
        title:        _titleCtrl.text.trim(),
        text:         '',
        imageUrl:     imageUrl,
        postedAt:     DateTime.now(),
        postedBy:     AuthService.instance.email ?? '',
        locationLat:  _tagLocation ? _locationLat : 0.0,
        locationLng:  _tagLocation ? _locationLng : 0.0,
        locationName: _tagLocation ? _locationLabel : '',
        radiusKm:     _tagLocation ? _radiusKm : 0.0,
      );
      await ContentService.createPost(post);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLoc = _locationLat != 0.0 || _locationLng != 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Post'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Post',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Category ─────────────────────────────────────────────────
            const Text('Category',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: PostType.values
                  .map((t) => ChoiceChip(
                        label: Text('${t.icon} ${t.label}'),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                        selectedColor: const Color(0xFF2E7D32),
                        labelStyle: TextStyle(
                            color: _type == t ? Colors.white : null),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),

            // ── Image ─────────────────────────────────────────────────────
            const Text('Image',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_pickedImage != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_pickedImage!,
                    height: 220, width: double.infinity, fit: BoxFit.cover),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _pickedImage = null),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Remove',
                    style: TextStyle(color: Colors.red)),
              ),
            ] else ...[
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.grey.shade300, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 44, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Tap to select image',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('Camera'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _imageUrlCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Or paste image URL (https://…)',
                prefixIcon: const Icon(Icons.link, size: 18),
                suffixIcon: _imageUrlCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () =>
                            setState(() => _imageUrlCtrl.clear()),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tip: if upload fails, enable Firebase Storage at\n'
              'console.firebase.google.com → Storage → Get started',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),

            // ── Title ─────────────────────────────────────────────────────
            const Text('Title',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Quote of the Day',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // ── Location tagging ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _tagLocation
                    ? const Color(0xFF1565C0).withValues(alpha: 0.06)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _tagLocation
                      ? const Color(0xFF1565C0).withValues(alpha: 0.35)
                      : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toggle row
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 18, color: Color(0xFF1565C0)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Show only to nearby users',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              'ON → local post  ·  OFF → everyone sees it',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _tagLocation,
                        onChanged: (v) {
                          setState(() => _tagLocation = v);
                          if (v && !hasLoc) _autoDetectLocation();
                        },
                        activeColor: const Color(0xFF1565C0),
                      ),
                    ],
                  ),

                  if (_tagLocation) ...[
                    const SizedBox(height: 12),

                    // Location status
                    if (_detectingLoc)
                      const Row(
                        children: [
                          SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Detecting your location…',
                              style: TextStyle(fontSize: 12)),
                        ],
                      )
                    else if (hasLoc)
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 14, color: Colors.green),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '📍 $_locationLabel',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.green),
                            ),
                          ),
                          TextButton(
                            onPressed: _autoDetectLocation,
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0)),
                            child: const Text('Refresh',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_outlined,
                              size: 14, color: Colors.orange),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text('Location not available',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.orange)),
                          ),
                          TextButton(
                            onPressed: _autoDetectLocation,
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0)),
                            child: const Text('Retry',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),

                    const SizedBox(height: 10),

                    // Radius selector
                    Row(
                      children: [
                        const Text('Radius:',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(width: 10),
                        DropdownButton<double>(
                          value: _radiusKm,
                          isDense: true,
                          items: const [
                            DropdownMenuItem(value: 10,   child: Text('10 km  (city)')),
                            DropdownMenuItem(value: 50,   child: Text('50 km  (region)')),
                            DropdownMenuItem(value: 200,  child: Text('200 km (wide region)')),
                            DropdownMenuItem(value: 500,  child: Text('500 km (country)')),
                            DropdownMenuItem(value: 1500, child: Text('1500 km (continent)')),
                          ],
                          onChanged: (v) =>
                              setState(() => _radiusKm = v ?? 500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Users within ${_radiusKm.toStringAsFixed(0)} km of your location will see this post.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> _confirm(
  BuildContext context,
  String title,
  String content, {
  required String confirmLabel,
  required Color confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: TextStyle(color: confirmColor)),
        ),
      ],
    ),
  );
}
