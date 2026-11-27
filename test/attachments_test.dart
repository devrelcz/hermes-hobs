import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/attachments.dart';
import 'package:hobs/api/hermes_http.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/chat_controller.dart';
import 'package:hobs/state/composer_draft.dart';
import 'package:hobs/state/image_prep.dart';
import 'package:hobs/state/share_inbox.dart';
import 'package:hobs/ui/attachments_ui.dart';
import 'package:hobs/ui/chat_screen.dart';
import 'package:hobs/ui/hobs_screen.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_lock_test.dart' show FakeBiometrics;
import 'chat_flow_test.dart' show waitFor;
import 'fake_hermes_server.dart';

/// A tiny real PNG.
final Uint8List png = img.encodePng(img.Image(width: 4, height: 3));

/// Uploads exactly what was picked (no platform image codecs needed).
Future<PreparedImage> keepImage(Uint8List b, String name, String? mime) async =>
    PreparedImage(b, mime ?? 'image/png', name);

/// Shares the test hands to the app, as the share sheet would.
class FakeShareSource implements ShareSource {
  final _ctrl = StreamController<List<SharedItem>>.broadcast();
  List<SharedItem> launch = const [];
  int resets = 0;

  void share(List<SharedItem> items) => _ctrl.add(items);

  @override
  Stream<List<SharedItem>> get incoming => _ctrl.stream;

  @override
  Future<List<SharedItem>> initial() async => launch;

  @override
  void reset() => resets++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('references in the transcript', () {
    test('images after the caption, files and links before it', () {
      final img = parseAttachmentRefs(
        'Co je na fotce?\n@image:/srv/p/cache/images/cat.png',
      );
      expect(img.text, 'Co je na fotce?');
      expect(img.attachments.single.kind, AttachmentKind.image);
      expect(img.attachments.single.path, '/srv/p/cache/images/cat.png');
      expect(img.attachments.single.name, 'cat.png');

      final mixed = parseAttachmentRefs(
        '@file:`attachments/my report.pdf`\n@url:https://example.com/a?b=1\n\nShrň to',
      );
      expect(mixed.text, 'Shrň to');
      expect(mixed.attachments.map((a) => a.kind), [
        AttachmentKind.file,
        AttachmentKind.url,
      ]);
      expect(mixed.attachments.first.name, 'my report.pdf');
      expect(mixed.attachments.last.url, 'https://example.com/a?b=1');
    });

    test('an image-only turn shows no placeholder caption', () {
      final r = parseAttachmentRefs('$imageOnlyPrompt\n@image:/x/a.jpg');
      expect(r.text, isEmpty);
      expect(r.attachments, hasLength(1));
    });

    test('plain text and inline mentions stay text', () {
      const t = 'see @file:foo.txt here\nand more';
      final r = parseAttachmentRefs(t);
      expect(r.text, t);
      expect(r.attachments, isEmpty);
    });

    test('values with spaces are quoted like the server does', () {
      expect(formatRefValue('a/b.txt'), 'a/b.txt');
      expect(formatRefValue('my file.txt'), '`my file.txt`');
      expect(formatRefValue('a`b c'), '"a`b c"');
    });
  });

  test('large photos shrink to 2048 px JPEG, small ones stay', () async {
    final big = img.encodePng(img.Image(width: 3000, height: 1200));
    final p = await prepareImage(big, 'wide.png', 'image/png');
    expect(p.mime, 'image/jpeg');
    expect(p.name, 'wide.jpg');
    final decoded = img.decodeJpg(p.bytes)!;
    expect(decoded.width, 2048);
    expect(decoded.height, closeTo(819, 1));

    final small = await prepareImage(png, 'tiny.png', null);
    expect(small.bytes, same(png));
    expect(small.mime, 'image/png');
  });

