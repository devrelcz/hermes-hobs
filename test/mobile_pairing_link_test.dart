import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/state/pairing.dart';

void main() {
  final token = List.filled(43, 'a').join();

  test('accepts the website pairing link and matching Android intent', () {
    expect(
      MobilePairingLink.tryParse(Uri.parse('https://hobcrew.com/pair#$token'))
          ?.token,
      token,
    );
    expect(
      MobilePairingLink.tryParse(Uri.parse('hobcrew://pair/$token'))?.token,
      token,
    );
  });

  test('rejects links outside the trusted origin and exact formats', () {
    for (final link in [
      'http://hobcrew.com/pair#$token',
      'https://hobcrew.com.evil.example/pair#$token',
      'https://hobcrew.com:8443/pair#$token',
      'https://other@hobcrew.com/pair#$token',
      'https://hobcrew.com/pair?token=$token',
      'https://hobcrew.com/other#$token',
      'https://hobcrew.com/pair#short',
      'hobcrew://pair/extra/$token',
      'hobcrew://other/$token',
    ]) {
      expect(MobilePairingLink.tryParse(Uri.parse(link)), isNull);
    }
  });
}
