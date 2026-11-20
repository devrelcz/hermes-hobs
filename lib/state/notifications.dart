import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/strings.dart';

/// Why a hob wants the user's attention.
enum AlertKind { reply, approval, clarify }

/// Something a hob did that is worth a system notification.
class HobAlert {
  const HobAlert(this.kind, this.text);

  final AlertKind kind;

  /// Reply preview, the command to approve, or the question.
  final String text;

  /// True when the hob is blocked until the user answers.
  bool get blocking => kind != AlertKind.reply;
}

/// Shortens [text] to one line for a notification body: markdown marks and
/// line breaks go, long text ends with an ellipsis.
String notificationPreview(String text, {int max = 140}) {
  var t = text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      )
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.length > max) t = '${t.substring(0, max - 1).trimRight()}…';
  return t;
}

/// Local (on-device) notifications. One notification per hob: a newer one
/// replaces the older, and opening the hob's chat clears it.
abstract class Notifier {
  /// Hob names of notifications the user tapped while the app was running.
  Stream<String> get taps;

  /// Sets the plugin up. Returns the hob whose notification launched the
  /// app, if one did.
  Future<String?> init();

  /// Asks the system for permission. True when notifications may show.
  Future<bool> requestPermission();

  /// Whether the system lets the app show notifications right now; null
  /// when it can't tell.
  Future<bool?> permitted();

  Future<void> show({
    required String hob,
    required String title,
    required String body,
    required bool blocking,
  });

  Future<void> clear(String hob);
}

/// Stable notification id for a hob (String.hashCode is not stable across
/// runs, and a cold-started app must still clear the old notification).
int notificationId(String hob) {
  var h = 0x811c9dc5;
  for (final c in hob.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// [Notifier] on `flutter_local_notifications` (Android, iOS, macOS). Every
/// call swallows platform errors: a missing notification must never break
/// the chat.
class LocalNotifier implements Notifier {
  LocalNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();
  Future<String?>? _init;

  static const _channelId = 'hobs';

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> init() => _init ??= _setup();

  Future<String?> _setup() async {
    try {
      // No permission prompt here: the app asks when it first matters
      // (the first prompt sent, or the settings switch).
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (r) {
          final hob = r.payload;
          if (hob != null && hob.isNotEmpty) _taps.add(hob);
        },
      );
      // Create the channel up front, so it is listed in the system settings
      // before the first notification.
      final s = Strings.current;
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              _channelId,
              s.notifyChannelName,
              description: s.notifyChannelDescription,
              importance: Importance.high,
            ),
          );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final hob = launch!.notificationResponse?.payload;
        if (hob != null && hob.isNotEmpty) return hob;
      }
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
    return null;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    try {
      return switch (defaultTargetPlatform) {
        TargetPlatform.android =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.requestNotificationsPermission() ??
              false,
        TargetPlatform.iOS =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, sound: true) ??
              false,
        TargetPlatform.macOS =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, sound: true) ??
              false,
        _ => false,
      };
    } catch (e) {
      debugPrint('notification permission: $e');
      return false;
    }
  }

  @override
  Future<bool?> permitted() async {
    await init();
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled();
        case TargetPlatform.iOS:
          final o = await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions();
          return o?.isEnabled;
        case TargetPlatform.macOS:
          final o = await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions();
          return o?.isEnabled;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> show({
    required String hob,
    required String title,
    required String body,
    required bool blocking,
  }) async {
    await init();
    final s = Strings.current;
    try {
      await _plugin.show(
        id: notificationId(hob),
        title: title,
        body: body,
        payload: hob,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            s.notifyChannelName,
            channelDescription: s.notifyChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: DarwinNotificationDetails(threadIdentifier: hob),
          macOS: DarwinNotificationDetails(threadIdentifier: hob),
        ),
      );
    } catch (e) {
      debugPrint('notification failed: $e');
    }
  }

  @override
  Future<void> clear(String hob) async {
    if (_init == null) return;
    try {
      await _plugin.cancel(id: notificationId(hob));
    } catch (_) {}
  }
}

/// Asks iOS for a little more time after the app leaves the screen, so a
/// reply that is still streaming can finish and notify. iOS ends it after
/// about 30 seconds whatever we do; other platforms don't need it.
class BackgroundTime {
  static const _channel = MethodChannel('hobs/background');
  bool _held = false;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> begin() async {
    if (_held || !_supported) return;
    _held = true;
    try {
      await _channel.invokeMethod<void>('begin');
    } catch (_) {
      _held = false;
    }
  }

  Future<void> end() async {
    if (!_held) return;
    _held = false;
    try {
      await _channel.invokeMethod<void>('end');
    } catch (_) {}
  }
}
