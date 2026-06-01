/// Shared last-known GPS position — written by Daily & Qibla screens,
/// read by main.dart for WhatsApp routing.
class LocationCache {
  LocationCache._();
  static double? lat;
  static double? lng;
}
