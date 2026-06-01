class ChatMessage {
  final String id;
  final String text;
  final String senderName;
  final String senderRole; // 'superadmin' | 'admin' | 'member'
  final String senderEmail;
  final String deviceId;   // for members
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.senderName,
    required this.senderRole,
    required this.senderEmail,
    required this.deviceId,
    required this.timestamp,
  });

  bool get isAdmin      => senderRole == 'admin' || senderRole == 'superadmin';
  bool get isSuperAdmin => senderRole == 'superadmin';

  static ChatMessage fromFirestore(Map<String, dynamic> doc) {
    final fields = doc['fields'] as Map<String, dynamic>? ?? {};
    String f(String k) =>
        (fields[k] as Map?)?.values.first?.toString() ?? '';
    final name = doc['name'] as String? ?? '';
    final id   = name.split('/').last;
    return ChatMessage(
      id:          id,
      text:        f('text'),
      senderName:  f('senderName'),
      senderRole:  f('senderRole'),
      senderEmail: f('senderEmail'),
      deviceId:    f('deviceId'),
      timestamp:   DateTime.tryParse(f('timestamp')) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestoreFields() => {
    'fields': {
      'text':        {'stringValue': text},
      'senderName':  {'stringValue': senderName},
      'senderRole':  {'stringValue': senderRole},
      'senderEmail': {'stringValue': senderEmail},
      'deviceId':    {'stringValue': deviceId},
      'timestamp':   {'stringValue': timestamp.toUtc().toIso8601String()},
    },
  };
}
