import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/strings.dart';

/// Why a hob wants the user's attention.
enum AlertKind { reply, approval, clarify }

/// Something a hob did that is worth a system notification.
class HobAlert {
  const HobAlert(this.kind, this.text, {this.id});

  final AlertKind kind;

  /// Reply preview, the command to approve, or the question.
  final String text;

  /// Which request it is (`request:<id>`, `prompt:<id>`), so an answer from
  /// the notification reaches that request and no later one.
  final String? id;

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

/// What a notification is about, carried as its payload: `hob:<name>` for a
/// Hob's chat, `group:<room id>` for a group chat. A bare name is a Hob
/// (notifications shown before group chats notified).
class NotifyTarget {
  const NotifyTarget.hob(this.id) : isGroup = false;
  const NotifyTarget.group(this.id) : isGroup = true;

  /// The Hob's profile name or the room id.
  final String id;
  final bool isGroup;

  String get key => isGroup ? 'group:$id' : 'hob:$id';

  static NotifyTarget? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith('group:')) {
      final id = payload.substring(6);
      return id.isEmpty ? null : NotifyTarget.group(id);
    }
    final name = payload.startsWith('hob:') ? payload.substring(4) : payload;
    return name.isEmpty ? null : NotifyTarget.hob(name);
  }

  @override
  bool operator ==(Object other) =>
      other is NotifyTarget && other.id == id && other.isGroup == isGroup;

  @override
  int get hashCode => Object.hash(id, isGroup);

  @override
  String toString() => key;
}

/// Local (on-device) notifications. One notification per Hob and one per
/// group chat (keyed by [NotifyTarget.key]): a newer one replaces the older,
/// and opening that chat clears it.
abstract class Notifier {
  /// Payloads ([NotifyTarget.key]) of notifications the user tapped while
  /// the app was running.
  Stream<String> get taps;

  /// Sets the plugin up. Returns the payload of the notification that
  /// launched the app, if one did.
  Future<String?> init();

  /// Asks the system for permission. True when notifications may show.
  Future<bool> requestPermission();

  /// Whether the system lets the app show notifications right now; null
  /// when it can't tell.
  Future<bool?> permitted();

  /// Shows (or replaces) the notification for [key] ([NotifyTarget.key]).
  /// [face] is the Hob's face as PNG, shown large. With [approve] set to
  /// the request's id it offers Deny / Allow once; a pressed button comes
  /// back on [taps] as `<key>#<choice>#<request id>`.
  Future<void> show({
    required String key,
    required String title,
    required String body,
    required bool blocking,
    Uint8List? face,
    String? approve,
  });

  Future<void> clear(String key);

  /// Clears every notification the app shows (another account took over).
  Future<void> clearAll();
}

/// Stable notification id for a [NotifyTarget.key] (String.hashCode is not
/// stable across runs, and a cold-started app must still clear the old
/// notification). A Hob keeps the id of its bare name, the one notifications
/// had before group chats notified.
int notificationId(String key) {
  final source = key.startsWith('hob:') ? key.substring(4) : key;
  var h = 0x811c9dc5;
  for (final c in source.codeUnits) {
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
          // The hob's silhouette, white for the status bar (the launcher
          // icon is adaptive and cannot be a small icon).
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (r) {
          final payload = r.payload;
          if (payload == null || payload.isEmpty) return;
          final (key, ref) = _split(payload);
          final action = r.actionId;
          _taps.add(
            action != null && action.isNotEmpty && ref != null
                ? '$key#$action#$ref'
                : key,
          );
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
      // A cold start only opens the chat, even from a button: the request
      // is answered in the app, once it is seen again.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final payload = launch!.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) return _split(payload).$1;
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

  /// Android bundles the Hobs' notifications under one summary.
  static const _group = 'cz.devrel.hermeshobs.chats';
  static const _summaryId = 0;

  /// The payload's target and, for an approval, its request id.
  static (String, String?) _split(String payload) {
    final i = payload.indexOf('#');
    return i < 0
        ? (payload, null)
        : (payload.substring(0, i), payload.substring(i + 1));
  }

  @override
  Future<void> show({
    required String key,
    required String title,
    required String body,
    required bool blocking,
    Uint8List? face,
    String? approve,
  }) async {
    await init();
    final s = Strings.current;
    try {
      await _plugin.show(
        id: notificationId(key),
        title: title,
        body: body,
        payload: approve == null ? key : '$key#$approve',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            s.notifyChannelName,
            channelDescription: s.notifyChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            styleInformation: BigTextStyleInformation(body),
            groupKey: _group,
            largeIcon: face == null ? null : ByteArrayAndroidBitmap(face),
            actions: approve == null
                ? null
                : [
                    // Both open the app: an answer is never sent from a
                    // locked phone without the app seeing it.
                    AndroidNotificationAction(
                      'deny',
                      s.deny,
                      showsUserInterface: true,
                      cancelNotification: true,
                    ),
                    AndroidNotificationAction(
                      'once',
                      s.allowOnce,
                      showsUserInterface: true,
                      cancelNotification: true,
                    ),
                  ],
          ),
          iOS: DarwinNotificationDetails(threadIdentifier: key),
          macOS: DarwinNotificationDetails(threadIdentifier: key),
        ),
      );
      await _summary();
    } catch (e) {
      debugPrint('notification failed: $e');
    }
  }

  /// The bundle's head on Android: present while any Hob notification is.
  Future<void> _summary() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final s = Strings.current;
    await _plugin.show(
      id: _summaryId,
      title: 'Hermes Hobs',
      body: null,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          s.notifyChannelName,
          channelDescription: s.notifyChannelDescription,
          groupKey: _group,
          setAsGroupSummary: true,
          onlyAlertOnce: true,
        ),
      ),
    );
  }

  @override
  Future<void> clear(String key) async {
    if (_init == null) return;
    try {
      await _plugin.cancel(id: notificationId(key));
      if (defaultTargetPlatform == TargetPlatform.android) {
        final left = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.getActiveNotifications();
        if (left != null && left.every((n) => n.id == _summaryId)) {
          await _plugin.cancel(id: _summaryId);
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> clearAll() async {
    if (_init == null) return;
    try {
      await _plugin.cancelAll();
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
