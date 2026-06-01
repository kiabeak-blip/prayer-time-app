import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId        = 'prayer_times_channel';
  static const _channelName      = 'Prayer Times';
  static const _channelDesc      = 'Prayer time reminders and admin alerts';

  // Persistent countdown notification
  static const _countdownId          = 888;
  static const _countdownChannelId   = 'prayer_countdown';
  static const _countdownChannelName = 'Prayer Countdown';

  static Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Prayer Times App',
      appUserModelId: 'com.example.PrayerTimesApp',
      guid: 'A7B9C3D5-E6F1-4A2B-8C3D-9E5F7A1B2C4D',
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(settings: initSettings);

    // Create / update the Android notification channel explicitly so
    // lock-screen visibility and heads-up banner are guaranteed.
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Alert channel — high priority, sound, vibration
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      ),
    );

    // Countdown channel — silent but high enough importance to show on
    // lock screen and AOD. Importance.low is excluded from lock screen
    // on most Android/Samsung devices; defaultImportance fixes that.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _countdownChannelId,
        _countdownChannelName,
        description: 'Live countdown to the next prayer time',
        importance: Importance.high,  // ensures lock screen + status bar icon
        playSound: false,
        enableVibration: false,
        showBadge: true,
      ),
    );

    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return true;
  }

  // Schedule one notification per enabled prayer for today (skips past times)
  static Future<void> schedulePrayerNotifications({
    required Map<String, DateTime> prayerTimes,
    required Set<String> enabledPrayers,
  }) async {
    await cancelAll();

    final now = DateTime.now();
    int id = 0;

    for (final entry in prayerTimes.entries) {
      if (!enabledPrayers.contains(entry.key)) continue;
      if (entry.value.isBefore(now)) continue;

      final prayerLabel = _label(entry.key);
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          fullScreenIntent: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(
          scenario: WindowsNotificationScenario.reminder,
        ),
      );
      final scheduledDate = tz.TZDateTime.from(entry.value, tz.local);
      final notifId = id++;
      try {
        await _plugin.zonedSchedule(
          id: notifId,
          title: 'Prayer Time',
          body: '$prayerLabel — time to pray',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (_) {
        // Exact alarms not permitted — fall back to inexact (fires within ~minutes)
        await _plugin.zonedSchedule(
          id: notifId,
          title: 'Prayer Time',
          body: '$prayerLabel — time to pray',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  /// Cancels only the scheduled prayer-alert notifications (not the countdown).
  static Future<void> cancelAll() async {
    // Cancel IDs 0–20 (prayer alerts) but leave the countdown (id 888) intact
    for (int i = 0; i < 20; i++) {
      await _plugin.cancel(id: i);
    }
  }

  // ── Persistent countdown notification ────────────────────────────────────

  /// Shows or updates the live countdown notification in the status bar.
  /// Call this every minute from the home screen timer.
  static Future<void> updateCountdownNotification({
    required String prayerName,
    required DateTime prayerTime,
  }) async {
    final now  = DateTime.now();
    final diff = prayerTime.difference(now);
    if (diff.isNegative) return;

    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    final timeStr = _formatTime(prayerTime);

    final String countdownText;
    if (h > 0) {
      countdownText = '${h}h ${m}min remaining  •  $timeStr';
    } else if (m > 0) {
      countdownText = '${m} min remaining  •  $timeStr';
    } else {
      countdownText = 'Starting now  •  $timeStr';
    }

    // BigTextStyle: expands the notification on the lock screen so the full
    // countdown + prayer time is readable without unlocking the phone.
    final bigText = BigTextStyleInformation(
      '$countdownText\n\n🕌  Prayer Times App',
      htmlFormatBigText: false,
      contentTitle: 'Next Prayer: $prayerName',
      summaryText: 'Prayer Times',
    );

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _countdownChannelId,
        _countdownChannelName,
        channelDescription: 'Live countdown to the next prayer time',
        importance: Importance.high,   // HIGH = lock screen + status bar icon
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: false,
        enableLights: false,
        showWhen: false,
        icon: '@mipmap/ic_launcher',
        visibility: NotificationVisibility.public,
        styleInformation: bigText,
        // Progress bar
        showProgress: true,
        maxProgress: prayerTime.difference(_startOfDay(prayerTime)).inMinutes,
        progress: now.difference(_startOfDay(now)).inMinutes,
        indeterminate: false,
        ticker: 'Next prayer: $prayerName',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
        interruptionLevel: InterruptionLevel.passive,
      ),
      windows: const WindowsNotificationDetails(),
    );

    await _plugin.show(
      id: _countdownId,
      title: 'Next Prayer: $prayerName',
      body: countdownText,
      notificationDetails: details,
    );
  }

  /// Removes the countdown notification (e.g. when all prayers are done).
  static Future<void> cancelCountdownNotification() =>
      _plugin.cancel(id: _countdownId);

  static String _formatTime(DateTime dt) {
    // Use 24h or 12h based on stored device preference
    final use24h = _use24hFormat;
    if (use24h) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  // Cached from app startup via setTimeFormat()
  static bool _use24hFormat = true;
  static void setTimeFormat(bool use24h) => _use24hFormat = use24h;

  static DateTime _startOfDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  /// Show an immediate notification (e.g. new admin request alert).
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      windows: WindowsNotificationDetails(),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static String _label(String key) {
    const labels = {
      'fajr': 'Fajr',
      'sunrise': 'Sunrise',
      'dhuhr': 'Dhuhr',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
    };
    return labels[key] ?? key;
  }
}
