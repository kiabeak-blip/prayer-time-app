import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AzanService {
  static final AzanService instance = AzanService._();
  AzanService._() {
    _player.onPlayerStateChanged.listen((s) {
      _isPlaying = s == PlayerState.playing;
    });
    // Configure for media / alarm playback on Android
    _player.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: true,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gain,
      ),
    ));
  }

  static const _azanEnabledKey = 'azan_enabled';

  // Bundled asset (most reliable — works offline)
  static const _azanAsset = 'assets/audio/azan.mp3';

  // Remote fallback URLs — tried in order if asset is missing
  static const _azanUrls = [
    'https://www.islamcan.com/audio/adhan/azan1.mp3',
    'https://ia600202.us.archive.org/11/items/AzanAudio/Azan.mp3',
  ];

  static const _azanPrayers = {'fajr', 'dhuhr', 'asr', 'maghrib', 'isha'};

  final AudioPlayer _player = AudioPlayer();
  Timer?  _timer;
  Map<String, DateTime> _prayerTimes   = {};
  final Set<String>     _playedToday   = {};
  DateTime?             _lastCheckedDate;

  bool _enabled   = false;
  bool _isPlaying = false;

  bool get isEnabled => _enabled;
  bool get isPlaying => _isPlaying;

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_azanEnabledKey) ?? false;
    // Pre-cache in background so first azan is instant
    if (_enabled) _preCacheAzan();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_azanEnabledKey, value);
    if (value) {
      _preCacheAzan();
      if (_prayerTimes.isNotEmpty) _startTimer();
    } else {
      _stopTimer();
      await _player.stop();
    }
  }

  void updatePrayerTimes(Map<String, DateTime> times) {
    _prayerTimes = {
      for (final e in times.entries)
        if (_azanPrayers.contains(e.key)) e.key: e.value,
    };
    if (_enabled) _startTimer();
  }

  Future<void> playNow() => _playAzan();
  Future<void> stop()    => _player.stop();

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    _check();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _check() {
    final now = DateTime.now();
    // Reset daily played set at midnight
    if (_lastCheckedDate == null || _lastCheckedDate!.day != now.day) {
      _playedToday.clear();
      _lastCheckedDate = now;
    }
    for (final entry in _prayerTimes.entries) {
      if (_playedToday.contains(entry.key)) continue;
      final diff = now.difference(entry.value).inSeconds;
      // Fire if within 0–89 seconds after prayer time
      if (diff >= 0 && diff < 90) {
        _playedToday.add(entry.key);
        _playAzan(); // intentionally not awaited — timer must not block
        break;
      }
    }
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  Future<void> _playAzan() async {
    await _player.stop();

    // 1. Bundled asset — fastest, works offline, most reliable
    try {
      await _player.play(AssetSource(_azanAsset.replaceFirst('assets/', '')));
      debugPrint('[Azan] Playing from bundled asset');
      return;
    } catch (e) {
      debugPrint('[Azan] Asset source failed: $e');
    }

    // 2. Try cached local file (previously downloaded)
    final cached = await _cachedFile();
    if (cached != null) {
      try {
        await _player.play(DeviceFileSource(cached));
        debugPrint('[Azan] Playing from device cache');
        return;
      } catch (e) {
        debugPrint('[Azan] DeviceFileSource failed: $e');
        try { await File(cached).delete(); } catch (_) {}
      }
    }

    // 3. Stream from URL as last resort
    for (final url in _azanUrls) {
      try {
        await _player.play(UrlSource(url));
        debugPrint('[Azan] Playing from URL: $url');
        _downloadAndCache(url);
        return;
      } catch (e) {
        debugPrint('[Azan] UrlSource $url failed: $e');
      }
    }

    debugPrint('[Azan] All sources failed — azan could not play.');
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  Future<String?> _cachedFile() async {
    try {
      final tmp  = await getTemporaryDirectory();
      final file = File('${tmp.path}${Platform.pathSeparator}azan_cache'
          '${Platform.pathSeparator}azan.mp3');
      if (await file.exists() && (await file.length()) > 10000) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _preCacheAzan() async {
    if (await _cachedFile() != null) return; // already cached
    await _downloadAndCache(_azanUrls.first);
  }

  Future<void> _downloadAndCache(String url) async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory(
          '${tmp.path}${Platform.pathSeparator}azan_cache');
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}azan.mp3');
      if (await file.exists()) return;
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 && res.bodyBytes.length > 10000) {
        await file.writeAsBytes(res.bodyBytes);
        debugPrint('[Azan] Cached from $url');
      }
    } catch (e) {
      debugPrint('[Azan] Cache download failed: $e');
    }
  }

  void dispose() {
    _timer?.cancel();
    _player.dispose();
  }
}
