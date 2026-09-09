import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;
import '../firebase_options.dart';
import '../models/custom_prayer_times.dart';
import '../services/auth_service.dart';
import '../services/prayer_times_service.dart';

class TimetableUploadScreen extends StatefulWidget {
  const TimetableUploadScreen({super.key});

  @override
  State<TimetableUploadScreen> createState() => _TimetableUploadScreenState();
}

enum _UploadState { idle, extracting, review, saving }
enum _TimetableScope { month, year }

class _TimetableUploadScreenState extends State<TimetableUploadScreen> {
  final _picker = ImagePicker();

  // Selected file
  File? _file;
  bool _isPdf = false;

  // Scope: month or year
  _TimetableScope _scope = _TimetableScope.month;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  _UploadState _state = _UploadState.idle;
  String? _errorMessage;
  List<_DayRow> _rows = [];
  final Set<int> _selectedIndices = {};

  // ── File picking ───────────────────────────────────────────────────────────

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _file = File(result.files.single.path!);
        _isPdf = true;
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickImage() async {
    final xfile = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (xfile != null) {
      setState(() {
        _file = File(xfile.path);
        _isPdf = false;
        _errorMessage = null;
      });
    }
  }

  Future<void> _takePhoto() async {
    final xfile = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 90);
    if (xfile != null) {
      setState(() {
        _file = File(xfile.path);
        _isPdf = false;
        _errorMessage = null;
      });
    }
  }

  // ── Scope / date pickers ───────────────────────────────────────────────────

  Future<void> _pickYear() async {
    int? picked = await showDialog<int>(
      context: context,
      builder: (ctx) => _YearPicker(initialYear: _year),
    );
    if (picked != null) setState(() => _year = picked);
  }

  Future<void> _pickMonth() async {
    await showDialog(
      context: context,
      builder: (ctx) => _MonthYearPicker(
        initialYear: _year,
        initialMonth: _month,
        onSelected: (y, m) => setState(() {
          _year = y;
          _month = m;
        }),
      ),
    );
  }

  // ── Extraction ─────────────────────────────────────────────────────────────

  Future<void> _extract() async {
    if (_file == null) return;
    setState(() {
      _state = _UploadState.extracting;
      _errorMessage = null;
    });

    try {
      final bytes = await _file!.readAsBytes();
      final base64Data = base64Encode(bytes);

      final scopeLabel = _scope == _TimetableScope.year
          ? 'the full year $_year'
          : '${DateFormat('MMMM').format(DateTime(_year, _month))} $_year';

      final prompt = '''This is a prayer timetable.
Extract ALL prayer times for every day shown. The file may contain data for one month or a full year.

Return ONLY a valid JSON object — no explanation, no markdown fences, just raw JSON:
{"year":2025,"month":6,"rows":[[6,1,"04:30","06:00","12:15","15:30","18:45","20:15"],[6,2,"04:32","06:01","12:15","15:31","18:44","20:13"]]}

Fields:
- year: set to null always — the year is provided separately and does not need to be extracted.
- month: for a single-month timetable, the month number 1–12. For a full-year timetable, omit this field (set to null).
- rows: array of arrays, each with 8 elements: [month(1-12), day(1-31), fajr, sunrise, dhuhr, asr, maghrib, isha]

Time rules:
- All times in 24-hour HH:mm format.
- CRITICAL: If a cell shows "--:--", "---", dashes, or any placeholder (no applicable time, e.g. Fajr/Isha in summer at high latitudes), use "" — do NOT guess, interpolate, or copy a nearby time.
- If a column is unreadable, use "".
- Include every day in the file.
- Use compact arrays to keep the response short.''';


      // Media type for the file being sent to the extraction proxy.
      final String mediaType;
      if (_isPdf) {
        mediaType = 'application/pdf';
      } else {
        final ext =
            _file!.path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
        mediaType = 'image/$ext';
      }

      final idToken = AuthService.instance.idToken;
      if (idToken == null) {
        throw Exception('You must be signed in as an admin to extract times.');
      }

      // Call our server-side Cloud Function proxy instead of Anthropic directly.
      // The Claude API key lives in the function, never in the app. The proxy
      // verifies this admin's Firebase token, then returns Claude's response
      // verbatim — so the parsing below is unchanged.
      final response = await http.post(
        Uri.parse(FirebaseConfig.function('extractTimetable')),
        headers: {
          'Authorization': 'Bearer $idToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'is_pdf': _isPdf,
          'media_type': mediaType,
          'data': base64Data,
          'prompt': prompt,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Extraction failed (${response.statusCode}): ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text =
          (data['content'] as List).first['text'] as String;

      // Strip any accidental markdown fences
      var jsonStr = text
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();

      // Truncation recovery: if truncated mid-stream, salvage complete rows
      dynamic topLevel;
      try {
        topLevel = jsonDecode(jsonStr);
      } catch (_) {
        // Try to close the rows array and the outer object
        final lastClose = jsonStr.lastIndexOf(']');
        if (lastClose > 0) {
          jsonStr = jsonStr.substring(0, lastClose + 1);
          jsonStr = jsonStr.replaceAll(RegExp(r',\s*$'), '');
          // Close outer object if needed
          if (!jsonStr.trimRight().endsWith('}')) jsonStr += ']}';
          topLevel = jsonDecode(jsonStr);
        } else {
          rethrow;
        }
      }

      String _s(dynamic v) => (v is String) ? v : '';

      // Read year/month from the wrapper object if present
      int extractedYear = _year;
      int extractedMonth = _month;
      List<dynamic> rowList;

      if (topLevel is Map) {
        final detectedMonth = (topLevel['month'] as num?)?.toInt();
        // Always use the year the admin selected in the scope picker.
        // Never trust the year Claude reads from the PDF — it may be wrong (Hijri,
        // prior-year template, etc.). The user explicitly chose the correct year.
        if (detectedMonth != null) extractedMonth = detectedMonth;
        rowList = topLevel['rows'] as List? ?? [];
      } else {
        rowList = topLevel as List;
      }

      final rows = rowList.map((e) {
        int month, day;
        String fajr, sunrise, dhuhr, asr, maghrib, isha;
        if (e is List) {
          month = (e[0] as num).toInt();
          day = (e[1] as num).toInt();
          fajr = _s(e[2]);
          sunrise = _s(e[3]);
          dhuhr = _s(e[4]);
          asr = _s(e[5]);
          maghrib = _s(e[6]);
          isha = _s(e[7]);
        } else {
          month = (e['month'] as num?)?.toInt() ?? extractedMonth;
          day = (e['day'] as num).toInt();
          fajr = _s(e['fajr']);
          sunrise = _s(e['sunrise']);
          dhuhr = _s(e['dhuhr']);
          asr = _s(e['asr']);
          maghrib = _s(e['maghrib']);
          isha = _s(e['isha']);
        }
        final date =
            '$extractedYear-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        return _DayRow(
          date: date,
          month: month,
          day: day,
          fajr: fajr,
          sunrise: sunrise,
          dhuhr: dhuhr,
          asr: asr,
          maghrib: maghrib,
          isha: isha,
        );
      }).toList()
        ..sort((a, b) {
          final mc = a.month.compareTo(b.month);
          return mc != 0 ? mc : a.day.compareTo(b.day);
        });

      setState(() {
        _rows = rows;
        _year = extractedYear;
        _month = extractedMonth;
        _selectedIndices.clear();
        _state = _UploadState.review;
      });
    } catch (e) {
      setState(() {
        _state = _UploadState.idle;
        _errorMessage = e.toString();
      });
    }
  }

  // ── Save all ───────────────────────────────────────────────────────────────

  Future<void> _saveAll() async {
    setState(() => _state = _UploadState.saving);

    // Get the admin's current GPS location to attach to the prayer times.
    // If location is unavailable, times will apply to everyone (no radius filter).
    double? adminLat, adminLng;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(const Duration(seconds: 10));
        adminLat = pos.latitude;
        adminLng = pos.longitude;
      }
    } catch (_) {
      // Location unavailable — save without location (applies to all users)
    }

    int saved = 0;
    int failed = 0;

    for (final row in _rows) {
      try {
        await PrayerTimesService.save(CustomPrayerTimes(
          date:     row.date,
          fajr:     row.fajr,
          sunrise:  row.sunrise,
          dhuhr:    row.dhuhr,
          asr:      row.asr,
          maghrib:  row.maghrib,
          isha:     row.isha,
          adminLat: adminLat,
          adminLng: adminLng,
          radiusKm: 50,
        ));
        saved++;
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _state = _UploadState.review);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0
          ? 'Saved $saved days successfully!'
          : 'Saved $saved days. $failed failed.'),
      backgroundColor: failed == 0 ? Colors.green : Colors.orange,
    ));
    if (failed == 0) Navigator.pop(context);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Timetable'),
        actions: [
          if (_state == _UploadState.review)
            TextButton.icon(
              onPressed: _saveAll,
              icon: const Icon(Icons.save),
              label: const Text('Save All'),
            ),
        ],
      ),
      body: switch (_state) {
        _UploadState.extracting => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Reading prayer times…'),
                SizedBox(height: 6),
                Text('This may take a few seconds.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        _UploadState.saving => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Saving ${_rows.length} days to Firestore…'),
              ],
            ),
          ),
        _UploadState.review => _buildReviewTable(),
        _ => _buildPicker(),
      },
    );
  }

  // ── Picker UI ──────────────────────────────────────────────────────────────

  Widget _buildPicker() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Scope toggle ────────────────────────────────────────────────
          const Text('Timetable covers',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<_TimetableScope>(
            segments: const [
              ButtonSegment(
                  value: _TimetableScope.month,
                  label: Text('One Month'),
                  icon: Icon(Icons.calendar_view_month)),
              ButtonSegment(
                  value: _TimetableScope.year,
                  label: Text('Full Year'),
                  icon: Icon(Icons.calendar_today)),
            ],
            selected: {_scope},
            onSelectionChanged: (s) =>
                setState(() => _scope = s.first),
          ),
          const SizedBox(height: 16),

          // ── Date selector ────────────────────────────────────────────────
          if (_scope == _TimetableScope.month) ...[
            OutlinedButton.icon(
              onPressed: _pickMonth,
              icon: const Icon(Icons.event, size: 18),
              label: Text(DateFormat('MMMM yyyy')
                  .format(DateTime(_year, _month))),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _pickYear,
              icon: const Icon(Icons.event, size: 18),
              label: Text('Year: $_year'),
            ),
          ],
          const SizedBox(height: 24),

          // ── File picker ──────────────────────────────────────────────────
          const Text('Timetable File',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          if (_file != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    _isPdf
                        ? Icons.picture_as_pdf
                        : Icons.image_outlined,
                    color: _isPdf ? Colors.red : Colors.blue,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _file!.path.split(Platform.pathSeparator).last,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        setState(() => _file = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (!_isPdf)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child:
                    Image.file(_file!, height: 180, fit: BoxFit.cover),
              ),
            const SizedBox(height: 12),
          ],

          // Three pick buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.picture_as_pdf,
                      color: Colors.red),
                  label: const Text('PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_errorMessage!,
                  style: TextStyle(
                      color: Colors.red.shade700, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _file == null ? null : _extract,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Extract Prayer Times'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'AI reads the timetable and extracts all days automatically.\nSupports PDF files and images (photos or screenshots).',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  void _deleteSelected() {
    setState(() {
      final sorted = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
      for (final i in sorted) _rows.removeAt(i);
      _selectedIndices.clear();
    });
  }

  void _selectMonth(int month) {
    setState(() {
      for (var i = 0; i < _rows.length; i++) {
        if (_rows[i].month == month) _selectedIndices.add(i);
      }
    });
  }

  // ── Review table ───────────────────────────────────────────────────────────

  Widget _buildReviewTable() {
    final showMonth = _scope == _TimetableScope.year;
    final hasSelection = _selectedIndices.isNotEmpty;
    final allSelected = _selectedIndices.length == _rows.length && _rows.isNotEmpty;

    // Months present in the data (for quick-select chips in year mode)
    final months = showMonth
        ? (_rows.map((r) => r.month).toSet().toList()..sort())
        : <int>[];

    return Column(
      children: [
        // ── Banner / selection bar ─────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: hasSelection ? Colors.red.shade50 : Colors.green.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (hasSelection) ...[
                Icon(Icons.delete_outline,
                    color: Colors.red.shade700, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_selectedIndices.length} day${_selectedIndices.length == 1 ? '' : 's'} selected',
                    style: TextStyle(
                        fontSize: 13, color: Colors.red.shade700),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedIndices.clear()),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                ),
              ] else ...[
                const Icon(Icons.check_circle,
                    color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_rows.length} days'
                    ' · ${_scope == _TimetableScope.month ? DateFormat('MMMM yyyy').format(DateTime(_year, _month)) : '$_year'}'
                    ' · Tap rows to select',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Quick-select month chips (year mode only) ──────────────────────
        if (showMonth && !hasSelection && months.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Text('Select month: ',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey)),
                ...months.map((m) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(_monthAbbr(m),
                            style: const TextStyle(fontSize: 11)),
                        onPressed: () => _selectMonth(m),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    )),
              ],
            ),
          ),

        // ── Data table ─────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                    const Color(0xFF1565C0).withValues(alpha: 0.1)),
                columnSpacing: 14,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 36,
                // Header checkbox — select / deselect all
                onSelectAll: (selected) => setState(() {
                  if (selected == true) {
                    _selectedIndices.addAll(
                        List.generate(_rows.length, (i) => i));
                  } else {
                    _selectedIndices.clear();
                  }
                }),
                columns: [
                  if (showMonth)
                    const DataColumn(
                        label: Text('Mon',
                            style: TextStyle(
                                fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Day',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Fajr',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Sunrise',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Dhuhr',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Asr',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Maghrib',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Isha',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Edit',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                ],
                rows: _rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  final isSelected = _selectedIndices.contains(i);
                  return DataRow(
                    selected: isSelected,
                    color: isSelected
                        ? WidgetStateProperty.all(
                            Colors.red.shade50)
                        : null,
                    onSelectChanged: (selected) => setState(() {
                      if (selected == true) {
                        _selectedIndices.add(i);
                      } else {
                        _selectedIndices.remove(i);
                      }
                    }),
                    cells: [
                      if (showMonth)
                        DataCell(Text(_monthAbbr(row.month),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600))),
                      DataCell(Text(row.day.toString(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600))),
                      DataCell(_tc(row.fajr)),
                      DataCell(_tc(row.sunrise)),
                      DataCell(_tc(row.dhuhr)),
                      DataCell(_tc(row.asr)),
                      DataCell(_tc(row.maghrib)),
                      DataCell(_tc(row.isha)),
                      DataCell(IconButton(
                        icon: const Icon(Icons.edit, size: 16),
                        onPressed: () => _editRow(row),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tc(String t) => Text(
        t.isEmpty ? '—' : t,
        style: TextStyle(
            color: t.isEmpty ? Colors.grey : Colors.black87,
            fontSize: 12),
      );

  String _monthAbbr(int m) => [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];

  Future<void> _editRow(_DayRow row) async {
    final idx = _rows.indexOf(row);
    final edited = await Navigator.push<_DayRow>(
      context,
      MaterialPageRoute(builder: (_) => _DayEditor(row: row)),
    );
    if (edited != null) setState(() => _rows[idx] = edited);
  }
}

// ── Per-day row ───────────────────────────────────────────────────────────────

class _DayRow {
  final String date;
  final int month;
  final int day;
  String fajr, sunrise, dhuhr, asr, maghrib, isha;

  _DayRow({
    required this.date,
    required this.month,
    required this.day,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });
}

// ── Day editor ────────────────────────────────────────────────────────────────

class _DayEditor extends StatefulWidget {
  final _DayRow row;
  const _DayEditor({required this.row});

  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  late Map<String, String> _times;
  static const _keys = [
    'fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'
  ];
  static const _labels = {
    'fajr': 'Fajr', 'sunrise': 'Sunrise', 'dhuhr': 'Dhuhr',
    'asr': 'Asr', 'maghrib': 'Maghrib', 'isha': 'Isha',
  };

  @override
  void initState() {
    super.initState();
    _times = {
      'fajr': widget.row.fajr,
      'sunrise': widget.row.sunrise,
      'dhuhr': widget.row.dhuhr,
      'asr': widget.row.asr,
      'maghrib': widget.row.maghrib,
      'isha': widget.row.isha,
    };
  }

  Future<void> _pick(String key) async {
    final cur = _times[key]!;
    final initial = cur.isNotEmpty
        ? TimeOfDay(
            hour: int.parse(cur.split(':')[0]),
            minute: int.parse(cur.split(':')[1]))
        : TimeOfDay.now();
    final picked =
        await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      setState(() => _times[key] =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Day ${widget.row.day} — ${widget.row.date}'),
        actions: [
          TextButton(
            onPressed: () {
              widget.row
                ..fajr = _times['fajr']!
                ..sunrise = _times['sunrise']!
                ..dhuhr = _times['dhuhr']!
                ..asr = _times['asr']!
                ..maghrib = _times['maghrib']!
                ..isha = _times['isha']!;
              Navigator.pop(context, widget.row);
            },
            child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _keys.map((key) {
          final t = _times[key]!;
          final isSet = t.isNotEmpty;
          return ListTile(
            title: Text(_labels[key]!),
            subtitle: isSet
                ? null
                : const Text('Not set', style: TextStyle(color: Colors.grey, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSet)
                  Tooltip(
                    message: 'Clear (mark as not set)',
                    child: IconButton(
                      icon: const Icon(Icons.cancel_outlined, size: 20, color: Colors.red),
                      onPressed: () => setState(() => _times[key] = ''),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _pick(key),
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text(isSet ? t : 'Set time'),
                  style: isSet
                      ? OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1565C0))
                      : OutlinedButton.styleFrom(foregroundColor: Colors.grey),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Month / Year picker ───────────────────────────────────────────────────────

class _MonthYearPicker extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final void Function(int year, int month) onSelected;

  const _MonthYearPicker({
    required this.initialYear,
    required this.initialMonth,
    required this.onSelected,
  });

  @override
  State<_MonthYearPicker> createState() => _MonthYearPickerState();
}

class _MonthYearPickerState extends State<_MonthYearPicker> {
  late int _year;
  late int _month;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    _month = widget.initialMonth;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Month'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left)),
              Text('$_year',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                  onPressed: () => setState(() => _year++),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 2.2,
            children: List.generate(12, (i) {
              final sel = i + 1 == _month;
              return GestureDetector(
                onTap: () => setState(() => _month = i + 1),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFF1565C0)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _months[i].substring(0, 3),
                    style: TextStyle(
                      color: sel ? Colors.white : Colors.black87,
                      fontWeight:
                          sel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            widget.onSelected(_year, _month);
            Navigator.pop(context);
          },
          child: const Text('Select'),
        ),
      ],
    );
  }
}

// ── Year-only picker ──────────────────────────────────────────────────────────

class _YearPicker extends StatefulWidget {
  final int initialYear;
  const _YearPicker({required this.initialYear});

  @override
  State<_YearPicker> createState() => _YearPickerState();
}

class _YearPickerState extends State<_YearPicker> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Year'),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              onPressed: () => setState(() => _year--),
              icon: const Icon(Icons.chevron_left)),
          Text('$_year',
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold)),
          IconButton(
              onPressed: () => setState(() => _year++),
              icon: const Icon(Icons.chevron_right)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _year),
          child: const Text('Select'),
        ),
      ],
    );
  }
}
