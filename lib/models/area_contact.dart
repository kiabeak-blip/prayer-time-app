class AreaContact {
  final String id;
  final String areaName;
  final String address;
  final String whatsapp;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final String adminEmail;

  const AreaContact({
    required this.id,
    required this.areaName,
    this.address = '',
    required this.whatsapp,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.adminEmail,
  });

  factory AreaContact.fromFirestore(Map<String, dynamic> doc) {
    final fields = doc['fields'] as Map<String, dynamic>? ?? {};

    String _s(String key) =>
        (fields[key] as Map?)?.values.first?.toString() ?? '';
    double _d(String key) =>
        double.tryParse((fields[key] as Map?)?.values.first?.toString() ?? '') ?? 0;

    return AreaContact(
      id:          (doc['name'] as String? ?? '').split('/').last,
      areaName:    _s('areaName'),
      address:     _s('address'),
      whatsapp:    _s('whatsapp'),
      latitude:    _d('latitude'),
      longitude:   _d('longitude'),
      radiusKm:    _d('radiusKm'),
      adminEmail:  _s('adminEmail'),
    );
  }

  Map<String, dynamic> toFirestoreFields() => {
        'fields': {
          'areaName':   {'stringValue': areaName},
          'address':    {'stringValue': address},
          'whatsapp':   {'stringValue': whatsapp},
          'latitude':   {'doubleValue': latitude},
          'longitude':  {'doubleValue': longitude},
          'radiusKm':   {'doubleValue': radiusKm},
          'adminEmail': {'stringValue': adminEmail},
        },
      };
}
