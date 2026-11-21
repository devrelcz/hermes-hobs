import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/state/network_status.dart';
import 'package:hobs/ui/offline_bar.dart';
import 'package:provider/provider.dart';

/// A [NetworkStatus] driven by hand: [radio] is what the OS reports, [reach]
/// whether the DNS probe succeeds.
class _Net {
  _Net({this.radio = const [ConnectivityResult.wifi]}) {
    status = NetworkStatus(
      host: () => 'hermes.example',
      onRestored: () => restored++,
      radioChanges: _radio.stream,
      checkRadio: () async => radio,
      probe: (host) async {
        probes++;
        return reach;
      },
    );
  }

  final _radio = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> radio;
  bool reach = true;
  int probes = 0;
  int restored = 0;
  late final NetworkStatus status;

  void emit(List<ConnectivityResult> r) {
    radio = r;
    _radio.add(r);
  }
}

const _none = [ConnectivityResult.none];
const _wifi = [ConnectivityResult.wifi];

void main() {
  test('radio off reads as offline without probing', () async {
    final net = _Net(radio: _none)..status.start();
    await pumpEventQueue();
    expect(net.status.offline, isTrue);
    expect(net.probes, 0);
  });

  test('a network that leads nowhere reads as offline', () async {
    final net = _Net()..reach = false;
    net.status.start();
    await pumpEventQueue();
    expect(net.status.offline, isTrue);
    net.status.dispose();
  });

  test('coming back online calls onRestored once', () async {
    final net = _Net(radio: _none)..status.start();
    await pumpEventQueue();
    expect(net.status.offline, isTrue);

    net.emit(_wifi);
    await pumpEventQueue();
    expect(net.status.online, isTrue);
    expect(net.restored, 1);

    // Another "still on" event changes nothing.
    net.emit(const [ConnectivityResult.wifi, ConnectivityResult.mobile]);
    await pumpEventQueue();
    expect(net.restored, 1);
  });

  test('radio off wins over a slower probe', () async {
    final probe = Completer<bool>();
    final radio = StreamController<List<ConnectivityResult>>();
    final status = NetworkStatus(
      host: () => 'hermes.example',
      radioChanges: radio.stream,
      checkRadio: () async => _wifi,
      probe: (_) => probe.future,
    )..start();
    await pumpEventQueue();
    radio.add(_none);
    await pumpEventQueue();
    probe.complete(true);
    await pumpEventQueue();
    expect(status.offline, isTrue);
  });

  testWidgets('keeps probing while the network leads nowhere', (tester) async {
    final net = _Net()..reach = false;
    net.status.start();
    await tester.pump();
    expect(net.status.offline, isTrue);
    final before = net.probes;

    net.reach = true;
    await tester.pump(NetworkStatus.retryDelays.first);
    expect(net.probes, before + 1);
    expect(net.status.online, isTrue);
    expect(net.restored, 1);
    net.status.dispose();
  });

  testWidgets('offline bar asks to turn on the internet and retries', (
    tester,
  ) async {
    final net = _Net(radio: _none);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: net.status,
        child: MaterialApp(
          builder: (context, child) => OfflineGate(child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    expect(find.text('Nejste připojeni k internetu'), findsNothing);

    net.status.start();
    await tester.pumpAndSettle();
    expect(find.text('Nejste připojeni k internetu'), findsOneWidget);
    expect(find.text('Zapněte Wi-Fi nebo mobilní data.'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);

    net.radio = _wifi;
    await tester.tap(find.text('Zkusit znovu'));
    await tester.pumpAndSettle();
    expect(find.text('Nejste připojeni k internetu'), findsNothing);
    expect(net.restored, 1);
  });
}
