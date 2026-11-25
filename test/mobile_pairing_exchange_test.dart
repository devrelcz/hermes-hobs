import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/state/pairing.dart';

void main() {
  // Run with --dart-define=HOBCREW_PAIRING_ORIGIN=http://127.0.0.1:38192.
  const configured = String.fromEnvironment('HOBCREW_PAIRING_ORIGIN');
  const fixture = 'http://127.0.0.1:38192';
  test(
    'exchanges the code and refuses reused codes and foreign crew addresses',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 38192);
      addTearDown(() => server.close(force: true));
      final requests = <(String, String, String?, String)>[];
      final token = List.filled(43, 'a').join();
      var count = 0;

      server.listen((request) async {
        final body = (jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map)['token'];
        requests.add((
          request.method,
          request.uri.path,
          request.headers.value('origin'),
          body as String,
        ));
        final response = request.response;
        response.headers.contentType = ContentType.json;
        count++;
        if (count == 2) {
          response.statusCode = 410;
          response.write(jsonEncode({'error': 'pairing_expired'}));
        } else {
          response.write(
            jsonEncode({
              'v': 1,
              'url': count == 1
                  ? 'https://example.apps.hobcrew.com'
                  : 'https://foreign.example',
              'user': 'admin',
              'password': 'test-only',
            }),
          );
        }
        await response.close();
      });

      final link = MobilePairingLink.tryParse(
        Uri.parse('$fixture/pair#$token'),
      )!;
      expect(
        (await link.redeem()).serverUrl,
        'https://example.apps.hobcrew.com',
      );
      final unavailable = isA<PairingException>().having(
        (error) => error.failure,
        'failure',
        PairingFailure.unavailable,
      );
      await expectLater(link.redeem(), throwsA(unavailable));
      await expectLater(link.redeem(), throwsA(unavailable));
      expect(
        requests,
        List.filled(3, ('POST', '/api/mobile-pairing/redeem', fixture, token)),
      );
    },
    skip: configured != fixture ? 'Requires the local pairing origin' : false,
  );
}
