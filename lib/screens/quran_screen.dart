import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../data/quran_data.dart';

// ─────────────────────────────────────────────────────────────────────────────

class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});
  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

enum _PlayState { idle, loading, playing, paused }
enum _TextLoad { empty, fetching, ready, error }

// ─────────────────────────────────────────────────────────────────────────────

class _QuranScreenState extends State<QuranScreen> {
  // ── Selection ──────────────────────────────────────────────────────────────
  int _surahIdx   = 0;
  int _ayahStart  = 1;
  int _repeatEach = 1;   // per-ayah repeat (default: read each once)
  double _speed   = 1.0;
  bool _loopSurah = false; // loop the whole surah when it ends

  // End ayah is always the last ayah of the surah
  int get _ayahEnd => kSurahs[_surahIdx].ayahCount;

  // ── Playback ───────────────────────────────────────────────────────────────
  _PlayState _playState = _PlayState.idle;
  int _currentAyah = 1;
  int _currentRepeat = 1;

  // ── Verse text ─────────────────────────────────────────────────────────────
  _TextLoad _textLoad = _TextLoad.empty;
  List<String> _verses = [];
  static final Map<int, List<String>> _textCache = {};

  // ── Scroll / keys ──────────────────────────────────────────────────────────
  final _scrollCtrl = ScrollController();
  final Map<int, GlobalKey> _verseKeys = {};

  // ── Surah picker ───────────────────────────────────────────────────────────
  bool _showSurahPicker = false;
  final _searchCtrl = TextEditingController();
  List<SurahInfo> _filtered = kSurahs;

  // ── Player ─────────────────────────────────────────────────────────────────
  final _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;

