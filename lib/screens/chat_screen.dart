import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _nameKey     = 'chat_member_name';
  static const _deviceIdKey = 'chat_device_id';

  final _textCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ChatMessage> _messages = [];
  bool   _loading  = true;
  bool   _sending  = false;
  String _error    = '';
  Timer? _pollTimer;

  String? _myDeviceId;
  String? _myName;

  // Admin identity (if signed in)
  bool   get _isAdmin      => AuthService.instance.isAdmin;
  bool   get _isSuperAdmin => AuthService.instance.isSuperAdmin;
  String get _adminRole    => _isSuperAdmin ? 'superadmin' : 'admin';

  // The "me" identifier string used to detect own messages
  String get _myId =>
      _isAdmin ? (AuthService.instance.email ?? '') : (_myDeviceId ?? '');

  bool _isMine(ChatMessage m) =>
      _isAdmin ? m.senderEmail == _myId : m.deviceId == _myId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadIdentity();
    if (!_isAdmin && (_myName == null || _myName!.isEmpty)) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _promptName(required: true));
      return;
    }
    await _loadMessages();
    _startPolling();
  }

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    _myName     = prefs.getString(_nameKey);
    _myDeviceId = prefs.getString(_deviceIdKey);
    if (_myDeviceId == null) {
      // Generate a simple device ID from timestamp
      _myDeviceId =
          'device_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_deviceIdKey, _myDeviceId!);
    }
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await ChatService.getMessages();
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading  = false;
        _error    = '';
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      try {
        final msgs = await ChatService.getMessages();
        if (!mounted) return;
        final hadNew = msgs.length != _messages.length;
        setState(() => _messages = msgs);
        if (hadNew) _scrollToBottom();
      } catch (_) {}
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    // Member must have a name
    if (!_isAdmin && (_myName == null || _myName!.isEmpty)) {
      _promptName(required: true);
      return;
    }

    setState(() => _sending = true);
    _textCtrl.clear();

    try {
      final msg = ChatMessage(
        id:          '',
        text:        text,
        senderName:  _isAdmin
            ? (AuthService.instance.email ?? 'Admin')
            : _myName!,
        senderRole:  _isAdmin ? _adminRole : 'member',
        senderEmail: _isAdmin ? (AuthService.instance.email ?? '') : '',
        deviceId:    _isAdmin ? '' : (_myDeviceId ?? ''),
        timestamp:   DateTime.now().toUtc(),
      );
      await ChatService.sendMessage(msg);
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _promptName({bool required = false}) async {
    final ctrl = TextEditingController(text: _myName ?? '');
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: !required,
      builder: (ctx) => AlertDialog(
        title: const Text('Your display name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          if (!required)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          FilledButton(
            onPressed: () {
              final n = ctrl.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, n);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, result);
      setState(() => _myName = result);
      if (_pollTimer == null) {
        await _loadMessages();
        _startPolling();
      }
    }
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text('"${msg.text}"'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ChatService.deleteMessage(msg.id);
        await _loadMessages();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Chat'),
        actions: [
          if (!_isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Change name',
              onPressed: () => _promptName(),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Status bar ───────────────────────────────────────────────
          if (_myName != null && !_isAdmin)
            Container(
              width: double.infinity,
              color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 14, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 6),
                  Text(
                    'Chatting as $_myName',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          // ── Messages ─────────────────────────────────────────────────
          Expanded(child: _buildMessages()),

          // ── Input ────────────────────────────────────────────────────
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Could not load messages',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadMessages, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💬', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('No messages yet.',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Be the first to say something!',
                style: TextStyle(
                    color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        message: _messages[i],
        isMine: _isMine(_messages[i]),
        canDelete: _isSuperAdmin ||
            AuthService.instance.isAdmin ||
            _isMine(_messages[i]),
        onDelete: () => _deleteMessage(_messages[i]),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, -2),
          )
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textCtrl,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? const SizedBox(
                    width: 44,
                    height: 44,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: _send,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.send_rounded),
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool canDelete;
  final VoidCallback onDelete;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const green     = Color(0xFF2E7D32);
    const darkGreen = Color(0xFF1B5E20);
    const gold      = Color(0xFFB8860B);

    final bubbleColor = isMine
        ? green
        : (message.isAdmin ? const Color(0xFFFFF8E1) : Colors.grey.shade100);
    final textColor =
        isMine ? Colors.white : Colors.black87;
    final nameColor = message.isSuperAdmin
        ? gold
        : (message.isAdmin ? darkGreen : Colors.grey.shade600);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar (others only)
          if (!isMine) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: message.isSuperAdmin
                  ? gold
                  : (message.isAdmin ? green : Colors.grey.shade300),
              child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: message.isAdmin
                        ? Colors.white
                        : Colors.grey.shade700),
              ),
            ),
            const SizedBox(width: 6),
          ],

          // Bubble
          Flexible(
            child: GestureDetector(
              onLongPress: canDelete ? onDelete : null,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMine ? 16 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 16),
                  ),
                  border: message.isAdmin && !isMine
                      ? Border.all(
                          color: message.isSuperAdmin
                              ? gold.withValues(alpha: 0.4)
                              : green.withValues(alpha: 0.3),
                          width: 1,
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Name + role badge
                    if (!isMine) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message.senderName,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: nameColor),
                          ),
                          if (message.isAdmin) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: message.isSuperAdmin
                                    ? gold
                                    : green,
                                borderRadius:
                                    BorderRadius.circular(4),
                              ),
                              child: Text(
                                message.isSuperAdmin
                                    ? 'SUPER ADMIN'
                                    : 'ADMIN',
                                style: const TextStyle(
                                    fontSize: 8,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                    ],

                    // Message text
                    Text(
                      message.text,
                      style:
                          TextStyle(fontSize: 14, color: textColor),
                    ),

                    // Time
                    const SizedBox(height: 3),
                    Text(
                      _formatTime(message.timestamp.toLocal()),
                      style: TextStyle(
                          fontSize: 10,
                          color: isMine
                              ? Colors.white70
                              : Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $p';
  }
}
