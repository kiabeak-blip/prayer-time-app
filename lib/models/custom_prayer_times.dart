class CustomPrayerTimes {
  final String date; // YYYY-MM-DD
  final String fajr;
  final String sunrise;
  final String dhuhr;
  final String asr;
  final String maghrib;
  final String isha;

  /// Admin's GPS location when they saved these times.
  /// If null, times apply to everyone (legacy / no location set).
  final double? adminLat;
  final double? adminLng;

  /// Radius in km — users beyond this distance use calculated times.
  /// Defaults to 50 km when location is set.
  final double radiusKm;

  const CustomPrayerTimes({
    required this.date,
    this.fajr = '',
    this.sunrise = '',
    this.dhuhr = '',
    this.asr = '',
    this.maghrib = '',
    this.isha = '',
    this.adminLat,
    this.adminLng,
    this.radiusKm = 50,
  });

  bool get isEmpty =>
      fajr.isEmpty &&
      sunrise.isEmpty &&
      dhuhr.isEmpty &&
      asr.isEmpty &&
      maghrib.isEmpty &&
      isha.isEmpty;

  String? timeFor(String key) {
    final t = switch (key) {
      'fajr' => fajr,
      'sunrise' => sunrise,
      'dhuhr' => dhuhr,
      'asr' => asr,
      'maghrib' => maghrib,
      'isha' => isha,
      _ => '',
    };
    return t.isEmpty ? null : t;
  }

  static String _str(Map f, String key) =>
      (f[key]?['stringValue'] as String?) ?? '';

  static double? _dbl(Map f, String key) {
    final v = f[key];
    if (v == null) return null;
    final d = v['doubleValue'] ?? v['integerValue'];
    if (d == null) return null;
    return double.tryParse(d.toString());
  }

  factory CustomPrayerTimes.fromFirestore(Map<String, dynamic> doc) {
    final f = (doc['fields'] as Map<String, dynamic>?) ?? {};
    return CustomPrayerTimes(
      date:     _str(f, 'date'),
      fajr:     _str(f, 'fajr'),
      sunrise:  _str(f, 'sunrise'),
      dhuhr:    _str(f, 'dhuhr'),
      asr:      _str(f, 'asr'),
      maghrib:  _str(f, 'maghrib'),
      isha:     _str(f, 'isha'),
      adminLat: _dbl(f, 'adminLat'),
      adminLng: _dbl(f, 'adminLng'),
      radiusKm: _dbl(f, 'radiusKm') ?? 50,
    );
  }

  Map<String, dynamic> toFirestoreFields() {
    final fields = <String, dynamic>{
      'date':    {'stringValue': date},
      'fajr':    {'stringValue': fajr},
      'sunrise': {'stringValue': sunrise},
      'dhuhr':   {'stringValue': dhuhr},
      'asr':     {'stringValue': asr},
      'maghrib': {'stringValue': maghrib},
      'isha':    {'stringValue': isha},
      'radiusKm': {'doubleValue': radiusKm},
    };
    if (adminLat != null) fields['adminLat'] = {'doubleValue': adminLat};
    if (adminLng != null) fields['adminLng'] = {'doubleValue': adminLng};
    return {'fields': fields};
  }

  CustomPrayerTimes copyWith({
    String? fajr,
    String? sunrise,
    String? dhuhr,
    String? asr,
    String? maghrib,
    String? isha,
    double? adminLat,
    double? adminLng,
    double? radiusKm,
  }) =>
      CustomPrayerTimes(
        date:     date,
        fajr:     fajr     ?? this.fajr,
        sunrise:  sunrise  ?? this.sunrise,
        dhuhr:    dhuhr    ?? this.dhuhr,
        asr:      asr      ?? this.asr,
        maghrib:  maghrib  ?? this.maghrib,
        isha:     isha     ?? this.isha,
        adminLat: adminLat ?? this.adminLat,
        adminLng: adminLng ?? this.adminLng,
        radiusKm: radiusKm ?? this.radiusKm,
      );
}
