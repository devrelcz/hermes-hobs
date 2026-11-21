// Local stand-in for a Hermes dashboard with demo data, for screenshots.
// The app's demo mode serves the same data (lib/demo/demo_hermes.dart).
//
//   dart run tool/demo_server.dart [port]
//
// Then sign in to http://127.0.0.1:<port> (default 8765) as `u` / `p`.
import 'dart:io';

import 'package:hobs/demo/demo_hermes.dart';
import 'package:hobs/demo/fake_hermes_server.dart';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8765 : int.parse(args.first);
  final server = seedDemo(FakeHermesServer());
  await server.start(port: port);
  stdout.writeln('Demo Hermes on ${server.baseUrl} (sign in as u / p)');
}