  SurahInfo get _surah => kSurahs[_surahIdx];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen(_onComplete);
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      if (s == PlayerState.playing && _playState != _PlayState.playing) {
        setState(() => _playState = _PlayState.playing);
      }
    });
    _searchCtrl.addListener(_onSearch);
    _loadVerses();
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Surah text fetch ───────────────────────────────────────────────────────

  Future<void> _loadVerses() async {
    final num = _surah.number;
    if (_textCache.containsKey(num)) {
      if (mounted) {
        setState(() {
          _verses = _textCache[num]!;
          _textLoad = _TextLoad.ready;
        });
      }
      return;
    }
    setState(() => _textLoad = _TextLoad.fetching);
    try {
      final verses = await _fetchSurahText(num);
      _textCache[num] = verses;
      if (!mounted) return;
      setState(() {
        _verses = verses;
        _textLoad = _TextLoad.ready;
      });
    } catch (e) {
      if (mounted) setState(() => _textLoad = _TextLoad.error);
    }
  }

  static Future<List<String>> _fetchSurahText(int surahNum) async {
    final url = 'https://api.alquran.cloud/v1/surah/$surahNum/ar';
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final bytes = await consolidateHttpClientResponseBytes(res);
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return (body['data']['ayahs'] as List)
          .map((a) => a['text'] as String)
          .toList();
    } finally {
      client.close();
    }
  }

  // ── Surah picker ───────────────────────────────────────────────────────────

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? kSurahs
          : kSurahs
              .where((s) =>
                  s.nameTranslit.toLowerCase().contains(q) ||
                  s.nameEnglish.toLowerCase().contains(q) ||
                  s.nameArabic.contains(q) ||
                  s.number.toString() == q)
              .toList();
    });
  }

  void _selectSurah(SurahInfo s) {
    _stopPlayback();
    setState(() {
      _surahIdx  = kSurahs.indexOf(s);
      _ayahStart = 1;
      _showSurahPicker = false;
      _searchCtrl.clear();
      _filtered  = kSurahs;
      _verses    = [];
      _textLoad  = _TextLoad.empty;
    });
    _loadVerses();
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  bool _playingBismillah = false;

  bool get _shouldPlayBismillah =>
      _currentAyah == 1 &&
      _surah.number != 1 && // Al-Fatiha already starts with Bismillah as ayah 1
      _surah.number != 9;   // At-Tawbah has no Bismillah

  Future<void> _startPlay() async {
    _currentAyah   = 1;   // always start from the first ayah
    _ayahStart     = 1;
    _currentRepeat = 1;
    if (_shouldPlayBismillah) {
      _playingBismillah = true;
      await _playBismillahThenContinue();
    } else {
      _playingBismillah = false;
      await _playNow();
    }
  }

  Future<void> _playBismillahThenContinue() async {
    if (!mounted) return;
    setState(() => _playState = _PlayState.loading);
    try {
      // Global ayah 1 = Surah 1 Ayah 1 = Bismillah in Minshawi's voice
      final path = await _cachedPath(1, 1);
      if (!mounted) return;
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      await _player.setPlaybackRate(_speed);
    } catch (e) {
      debugPrint('[Quran] Bismillah audio error: $e');
      _playingBismillah = false;
      await _playNow(); // continue even if Bismillah download fails
    }
  }

  Future<void> _playNow() async {
    if (!mounted) return;
    setState(() => _playState = _PlayState.loading);
    _scrollToCurrent();
    try {
      final path = await _cachedPath(_surah.number, _currentAyah);
      debugPrint('[Quran] Playing file: $path');
      if (!mounted) return;
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      await _player.setPlaybackRate(_speed);
      // Pre-fetch the next ayah in the background so it's ready instantly
      _prefetchNext();
    } catch (e) {
      debugPrint('[Quran] Audio error: $e');
      if (mounted) {
        setState(() => _playState = _PlayState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audio error: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  /// Downloads the next ayah's audio in the background while the current one plays.
  void _prefetchNext() {
    final next = _currentAyah + 1;
    if (next <= _ayahEnd) {
      _cachedPath(_surah.number, next).catchError((_) {});
    }
  }

  void _onComplete(void _) {
    if (!mounted || _playState == _PlayState.idle) return;

    // Bismillah just finished — now play the actual first ayah
    if (_playingBismillah) {
      _playingBismillah = false;
      setState(() {});
      _playNow();
      return;
    }

    final infinite    = _repeatEach == -1;
    final moreRepeats = infinite || _currentRepeat < _repeatEach;

    if (moreRepeats) {
      // Repeat this ayah again
      if (!infinite) _currentRepeat++;
      setState(() {});
      _playNow();
    } else if (_currentAyah < _ayahEnd) {
      // Advance to the next ayah
      _currentAyah++;
      _currentRepeat = 1;
      setState(() {});
      _playNow();
    } else {
      // Reached the last ayah
      if (_loopSurah) {
        // Restart the whole surah from _ayahStart
        _currentAyah   = _ayahStart;
        _currentRepeat = 1;
        setState(() {});
        if (_shouldPlayBismillah) {
          _playingBismillah = true;
          _playBismillahThenContinue();
        } else {
          _playNow();
        }
      } else {
        // Stop
        if (mounted) setState(() => _playState = _PlayState.idle);
      }
    }
  }

  Future<void> _togglePause() async {
    if (_playState == _PlayState.playing) {
      await _player.pause();
      if (mounted) setState(() => _playState = _PlayState.paused);
    } else if (_playState == _PlayState.paused) {
      await _player.resume();
      if (mounted) setState(() => _playState = _PlayState.playing);
    }
  }

  Future<void> _stopPlayback() async {
    _playingBismillah = false;
    await _player.stop();
    if (mounted) setState(() => _playState = _PlayState.idle);
  }

  Future<void> _skipForward() async {
    if (_playState == _PlayState.idle) return;
    if (_currentAyah < _ayahEnd) { _currentAyah++; _currentRepeat = 1; }
    await _playNow();
  }

  Future<void> _skipBack() async {
    if (_playState == _PlayState.idle) return;
    if (_currentRepeat > 1) { _currentRepeat = 1; }
    else if (_currentAyah > _ayahStart) { _currentAyah--; _currentRepeat = 1; }
    await _playNow();
  }

  void _scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _verseKeys[_currentAyah];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
          alignment: 0.25,
        );
      }
    });
  }

  // ── Audio download / cache ─────────────────────────────────────────────────

  static Future<String> _cachedPath(int surah, int ayah) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}${Platform.pathSeparator}quran_minshawi');
    await dir.create(recursive: true);
    final file =
        File('${dir.path}${Platform.pathSeparator}${surah}_$ayah.mp3');
    if (await file.exists()) return file.path;
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(minshawuiUrl(surah, ayah)));
      req.headers.set(
          HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      await file.writeAsBytes(await consolidateHttpClientResponseBytes(res));
      return file.path;
    } finally {
      client.close();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildHeader(theme),
        if (_showSurahPicker)
          Expanded(child: _buildSurahPicker(theme))
        else ...[
          Expanded(child: _buildVerseArea(theme)),
          _buildBottomPanel(theme),
        ],
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Surah selector button
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showSurahPicker = !_showSurahPicker),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${_surah.number}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _surah.nameTranslit,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        Text(
                          '${_surah.nameEnglish}  •  ${_surah.ayahCount} ayahs',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showSurahPicker ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Arabic name
          Text(
            _surah.nameArabic,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  // ── Surah picker ───────────────────────────────────────────────────────────

  Widget _buildSurahPicker(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search surah…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final s = _filtered[i];
              final selected = s.number == _surah.number;
              return ListTile(
                selected: selected,
                selectedTileColor: const Color(0xFF1B5E20).withValues(alpha: 0.1),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      selected ? const Color(0xFF2E7D32) : Colors.grey.shade200,
                  child: Text('${s.number}',
                      style: TextStyle(
                          fontSize: 12,
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(s.nameTranslit,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(s.nameEnglish,
                    style: const TextStyle(fontSize: 12)),
                trailing: Text(
                  s.nameArabic,
                  style: TextStyle(
                      color: selected
                          ? const Color(0xFF2E7D32)
                          : Colors.grey.shade700,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  textDirection: TextDirection.rtl,
                ),
                onTap: () => _selectSurah(s),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Verse area ─────────────────────────────────────────────────────────────

  Widget _buildVerseArea(ThemeData theme) {
    if (_textLoad == _TextLoad.fetching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF2E7D32)),
            SizedBox(height: 12),
            Text('Loading verses…'),
          ],
        ),
      );
    }

    if (_textLoad == _TextLoad.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Could not load verse text.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadVerses,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_verses.isEmpty) {
      return const Center(
        child: Text('Select a surah to begin.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final isActive = _playState != _PlayState.idle;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _verses.length,
      itemBuilder: (ctx, i) {
        final ayahNum = i + 1;
        final isInRange = ayahNum >= _ayahStart && ayahNum <= _ayahEnd;
        final isCurrent = isActive && ayahNum == _currentAyah;
        final key = _verseKeys.putIfAbsent(ayahNum, () => GlobalKey());

        return _VerseTile(
          key: key,
          ayahNum: ayahNum,
          text: _verses[i],
          isInRange: isInRange,
          isCurrent: isCurrent,
          playState: _playState,
          onTap: () {
            // Tap a verse to jump to it as the start point
            setState(() => _ayahStart = ayahNum);
          },
        );
      },
    );
  }

  // ── Bottom panel ───────────────────────────────────────────────────────────

  Widget _buildBottomPanel(ThemeData theme) {
    final isActive = _playState != _PlayState.idle;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: isActive
          ? _buildNowPlayingBar(theme)
          : _buildIdleControls(theme),
    );
  }

  Widget _buildNowPlayingBar(ThemeData theme) {
    const green = Color(0xFF2E7D32);
    final repeatLabel = _repeatEach == -1
        ? '∞'
        : '$_currentRepeat / $_repeatEach';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_playState == _PlayState.loading)
            const LinearProgressIndicator(
                backgroundColor: Colors.white24, color: Colors.white),
          const SizedBox(height: 4),
          Row(
            children: [
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_surah.nameTranslit}  •  Ayah $_currentAyah',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    Text(
                      'Repeat $repeatLabel  •  ${_speed}x  •  Range $_ayahStart–$_ayahEnd',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Controls
              IconButton(
                onPressed: _skipBack,
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                iconSize: 26,
                visualDensity: VisualDensity.compact,
              ),
              GestureDetector(
                onTap: _togglePause,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _playState == _PlayState.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: green,
                    size: 28,
                  ),
                ),
              ),
              IconButton(
                onPressed: _skipForward,
                icon: const Icon(Icons.skip_next, color: Colors.white),
                iconSize: 26,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: _stopPlayback,
                icon: const Icon(Icons.stop, color: Colors.white70),
                iconSize: 22,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdleControls(ThemeData theme) {
    const green     = Color(0xFF2E7D32);
    const darkGreen = Color(0xFF1B5E20);

    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Options row ───────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Speed
                DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    value: _speed,
                    isDense: true,
                    borderRadius: BorderRadius.circular(10),
                    dropdownColor: Colors.white,
                    icon: Icon(Icons.speed, size: 14, color: green),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: green),
                    onChanged: (v) async {
                      setState(() => _speed = v ?? 1.0);
                      if (_playState == _PlayState.playing ||
                          _playState == _PlayState.paused) {
                        await _player.setPlaybackRate(_speed);
                      }
                    },
                    items: [0.5, 0.75, 1.0, 1.25, 1.5]
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text('${s}x',
                                  style: TextStyle(
                                      fontSize: 13, color: green)),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(width: 16),
                // Per-ayah repeat
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _repeatEach,
                    isDense: true,
                    borderRadius: BorderRadius.circular(10),
                    dropdownColor: Colors.white,
                    icon: Icon(Icons.repeat_one, size: 14, color: darkGreen),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: darkGreen),
                    onChanged: (v) => setState(() => _repeatEach = v ?? 1),
                    items: [1, 2, 3, 5, 7, 10, -1]
                        .map((n) => DropdownMenuItem(
                              value: n,
                              child: Text(
                                n == -1 ? '∞' : '×$n',
                                style: TextStyle(
                                    fontSize: 13, color: darkGreen),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(width: 16),
                // Repeat surah toggle
                GestureDetector(
                  onTap: () => setState(() => _loopSurah = !_loopSurah),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _loopSurah
                          ? green.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _loopSurah
                            ? green
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.loop,
                            size: 15,
                            color: _loopSurah
                                ? green
                                : Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          'Repeat Surah',
                          style: TextStyle(
                              fontSize: 12,
                              color: _loopSurah
                                  ? green
                                  : Colors.grey.shade400,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Play button ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startPlay,
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(
                  'Play  ${_surah.nameTranslit}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ── Verse tile ────────────────────────────────────────────────────────────────

class _VerseTile extends StatelessWidget {
  final int ayahNum;
  final String text;
  final bool isInRange;
  final bool isCurrent;
  final _PlayState playState;
  final VoidCallback onTap;

  const _VerseTile({
    super.key,
    required this.ayahNum,
    required this.text,
    required this.isInRange,
    required this.isCurrent,
    required this.playState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Current: bright green highlight
    // In range: subtle green tint
    // Out of range: dimmed
    Color? bgColor;
    Color textColor;
    double opacity;

    if (isCurrent) {
      bgColor = const Color(0xFF1B5E20).withValues(alpha: isDark ? 0.5 : 0.12);
      textColor = isDark ? Colors.white : const Color(0xFF1B3A1B);
      opacity = 1.0;
    } else if (isInRange) {
      bgColor = const Color(0xFF2E7D32).withValues(alpha: isDark ? 0.12 : 0.05);
      textColor = theme.colorScheme.onSurface;
      opacity = 1.0;
    } else {
      bgColor = null;
      textColor = theme.colorScheme.onSurface;
      opacity = 0.35;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: isCurrent
              ? Border.all(color: const Color(0xFF2E7D32), width: 1.5)
              : null,
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Opacity(
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ayah number badge
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(top: 4, left: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrent
                        ? const Color(0xFF2E7D32)
                        : (isInRange
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: Center(
                    child: Text(
                      '$ayahNum',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCurrent ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Verse text (Arabic, RTL)
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        fontSize: isCurrent ? 22 : 19,
                        height: 1.9,
                        color: textColor,
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                      ),
                      child: Text(text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mini stepper ──────────────────────────────────────────────────────────────

class _MiniStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final Color color;
  final ValueChanged<int> onChanged;

  const _MiniStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.color = const Color(0xFF2E7D32),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: value > min ? () => onChanged(value - 1) : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.remove,
                size: 14,
                color: value > min ? color : Colors.grey.shade300),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: color),
          ),
        ),
        InkWell(
          onTap: value < max ? () => onChanged(value + 1) : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.add,
                size: 14,
                color: value < max ? color : Colors.grey.shade300),
          ),
        ),
      ],
    );
  }
}

