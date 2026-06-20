import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

const _sttChannel = MethodChannel('speech_to_text_windows');

// ── Common dhikr presets ──────────────────────────────────────────────────────

class _Dhikr {
  final String arabic;
  final String label;
  final String transliteration;
  const _Dhikr(this.arabic, this.label, this.transliteration);
}

// ── Saved custom dhikr ────────────────────────────────────────────────────────

class _SavedDhikr {
  final String text;
  final String label;
  _SavedDhikr({required this.text, required this.label});

  factory _SavedDhikr.fromJson(Map<String, dynamic> j) =>
      _SavedDhikr(text: j['text'] as String, label: j['label'] as String);

  Map<String, dynamic> toJson() => {'text': text, 'label': label};
}

const _presets = [
  _Dhikr('سبحان الله',          'Subhanallah',      'subhanallah'),
  _Dhikr('الحمد لله',           'Alhamdulillah',    'alhamdulillah'),
  _Dhikr('الله أكبر',           'Allahu Akbar',     'allahu akbar'),
  _Dhikr('لا إله إلا الله',     'La ilaha illallah','la ilaha illallah'),
  _Dhikr('أستغفر الله',         'Astaghfirullah',   'astaghfirullah'),
  _Dhikr('لا حول ولا قوة إلا بالله', 'La hawla',   'la hawla wala quwwata'),
  _Dhikr('اللهم صل على النبي',  'Salawat',          'allahumma salli alan nabi'),
];

// ── Arabic text helpers ───────────────────────────────────────────────────────

/// Returns true when [text] contains any Arabic-script character.
bool _isArabic(String text) =>
    text.runes.any((r) => r >= 0x0600 && r <= 0x06FF);

/// Normalise Arabic text for robust matching:
/// strips diacritics, normalises alef variants, removes tatweel.
String _normalise(String text) {
  // Remove Arabic diacritics (harakat) U+064B–U+065F and U+0670
  text = text.replaceAll(RegExp(r'[ً-ٰٟ]'), '');
  // Normalise alef variants → bare alef
  text = text.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
  // Remove tatweel ـ
  text = text.replaceAll('ـ', '');
  // Collapse whitespace
  return text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}

/// Counts non-overlapping occurrences of [phrase] inside [heard], so a
/// continuous speech session can be scored for every repetition spoken,
/// not just whether the phrase appeared at all.
int _countOccurrences(String heard, String phrase) {
  final h = _normalise(heard);
  final p = _normalise(phrase);
  if (p.isEmpty) return 0;

  final direct = _countSubstring(h, p);
  if (direct > 0) return direct;

  // Spacing differences (سبحانالله vs سبحان الله)
  final hNoSpace = h.replaceAll(' ', '');
  final pNoSpace = p.replaceAll(' ', '');
  if (pNoSpace.isNotEmpty) return _countSubstring(hNoSpace, pNoSpace);
  return 0;
}

int _countSubstring(String text, String pattern) {
  if (pattern.isEmpty) return 0;
  var count = 0;
  var start = 0;
  while (true) {
    final idx = text.indexOf(pattern, start);
    if (idx == -1) break;
    count++;
    start = idx + pattern.length;
  }
  return count;
}

// ─────────────────────────────────────────────────────────────────────────────

class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});

  @override
  CounterScreenState createState() => CounterScreenState();
}

class CounterScreenState extends State<CounterScreen> {
  int    _count              = 0;
  String _phrase             = 'سبحان الله';
  bool   _isListening        = false;
  bool   _speechAvailable    = false;
  bool   _speechInitialized  = false; // true once _initSpeech() has run
  bool   _speechInitializing = false; // true while permission dialog is open
  String _lastHeard          = '';
  bool   _phraseDetectedFlash = false;
  String? _localeId;            // resolved Arabic or device locale
  bool   _arabicLocaleConfirmed = false; // true = device listed it; false = best-effort
  bool   _arabicLocaleFailed    = false; // true = ar-SA was tried and failed
  int    _occurrencesInSession  = 0; // phrase repetitions already counted in the current listen session
  int?   _targetCount;          // beep/notify once _count reaches this
  bool   _isDictating           = false; // dictating the custom-phrase text field