  group('upload and send', () {
    late FakeHermesServer server;

    setUp(() async {
      server = FakeHermesServer();
      await server.start();
    });

    tearDown(() => server.stop());

    Future<HermesHttp> signedIn() async {
      final http = HermesHttp(baseUrl: server.baseUrl);
      await http.postJson('/auth/password-login', {
        'provider': 'basic',
        'username': 'u',
        'password': 'p',
      });
      return http;
    }

    Future<(HermesHttp, ChatController, ComposerDraft)> open() async {
      final http = await signedIn();
      final rpc = HermesRpc(http);
      await rpc.connect();
      final res =
          await rpc.request('profiles.list', {'include_sessions': true}) as Map;
      final cto = Hob.fromJson(
        (res['profiles'] as List).first as Map<String, dynamic>,
      );
      final chat = ChatController(rpc: rpc, hob: cto);
      await chat.start();
      final draft = ComposerDraft(
        AttachmentUploader(http, cto.name, prepare: keepImage),
      );
      return (http, chat, draft);
    }

    Map<String, dynamic> lastSubmit() =>
        server.calls.lastWhere((c) => c['method'] == 'prompt.submit')['params']
            as Map<String, dynamic>;

    test('canonical: images ride on prompt.submit, files via file.attach', () async {
      server.canonical = true;
      final (_, chat, draft) = await open();

      draft.addImage(png, 'cat.png', mime: 'image/png');
      draft.addFile(Uint8List.fromList('hello'.codeUnits), 'notes.txt');
      draft.addUrl('https://example.com/a');
      expect(draft.ready, isFalse);
      await waitFor(() => draft.ready);

      final image = server.uploads.firstWhere((u) => u['route'] == 'image');
      expect(image['profile'], 'cto');
      expect(image['bytes'], png);
      final file = server.uploads.firstWhere((u) => u['route'] == 'file');
      expect(file['name'], 'notes.txt');
      expect(file['bytes'], 'hello'.codeUnits);
      expect(file['contentType'], 'multipart/form-data');

      await chat.send('Co to je?', attachments: draft.take());
      await waitFor(() => chat.phase == ChatPhase.idle);
      expect(draft.isEmpty, isTrue);

      final attach = server.calls.firstWhere(
        (c) => c['method'] == 'file.attach',
      );
      expect(attach['params']['profile'], 'cto');
      expect(attach['params']['name'], 'notes.txt');
      expect(attach['params']['staged_upload'], {
        'install_id': 'i1',
        'path': '/srv/hermes/profiles/cto/uploads/u1_notes.txt',
        'profile_home': '/srv/hermes/profiles/cto',
      });

      final submit = lastSubmit();
      expect(
        submit['text'],
        '@file:attachments/notes.txt\n@url:https://example.com/a\n\nCo to je?',
      );
      expect(submit['attachments'], [
        {
          'path': '/srv/hermes/profiles/cto/cache/images/dashboard_1_cat.png',
          'mime': 'image/png',
        },
      ]);
      final sent = chat.messages.firstWhere(
        (m) => m.role == ChatRole.user && m.text == 'Co to je?',
      );
      expect(sent.attachments.map((a) => a.kind), [
        AttachmentKind.image,
        AttachmentKind.file,
        AttachmentKind.url,
      ]);
      expect(sent.attachments.first.preview, png);
      chat.dispose();
    });

    test('legacy: images are queued with image.attach first', () async {
      final (_, chat, draft) = await open();
      draft.addImage(png, 'cat.png', mime: 'image/png');
      await waitFor(() => draft.ready);
      await chat.send('', attachments: draft.take());
      await waitFor(() => chat.phase == ChatPhase.idle);

      final methods = server.calls.map((c) => c['method']).toList();
      final attachAt = methods.indexOf('image.attach');
      expect(attachAt, greaterThan(-1));
      expect(attachAt, lessThan(methods.lastIndexOf('prompt.submit')));
      final submit = lastSubmit();
      expect(submit['text'], imageOnlyPrompt);
      expect(submit.containsKey('attachments'), isFalse);
      chat.dispose();
    });

    test('an upload reports progress and can be cancelled', () async {
      final (_, chat, draft) = await open();
      server.holdUploads = Completer();
      draft.addImage(png, 'slow.png', mime: 'image/png');
      final a = draft.items.single;
      // The body is on the wire; the server has not answered yet.
      await waitFor(() => a.phase == UploadPhase.uploading && a.progress == 1);
      expect(draft.ready, isFalse);

      draft.remove(a);
      expect(draft.isEmpty, isTrue);
      expect(draft.ready, isTrue);
      server.holdUploads!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(draft.isEmpty, isTrue, reason: 'a cancelled upload stays gone');
      chat.dispose();
    });

    test('a failed upload shows its error and blocks sending', () async {
      final http = await signedIn();
      final draft = ComposerDraft(
        AttachmentUploader(http, 'cto', prepare: keepImage),
      );
      await server.stop();
      draft.addFile(Uint8List.fromList([1, 2, 3]), 'a.bin');
      await waitFor(() => draft.hasFailed);
      expect(draft.ready, isFalse);
      expect(
        draft.items.single.error,
        startsWith(Strings.current.uploadFailed('')),
      );

      draft.addFile(Uint8List(maxAttachmentBytes + 1), 'huge.bin');
      expect(draft.items.last.error, Strings.current.attachmentTooLarge(16));
      await server.start(); // tearDown stops it again
    });
  });

