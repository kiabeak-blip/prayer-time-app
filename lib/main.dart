import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/settings_about.dart';
import 'screens/counter_screen.dart';
import 'screens/home_screen.dart';
import 'screens/qibla_screen.dart';
import 'screens/quran_screen.dart';
import 'screens/daily_screen.dart';
import 'screens/admin_screen.dart';
import 'services/notification_service.dart';
import 'services/azan_service.dart';
import 'services/settings_service.dart';
import 'services/contact_service.dart';
import 'services/location_cache.dart';

final homeScreenKey     = GlobalKey<HomeScreenState>();
final settingsScreenKey = GlobalKey<SettingsScreenState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('NotificationService init error: $e');
  }
  try {
    await AzanService.instance.init();
  } catch (e) {
    debugPrint('AzanService init error: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Sync notification time format with device setting on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
      NotificationService.setTimeFormat(use24h);
    });
    return MaterialApp(
      title: 'Prayer Times',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color.fromARGB(255, 198, 147, 27),
      ),
      home: const HomeWithBottomTabs(),
    );
  }
}

class HomeWithBottomTabs extends StatefulWidget {
  const HomeWithBottomTabs({super.key});

  @override
  HomeWithBottomTabsState createState() => HomeWithBottomTabsState();
}

class HomeWithBottomTabsState extends State<HomeWithBottomTabs> {
  int _currentIndex = 0;
  int _titleTapCount = 0;
  DateTime? _lastTitleTap;
  String _selectedLanguage = 'en';

  final List<Widget> _screens = [
    HomeScreen(key: homeScreenKey),
    DailyScreen(),
    QuranScreen(),
    CounterScreen(),
    QiblaScreen(),
    SettingsScreen(key: settingsScreenKey),
  ];

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final lang = await SettingsService.getLanguage();
    if (mounted) setState(() => _selectedLanguage = lang);
  }

  void _onLanguageChanged(String? lang) {
    if (lang == null) return;
    setState(() => _selectedLanguage = lang);
    SettingsService.setLanguage(lang);
    homeScreenKey.currentState?.setLanguage(lang);
    settingsScreenKey.currentState?.setLanguage(lang);
  }

  void _onTitleTap() {
    final now = DateTime.now();
    if (_lastTitleTap == null ||
        now.difference(_lastTitleTap!) > const Duration(seconds: 2)) {
      _titleTapCount = 1;
    } else {
      _titleTapCount++;
    }
    _lastTitleTap = now;

    if (_titleTapCount >= 7) {
      _titleTapCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      ).then((_) {
        homeScreenKey.currentState?.refreshAdminTimes();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTap,
          behavior: HitTestBehavior.opaque,
          child: const Text('Prayer Times App'),
        ),
        actions: [
          // ── Language flag selector — visible on all pages ──────────────
          DropdownButton<String>(
            value: _selectedLanguage,
            underline: const SizedBox(),
            icon: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                  value: 'en',
                  child: Text('🇬🇧', style: TextStyle(fontSize: 22))),
              DropdownMenuItem(
                  value: 'sv',
                  child: Text('🇸🇪', style: TextStyle(fontSize: 22))),
              DropdownMenuItem(
                  value: 'ar',
                  child: Text('🇸🇦', style: TextStyle(fontSize: 22))),
              DropdownMenuItem(
                  value: 'am',
                  child: Text('🇪🇹', style: TextStyle(fontSize: 22))),
            ],
            onChanged: _onLanguageChanged,
          ),
          // WhatsApp — opens nearest area admin, falls back to central
          IconButton(
            icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
            tooltip: 'WhatsApp',
            onPressed: () async {
              final number = await ContactService.findNearest(
                  LocationCache.lat, LocationCache.lng);
              await launchUrl(
                Uri.parse('https://wa.me/$number'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => homeScreenKey.currentState?.refresh(),
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color.fromARGB(255, 211, 145, 31),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.wb_sunny_outlined), label: 'Daily'),
          BottomNavigationBarItem(
              icon: Icon(Icons.menu_book), label: 'Quran'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Counter'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Qibla'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