  List<_SavedDhikr> _savedDhikr = [];

  final _phraseController = TextEditingController();
  final _speech = stt.SpeechToText();
  final bool _isWindows = Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _load();
    // Speech engine is initialised lazily — only when the mic button is tapped.
    // This avoids asking for microphone permission at app startup.
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('saved_dhikr_list');
    List<_SavedDhikr> saved = [];
    if (savedJson != null) {
      try {
        final list = jsonDecode(savedJson) as List;
        saved = list.map((e) => _SavedDhikr.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _count  = prefs.getInt('dhikr_count')   ?? 0;
        _phrase = prefs.getString('dhikr_phrase') ?? 'سبحان الله';
        _targetCount = prefs.getInt('dhikr_target');
        _phraseController.text = _phrase;
        _savedDhikr = saved;
      });
    }
  }

  Future<void> _persistSavedDhikr() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'saved_dhikr_list',
        jsonEncode(_savedDhikr.map((d) => d.toJson()).toList()));
  }

  Future<void> _promptSaveDhikr() async {
    final text = _phraseController.text.trim();
    if (text.isEmpty) return;

    // Check if already saved
    if (_savedDhikr.any((d) => d.text == text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already saved')),
      );
      return;
    }

    final labelCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Dhikr'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: const TextStyle(fontSize: 18),
                textDirection: _isArabic(text)
                    ? TextDirection.rtl
                    : TextDirection.ltr),
            const SizedBox(height: 12),
            TextField(
              controller: labelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. Morning Dhikr)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (confirmed != true) return;
    final label = labelCtrl.text.trim().isEmpty ? text : labelCtrl.text.trim();
    setState(() => _savedDhikr.add(_SavedDhikr(text: text, label: label)));
    await _persistSavedDhikr();
  }

  Future<void> _deleteSavedDhikr(_SavedDhikr d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Dhikr?'),
        content: Text('"${d.label}" will be removed from your list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _savedDhikr.removeWhere((x) => x.text == d.text));
    await _persistSavedDhikr();
  }

  Future<void> _saveCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dhikr_count', _count);
  }

  Future<void> _savePhrase(String phrase) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dhikr_phrase', phrase);
  }

  Future<void> _setTargetCount(int? value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _targetCount = value);
    if (value == null) {
      await prefs.remove('dhikr_target');
    } else {
      await prefs.setInt('dhikr_target', value);
    }
  }

  Future<void> _promptSetTarget() async {
    final ctrl = TextEditingController(
        text: _targetCount?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Target Count'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Beep when count reaches…',
            hintText: 'e.g. 33, 100',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (_targetCount != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _setTargetCount(result == -1 ? null : result);
  }

  void _checkTargetReached() {
    if (_targetCount != null && _count == _targetCount) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🎯 Target of $_targetCount reached!')),
        );
      }
    }
  }

  // ── Speech engine ─────────────────────────────────────────────────────────

  Future<void> _initSpeech() async {
    if (_isWindows) {
      _sttChannel.setMethodCallHandler(_onWindowsCallback);
      final ok =
          await _sttChannel.invokeMethod<bool>(
              'initialize', {'debugLogging': false}) ??
              false;
      if (mounted) setState(() => _speechAvailable = ok);
    } else {
      final ok = await _speech.initialize(
        onError: (e) {
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (status) {
          if (!mounted) return;
          if (status == stt.SpeechToText.doneStatus && _isListening) {
            Future.delayed(const Duration(milliseconds: 200),
                _beginListenSession);
          }
        },
      );
      if (mounted) setState(() => _speechAvailable = ok);

      // Resolve Arabic locale once
      if (ok) _resolveArabicLocale();
    }
    if (mounted) setState(() => _speechInitialized = true);
  }

  /// Finds the best Arabic locale the device supports.
  /// If none is listed, falls back to trying 'ar-SA' directly — Android
  /// sometimes supports locales it doesn't enumerate.
  Future<void> _resolveArabicLocale() async {
    try {
      final locales = await _speech.locales();
      final arabicLocales =
          locales.where((l) => l.localeId.startsWith('ar')).toList();

      if (arabicLocales.isNotEmpty) {
        // Device has Arabic listed — use it
        if (mounted) {
          setState(() {
            _localeId = arabicLocales.first.localeId;
            _arabicLocaleConfirmed = true;
            _arabicLocaleFailed    = false;
          });
        }
      } else {
        // Not listed — try ar-SA anyway (unlisted but often works on Samsung)
        if (mounted) {
          setState(() {
            _localeId = 'ar-SA';
            _arabicLocaleConfirmed = false;
            _arabicLocaleFailed    = false;
          });
        }
      }
    } catch (_) {
      // On error, still attempt ar-SA
      if (mounted) {
        setState(() {
          _localeId = 'ar-SA';
          _arabicLocaleConfirmed = false;
        });
      }
    }
  }

  Future<dynamic> _onWindowsCallback(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'textRecognition':
        if (_isDictating) {
          _handleWindowsDictation(call.arguments as String);
        } else {
          _handleWindowsRecognition(call.arguments as String);
        }
      case 'notifyStatus':
        final status = call.arguments as String;
        if (status == 'done' && _isListening) {
          Future.delayed(
              const Duration(milliseconds: 150), _beginListenSession);
        }
        if (status == 'notListening' && !_isListening) setState(() {});
      case 'notifyError':
        setState(() {
          _isListening = false;
          _isDictating = false;
        });
    }
  }

  void _handleWindowsRecognition(String resultJson) {
    if (!mounted) return;
    try {
      final map  = jsonDecode(resultJson) as Map<String, dynamic>;
      final words = map['recognizedWords'] as String? ??
          (() {
            final alts = map['alternates'] as List<dynamic>?;
            return (alts?.first as Map<String, dynamic>?)?['recognizedWords']
                    as String? ??
                '';
          })();
      final isFinal = map['finalResult'] as bool? ?? true;
      setState(() => _lastHeard = words);

      // Count every repetition as it appears in the growing transcript, so
      // the counter ticks up live without waiting for the session to end.
      final occurrences = _countOccurrences(words, _phrase);
      if (occurrences > _occurrencesInSession) {
        final newOnes = occurrences - _occurrencesInSession;
        _occurrencesInSession = occurrences;
        for (var i = 0; i < newOnes; i++) {
          _incrementWithFlash();
        }
      }

      if (isFinal) {
        _occurrencesInSession = 0;
        if (_isListening && mounted) {
          Future.delayed(
              const Duration(milliseconds: 150), _beginListenSession);
        }
      }
    } catch (_) {}
  }

  void _handleWindowsDictation(String resultJson) {
    if (!mounted) return;
    try {
      final map = jsonDecode(resultJson) as Map<String, dynamic>;
      final words = map['recognizedWords'] as String? ??
          (() {
            final alts = map['alternates'] as List<dynamic>?;
            return (alts?.first as Map<String, dynamic>?)?['recognizedWords']
                    as String? ??
                '';
          })();
      final isFinal = map['finalResult'] as bool? ?? true;
      if (words.isNotEmpty) _phraseController.text = words;
      if (isFinal) {
        setState(() => _isDictating = false);
        _sttChannel.invokeMethod('stop');
        if (words.trim().isNotEmpty) _setPhrase(words.trim());
      }
    } catch (_) {}
  }

  /// Dictate the custom-phrase text field by voice, separate from the
  /// counting mic so the two don't fight over the speech engine.
  Future<void> _toggleDictation() async {
    if (_isDictating) {
      if (_isWindows) {
        _sttChannel.invokeMethod('stop');
      } else {
        _speech.stop();
      }
      setState(() => _isDictating = false);
      return;
    }

    if (_isListening) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop the counter mic first')),
      );
      return;
    }

    if (!_speechInitialized) {
      setState(() => _speechInitializing = true);
      await _initSpeech();
      setState(() => _speechInitializing = false);
      if (!_speechAvailable) return;
    }

    setState(() => _isDictating = true);

    if (_isWindows) {
      await _sttChannel.invokeMethod('listen', {
        'partialResults':  true,
        'onDevice':        false,
        'listenMode':      0,
        'sampleRate':      0,
        'enableHaptics':   false,
        'autoPunctuation': false,
      });
    } else {
      try {
        await _speech.listen(
          onResult: (result) {
            if (!mounted) return;
            if (result.recognizedWords.isNotEmpty) {
              _phraseController.text = result.recognizedWords;
            }
            if (result.finalResult) {
              setState(() => _isDictating = false);
              final words = result.recognizedWords.trim();
              if (words.isNotEmpty) _setPhrase(words);
            }
          },
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        );
      } catch (_) {
        if (mounted) setState(() => _isDictating = false);
      }
    }
  }

  Future<void> _beginListenSession() async {
    if (!_speechAvailable || !_isListening || !mounted) return;

    if (_isWindows) {
      // Windows STT: pass langTag when phrase is Arabic
      final args = <String, dynamic>{
        'partialResults':   true,
        'onDevice':         false,
        'listenMode':       0,
        'sampleRate':       0,
        'enableHaptics':    false,
        'autoPunctuation':  false,
      };
      if (_isArabic(_phrase)) args['langTag'] = 'ar-SA';
      await _sttChannel.invokeMethod('listen', args);
    } else {
      // Android/iOS: use resolved Arabic locale when phrase is Arabic
      final useLocale = (_isArabic(_phrase) && !_arabicLocaleFailed)
          ? _localeId
          : null;

      try {
        await _speech.listen(
          onResult: (result) {
            if (!mounted) return;
            final words = result.recognizedWords;
            setState(() => _lastHeard = words);

            // Count every repetition as it appears in the growing
            // transcript, so the counter ticks up live without waiting
            // for the session to end (which only happens on a pause or
            // manual stop).
            final occurrences = _countOccurrences(words, _phrase);
            if (occurrences > _occurrencesInSession) {
              final newOnes = occurrences - _occurrencesInSession;
              _occurrencesInSession = occurrences;
              for (var i = 0; i < newOnes; i++) {
                _incrementWithFlash();
              }
            }

            if (result.finalResult) {
              _occurrencesInSession = 0;
              if (_isListening) {
                Future.delayed(
                    const Duration(milliseconds: 200), _beginListenSession);
              }
            }
          },
          localeId:       useLocale,
          partialResults: true,
          cancelOnError:  false,
          listenMode:     stt.ListenMode.dictation,
        );
      } catch (e) {
        // Arabic locale failed — mark it and retry with device default
        if (useLocale != null && mounted) {
          setState(() => _arabicLocaleFailed = true);
          Future.delayed(
              const Duration(milliseconds: 100), _beginListenSession);
        }
      }
    }
  }

  Future<void> _toggleListening() async {
    if (_isDictating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish dictating the phrase first')),
      );
      return;
    }
    if (_isListening) {
      // ── Stop ──────────────────────────────────────────────────────────
      if (_isWindows) {
        _sttChannel.invokeMethod('stop');
      } else {
        _speech.stop();
      }
      setState(() {
        _isListening = false;
        _lastHeard   = '';
      });
      return;
    }

    // ── Start — initialise on first use ───────────────────────────────
    if (!_speechInitialized) {
      setState(() => _speechInitializing = true);
      await _initSpeech();
      setState(() => _speechInitializing = false);

      if (!_speechAvailable) return; // permission denied — don't start
    }

    setState(() {
      _isListening = true;
      _lastHeard   = '';
    });
    _occurrencesInSession = 0;
    _beginListenSession();
  }

  // ── Counter ───────────────────────────────────────────────────────────────

  void _incrementWithFlash() {
    setState(() {
      _count++;
      _phraseDetectedFlash = true;
    });
    _saveCount();
    _checkTargetReached();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _phraseDetectedFlash = false);
    });
  }

  void _increment() {
    setState(() => _count++);
    _saveCount();
    _checkTargetReached();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Counter'),
        content: const Text('Reset count to zero?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _count = 0);
    _saveCount();
  }

  void _showArabicInstallDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.language, color: Colors.orange),
            SizedBox(width: 8),
            Text('Install Arabic Speech'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your device does not have Arabic speech recognition installed. '
                'To enable it:',
              ),
              SizedBox(height: 12),
              Text('1.  Open device Settings',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              Text('2.  Go to General Management → Language'),
              Text('3.  Tap "Text-to-speech" or "Voice input"'),
              Text('4.  Select "Samsung Voice Input" or "Google"'),
              Text('5.  Tap "Add language" → choose Arabic'),
              Text('6.  Download the language pack'),
              Text('7.  Restart this app'),
              SizedBox(height: 12),
              Text(
                'Or: Settings → Apps → Google app → Language → Add Arabic',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _setPhrase(String phrase) {
    setState(() {
      _phrase = phrase;
      _arabicLocaleFailed = false; // allow retry on phrase change
    });
    _phraseController.text = phrase;
    _savePhrase(phrase);
    // Re-resolve locale if the phrase language changed
    if (!_isWindows && _speechAvailable) _resolveArabicLocale();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    if (_isWindows) {
      _sttChannel.invokeMethod('stop');
    } else {
      _speech.stop();
    }
    _phraseController.dispose();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final arabicPhrase = _isArabic(_phrase);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Dhikr presets ───────────────────────────────────────────────
          const Text('Common Dhikr',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((d) {
              final isSelected = _phrase == d.arabic;
              return GestureDetector(
                onTap: () => _setPhrase(d.arabic),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primary.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? primary
                          : Colors.grey.withValues(alpha: 0.3),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d.arabic,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? primary : null,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        d.label,
                        style: TextStyle(
                          fontSize: 9,
                          color: isSelected
                              ? primary.withValues(alpha: 0.8)
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // ── My Dhikr ─────────────────────────────────────────────────────
          if (_savedDhikr.isNotEmpty) ...[
            const Text('My Dhikr',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _savedDhikr.map((d) {
                final isSelected = _phrase == d.text;
                return GestureDetector(
                  onTap: () => _setPhrase(d.text),
                  onLongPress: () => _deleteSavedDhikr(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primary.withValues(alpha: 0.15)
                          : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? primary
                            : Colors.amber.shade300,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              d.text,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected ? primary : null,
                              ),
                              textDirection: _isArabic(d.text)
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                            ),
                            Text(
                              d.label,
                              style: TextStyle(
                                fontSize: 9,
                                color: isSelected
                                    ? primary.withValues(alpha: 0.8)
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text('Long-press a chip to remove it',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
          ],

          // ── Custom phrase input ──────────────────────────────────────────
          Directionality(
            textDirection: arabicPhrase
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: TextField(
              controller: _phraseController,
              textDirection: TextDirection.rtl, // always allow Arabic input
              decoration: InputDecoration(
                labelText: 'Custom phrase',
                hintText: 'اكتب العبارة هنا…',
                hintTextDirection: TextDirection.rtl,
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _isDictating ? Icons.mic : Icons.mic_none,
                        color: _isDictating ? Colors.red : null,
                      ),
                      tooltip: _isDictating
                          ? 'Stop dictating'
                          : 'Dictate phrase by voice',
                      onPressed: _toggleDictation,
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      tooltip: 'Save to My Dhikr',
                      onPressed: _promptSaveDhikr,
                    ),
                    IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: 'Use phrase',
                      onPressed: () {
                        final p = _phraseController.text.trim();
                        if (p.isNotEmpty) _setPhrase(p);
                      },
                    ),
                  ],
                ),
              ),
              onSubmitted: (v) {
                final p = v.trim();
                if (p.isNotEmpty) _setPhrase(p);
              },
            ),
          ),

          const SizedBox(height: 24),

          // ── Counter display ──────────────────────────────────────────────
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: _phraseDetectedFlash
                    ? primary.withValues(alpha: 0.15)
                    : theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Text(
                    '$_count',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _phraseDetectedFlash ? primary : null,
                      fontSize: 80,
                    ),
                  ),
                  Directionality(
                    textDirection: arabicPhrase
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Text(
                      '"$_phrase"',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (arabicPhrase) ...[
                    const SizedBox(height: 6),
                    if (_arabicLocaleConfirmed) ...[
                      // Device has Arabic installed and confirmed
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.language,
                              size: 11, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Arabic recognition ($_localeId)',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.green),
                          ),
                        ],
                      ),
                    ] else if (!_arabicLocaleFailed) ...[
                      // Trying ar-SA unlisted
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.language,
                              size: 11, color: Colors.orange),
                          SizedBox(width: 4),
                          Text(
                            'Trying Arabic (ar-SA)…',
                            style: TextStyle(
                                fontSize: 10, color: Colors.orange),
                          ),
                        ],
                      ),
                    ] else ...[
                      // ar-SA failed — using device default, show instructions
                      GestureDetector(
                        onTap: () => _showArabicInstallDialog(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Column(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber,
                                      size: 13, color: Colors.red),
                                  SizedBox(width: 4),
                                  Text(
                                    'Arabic not installed — using device language',
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.red),
                                  ),
                                ],
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Tap here for setup instructions',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    decoration: TextDecoration.underline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _promptSetTarget,
              icon: const Icon(Icons.notifications_active_outlined, size: 16),
              label: Text(
                _targetCount == null
                    ? 'Set target count'
                    : 'Target: $_targetCount',
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Mic button ───────────────────────────────────────────────────
          Center(
            child: _speechInitializing
                // Initialising — show spinner while permission dialog is open
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: primary),
                      ),
                      const SizedBox(height: 8),
                      const Text('Requesting mic permission…',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  )
                : (_speechInitialized && !_speechAvailable)
                    // Permission denied after trying
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.mic_off,
                                size: 40, color: Colors.red),
                            const SizedBox(height: 8),
                            const Text(
                              'Microphone permission denied.\nEnable it in Settings → Apps → Prayer Times → Permissions.',
                              style: TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    // Normal mic button (not yet initialised OR available)
                    : GestureDetector(
                        onTap: _toggleListening,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening ? Colors.red : primary,
                            boxShadow: _isListening
                                ? [
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      spreadRadius: 4,
                                    )
                                  ]
                                : [],
                          ),
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
          ),

          const SizedBox(height: 10),
          Center(
            child: Text(
              _isListening
                  ? 'Listening${arabicPhrase ? ' (Arabic)' : ''} — tap to stop'
                  : 'Tap mic to start',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ),

          // ── Live transcription ───────────────────────────────────────────
          if (_isListening || _lastHeard.isNotEmpty) ...[
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _phraseDetectedFlash
                      ? primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.hearing,
                      size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Directionality(
                      textDirection:
                          _isArabic(_lastHeard)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                      child: Text(
                        _lastHeard.isEmpty ? '…' : _lastHeard,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: _phraseDetectedFlash
                              ? primary
                              : Colors.grey[700],
                          fontWeight: _phraseDetectedFlash
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Manual controls ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _increment,
                icon: const Icon(Icons.add),
                label: const Text('Manual +1'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
