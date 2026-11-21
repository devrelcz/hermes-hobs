import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device can reach the internet at all.
///
/// The radio state from the OS ([Connectivity]) answers "is any network on";
/// a DNS lookup of the server's host then answers "does that network actually
/// lead anywhere" (a hotel Wi-Fi behind a login page, mobile data with no
/// credit). DNS is used instead of calling the server so a server that is
/// down does not read as "you are offline": that case has its own banner
/// ([ConnectionStatus] in the chats).
///
/// Starts optimistic ([online] true) so the app never flashes an offline bar
/// while the first check runs.
class NetworkStatus extends ChangeNotifier {
  NetworkStatus({
    required this.host,
    this.onRestored,
    Stream<List<ConnectivityResult>>? radioChanges,
    Future<List<ConnectivityResult>> Function()? checkRadio,
    Future<bool> Function(String host)? probe,
  }) : _radioChanges = radioChanges ?? Connectivity().onConnectivityChanged,
       _checkRadio = checkRadio ?? Connectivity().checkConnectivity,
       _probe = probe ?? _dnsProbe;

  /// The server's host name; looked up to confirm the network works.
  final String Function() host;
  final Stream<List<ConnectivityResult>> _radioChanges;
  final Future<List<ConnectivityResult>> Function() _checkRadio;
  final Future<bool> Function(String host) _probe;

  /// Called once each time the device goes from offline back to online, so
  /// sockets and lists can reconnect right away instead of waiting out their
  /// backoff.
  final VoidCallback? onRestored;

  /// While a network is on but leads nowhere, look again after these delays
  /// (the last one repeats). Nothing polls while every radio is off: the OS
  /// tells us when one comes back.
  static const retryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
    Duration(seconds: 20),
  ];

  bool _online = true;
  bool _checking = false;
  bool _disposed = false;
  int _retry = 0;
  int _generation = 0;
  Timer? _retryTimer;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// False when there is no usable internet connection.
  bool get online => _online;
  bool get offline => !_online;

  /// A check the user asked for ([recheck]) is running.
  bool get checking => _checking;

  void start() {
    _sub ??= _radioChanges.listen(_onRadio, onError: (_) {});
    unawaited(recheck(quiet: true));
  }

  /// Looks again now: on start, when the app comes back to the foreground,
  /// and when the user taps "try again". [quiet] keeps the button as it is.
  Future<void> recheck({bool quiet = false}) async {
    if (!quiet) _setChecking(true);
    try {
      final List<ConnectivityResult> radio;
      try {
        radio = await _checkRadio();
      } catch (_) {
        // No plugin (tests, an unsupported platform): judge by DNS alone.
        await _verify();
        return;
      }
      await _onRadio(radio);
    } finally {
      if (!quiet) _setChecking(false);
    }
  }

  Future<void> _onRadio(List<ConnectivityResult> radio) async {
    if (_disposed) return;
    final noRadio =
        radio.isEmpty || radio.every((r) => r == ConnectivityResult.none);
    if (noRadio) {
      _generation++;
      _retryTimer?.cancel();
      _set(false);
      return;
    }
    await _verify();
  }

  /// A network is on: confirm it reaches the internet.
  Future<void> _verify() async {
    final generation = ++_generation;
    _retryTimer?.cancel();
    final ok = await _probe(host());
    // A newer event (radio off, another check) already decided.
    if (_disposed || generation != _generation) return;
    _set(ok);
    if (ok) {
      _retry = 0;
    } else {
      final delay = retryDelays[_retry.clamp(0, retryDelays.length - 1)];
      _retry++;
      _retryTimer = Timer(delay, () => unawaited(_verify()));
    }
  }

  void _set(bool online) {
    if (_online == online) return;
    _online = online;
    if (online) _retry = 0;
    notifyListeners();
    if (online) onRestored?.call();
  }

  void _setChecking(bool value) {
    if (_disposed || _checking == value) return;
    _checking = value;
    notifyListeners();
  }

  static Future<bool> _dnsProbe(String host) async {
    if (host.isEmpty || InternetAddress.tryParse(host) != null) {
      // An IP (a server on this machine or the LAN) needs no lookup; the
      // radio state is all we can say.
      return true;
    }
    try {
      final found = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      return found.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