  group('screens', () {
    late FakeHermesServer server;

    setUp(() async {
      server = FakeHermesServer();
      await server.start();
      SharedPreferences.setMockInitialValues({
        'server_url': server.baseUrl.toString(),
        'username': 'u',
        'auto_login': true,
      });
      FlutterSecureStorage.setMockInitialValues({'password': 'p'});
    });

    tearDown(() => server.stop());

    Future<void> pumpUntil(WidgetTester tester, bool Function() cond) async {
      for (var i = 0; i < 300 && !cond(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(cond(), isTrue, reason: 'condition not met in time');
    }

    Widget wrap(AppState app, Widget home, {ShareInbox? inbox}) =>
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            if (inbox != null) ChangeNotifierProvider.value(value: inbox),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              Strings.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: Strings.supportedLocales,
            home: home,
          ),
        );

    Future<AppState> signIn(WidgetTester tester) async {
      final app = AppState(biometrics: FakeBiometrics());
      await tester.runAsync(app.init);
      await pumpUntil(
        tester,
        () =>
            app.hobs.isNotEmpty &&
            !app.loadingHobs &&
            app.connection == ConnectionStatus.connected,
      );
      return app;
    }

    testWidgets('chat history links have separate screen reader actions', (
      tester,
    ) async {
      const first = 'https://example.org/a%20b?next=%2Fdocs&lang=cs';
      const second = 'https://example.org/details';
      server.history = [
        {
          'role': 'assistant',
          'text': '[Guide]($first) and [Details]($second)',
          'timestamp': 1795186010,
        },
      ];
      final app = await signIn(tester);
      final cto = app.hobNamed('cto')!;
      final chat = (await tester.runAsync(() async => app.chatFor(cto)))!;
      final semantics = tester.ensureSemantics();
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = tester.binding.defaultBinaryMessenger;
      final opened = <String>[];
      messenger.setMockMethodCallHandler(launcher, (call) async {
        opened.add(call.arguments['url'] as String);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));

      try {
        await tester.pumpWidget(wrap(app, ChatScreen(hob: cto)));
        await pumpUntil(tester, () => chat.phase == ChatPhase.idle);
        await tester.pumpAndSettle();

        tester.semantics.tap(find.semantics.byLabel('Guide'));
        tester.semantics.tap(find.semantics.byLabel('Details'));
        await tester.pump();
        expect(opened, [first, second]);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async => app.dispose());
      }
    });

    testWidgets('history shows images, files and links of user messages', (
      tester,
    ) async {
      const shot = '/srv/hermes/profiles/cto/cache/images/cat.png';
      server.images[shot] = png;
      server.history = [
        {
          'role': 'user',
          'text': 'Co je na fotce?\n@image:$shot',
          'timestamp': 1795186000,
        },
        {'role': 'assistant', 'text': 'Kočka.', 'timestamp': 1795186010},
        {
          'role': 'user',
          'text': '@file:attachments/report.pdf\n@url:https://example.com/a\n\nShrň to',
          'timestamp': 1795186100,
        },
        {'role': 'assistant', 'text': 'Hotovo.', 'timestamp': 1795186110},
      ];
      final app = await signIn(tester);
      final cto = app.hobs.firstWhere((h) => h.name == 'cto');
      // Open the chat outside the fake clock: its requests time out on real
      // timers.
      final chat = (await tester.runAsync(() async => app.chatFor(cto)))!;
      // Same for the thumbnail read (the widget then uses the cached bytes).
      await tester.runAsync(
        () => RemoteImageCache.load(app.http!, shot, 'cto'),
      );
      expect(server.downloads, [shot]);
      await tester.pumpWidget(wrap(app, ChatScreen(hob: cto)));
      await pumpUntil(tester, () => chat.phase == ChatPhase.idle);
      await tester.pump();

      expect(find.text('Co je na fotce?'), findsOneWidget);
      expect(find.byType(MessageAttachments), findsNWidgets(2));
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('https://example.com/a'), findsOneWidget);
      // The bubble only: the question is on screen, so it is not pinned.
      expect(find.text('Shrň to'), findsOneWidget);
      expect(find.text('@file:attachments/report.pdf'), findsNothing);
      await pumpUntil(
        tester,
        () => find
            .descendant(
              of: find.byType(AttachmentImage),
              matching: find.byType(Image),
            )
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => app.dispose());
    });

