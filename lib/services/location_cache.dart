import 'package:geolocator/geolocator.dart';

/// Shared last-known GPS position — written by Daily & Qibla screens,
/// read by main.dart for WhatsApp routing and by both screens so whichever
/// one fetches a fix first lets the other show it instantly on open.
class LocationCache {
  LocationCache._();
  static double? lat;
  static double? lng;

  /// A [Position] built from the cached coordinates, for screens that need
  /// a full Position but only ever read its latitude/longitude. Returns
  /// null if no fix has been cached yet this session.
  static Position? toPosition() {
    if (lat == null || lng == null) return null;
    return Position(
      latitude: lat!,
      longitude: lng!,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}
