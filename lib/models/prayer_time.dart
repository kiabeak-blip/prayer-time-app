class PrayerTime {
  final String date;
  final Map<String, Map<String, String>> prayers;

  PrayerTime({required this.date, required this.prayers});

  factory PrayerTime.fromJson(Map<String, dynamic> json) {
    return PrayerTime(
      date: json['date'],
      prayers: Map<String, Map<String, String>>.from(
        json['prayers'].map((lang, times) =>
          MapEntry(lang, Map<String, String>.from(times))
        ),
      ),
    );
  }
}