    testWidgets(
      'a share waits for unlock, then lands in the picked Hob unsent',
      (tester) async {
        final app = await signIn(tester);
        final cto = app.hobs.firstWhere((h) => h.name == 'cto');
        final chat = (await tester.runAsync(() async => app.chatFor(cto)))!;
        await pumpUntil(tester, () => chat.phase == ChatPhase.idle);
        final source = FakeShareSource();
        final inbox = ShareInbox(source: source);
        await tester.runAsync(inbox.start);
        final dir = await tester.runAsync(
          () => Directory.systemTemp.createTemp('share'),
        );
        final photo = File('${dir!.path}/beach.png');
        await tester.runAsync(() => photo.writeAsBytes(png));

        app.locked = true;
        await tester.pumpWidget(wrap(app, const HobsScreen(), inbox: inbox));
        source.share([
          SharedItem(
            SharedKind.image,
            'file://${photo.path}',
            mime: 'image/png',
          ),
          const SharedItem(SharedKind.text, 'https://example.com/post'),
          const SharedItem(SharedKind.text, 'Podívej se na tohle'),
        ]);
        await pumpUntil(tester, () => inbox.pending != null);
        await tester.pump();
        expect(find.text('Send to a Hob'), findsNothing, reason: 'locked');

        await tester.runAsync(app.unlock);
        await tester.pumpAndSettle();
        expect(find.text('Send to a Hob'), findsOneWidget);
        expect(
          find.text('3 items go into the chat; you send them yourself.'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('share-to-cto')));
        await tester.pumpAndSettle();
        final draft = app.draftFor(cto);
        await pumpUntil(tester, () => draft.items.length == 2 && draft.ready);
        await tester.pump();

        expect(find.byType(ChatScreen), findsOneWidget);
        expect(inbox.pending, isNull);
        expect(source.resets, 1);
        expect(draft.items.map((a) => a.kind), [
          AttachmentKind.image,
          AttachmentKind.url,
        ]);
        expect(server.uploads.single['name'], 'beach.png');
        expect(find.byType(DraftStrip), findsOneWidget);
        final field = tester.widget<TextField>(
          find.descendant(
            of: find.byType(ChatScreen),
            matching: find.byType(TextField),
          ),
        );
        expect(field.controller!.text, 'Podívej se na tohle');
        expect(
          server.calls.where((c) => c['method'] == 'prompt.submit'),
          isEmpty,
          reason: 'a share is never sent by itself',
        );

        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          inbox.dispose();
          app.dispose();
          await dir.delete(recursive: true);
        });
      },
    );

    testWidgets('closing the picker drops the share', (tester) async {
      final app = await signIn(tester);
      final source = FakeShareSource()
        ..launch = const [SharedItem(SharedKind.url, 'https://example.com')];
      final inbox = ShareInbox(source: source);
      await tester.runAsync(inbox.start);
      await tester.pumpWidget(wrap(app, const HobsScreen(), inbox: inbox));
      await tester.pumpAndSettle();
      expect(find.text('Send to a Hob'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10)); // the scrim
      await tester.pumpAndSettle();
      expect(find.text('Send to a Hob'), findsNothing);
      expect(inbox.pending, isNull);
      expect(source.resets, 1);
      expect(find.byType(ChatScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        inbox.dispose();
        app.dispose();
      });
    });
  });
}
