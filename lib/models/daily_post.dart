enum PostType { verse, hadith, reminder, dua }

extension PostTypeLabel on PostType {
  String get label => switch (this) {
        PostType.verse => 'Quran Verse',
        PostType.hadith => 'Hadith',
        PostType.reminder => 'Reminder',
        PostType.dua => 'Dua',
      };

  String get icon => switch (this) {
        PostType.verse => '📖',
        PostType.hadith => '🌙',
        PostType.reminder => '💬',
        PostType.dua => '🤲',
      };
}

class DailyPost {
  final String? id;
  final PostType type;
  final String date; // YYYY-MM-DD
  final String time; // HH:mm or empty
  final String title;
  final String arabic;
  final String text;
  final String source;
  final String translation;
  final String imageUrl; // Firebase Storage download URL or empty
  final DateTime postedAt;
  final String postedBy;

  // Location targeting — radiusKm == 0 means global (shown to everyone)
  final double locationLat;
  final double locationLng;
  final String locationName;
  final double radiusKm;

  bool get hasLocation => radiusKm > 0;

  const DailyPost({
    this.id,
    required this.type,
    required this.date,
    this.time = '',
    required this.title,
    this.arabic = '',
    required this.text,
    this.source = '',
    this.translation = '',
    this.imageUrl = '',
    required this.postedAt,
    required this.postedBy,
    this.locationLat = 0.0,
    this.locationLng = 0.0,
    this.locationName = '',
    this.radiusKm = 0.0,
  });

  // ── Firestore REST helpers ─────────────────────────────────────────────────

  static String _str(Map f, String key) =>
      (f[key]?['stringValue'] as String?) ?? '';

  static DateTime _ts(Map f, String key) {
    final v = f[key]?['timestampValue'] as String?;
    return v != null ? DateTime.parse(v) : DateTime.now();
  }

  static double _dbl(Map f, String key) =>
      (f[key]?['doubleValue'] as num?)?.toDouble() ?? 0.0;

  factory DailyPost.fromFirestore(Map<String, dynamic> doc) {
    final name = doc['name'] as String;
    final id = name.split('/').last;
    final f = (doc['fields'] as Map<String, dynamic>?) ?? {};
    return DailyPost(
      id: id,
      type: PostType.values.firstWhere(
        (e) => e.name == _str(f, 'type'),
        orElse: () => PostType.reminder,
      ),
      date: _str(f, 'date'),
      time: _str(f, 'time'),
      title: _str(f, 'title'),
      arabic: _str(f, 'arabic'),
      text: _str(f, 'text'),
      source: _str(f, 'source'),
      translation: _str(f, 'translation'),
      imageUrl: _str(f, 'imageUrl'),
      postedAt: _ts(f, 'postedAt'),
      postedBy: _str(f, 'postedBy'),
      locationLat: _dbl(f, 'locationLat'),
      locationLng: _dbl(f, 'locationLng'),
      locationName: _str(f, 'locationName'),
      radiusKm: _dbl(f, 'radiusKm'),
    );
  }

  Map<String, dynamic> toFirestoreFields() => {
        'fields': {
          'type': {'stringValue': type.name},
          'date': {'stringValue': date},
          'time': {'stringValue': time},
          'title': {'stringValue': title},
          'arabic': {'stringValue': arabic},
          'text': {'stringValue': text},
          'source': {'stringValue': source},
          'translation': {'stringValue': translation},
          'imageUrl': {'stringValue': imageUrl},
          'postedAt': {
            'timestampValue': postedAt.toUtc().toIso8601String()
          },
          'postedBy': {'stringValue': postedBy},
          'locationLat': {'doubleValue': locationLat},
          'locationLng': {'doubleValue': locationLng},
          'locationName': {'stringValue': locationName},
          'radiusKm': {'doubleValue': radiusKm},
        }
      };

  DailyPost copyWith({
    String? id,
    PostType? type,
    String? date,
    String? time,
    String? title,
    String? arabic,
    String? text,
    String? source,
    String? translation,
    String? imageUrl,
    double? locationLat,
    double? locationLng,
    String? locationName,
    double? radiusKm,
  }) =>
      DailyPost(
        id: id ?? this.id,
        type: type ?? this.type,
        date: date ?? this.date,
        time: time ?? this.time,
        title: title ?? this.title,
        arabic: arabic ?? this.arabic,
        text: text ?? this.text,
        source: source ?? this.source,
        translation: translation ?? this.translation,
        imageUrl: imageUrl ?? this.imageUrl,
        postedAt: postedAt,
        postedBy: postedBy,
        locationLat: locationLat ?? this.locationLat,
        locationLng: locationLng ?? this.locationLng,
        locationName: locationName ?? this.locationName,
        radiusKm: radiusKm ?? this.radiusKm,
      );
}
