import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/ui/message_links.dart';

void main() {
  const address = 'https://example.org/a%20b?next=%2Fdocs&lang=cs#intro';
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');

  test('only absolute HTTP and HTTPS destinations can open', () {
    expect(messageLinkUri(address).toString(), address);
    expect(messageLinkUri('HTTP://localhost:8080/path')?.host, 'localhost');
    for (final blocked in [
      null,
      '/relative',
      '//example.org',
      'https:///missing-host',
      'https://example.org@other.example',
      'javascript:alert(1)',
      'file:///etc/hosts',
      'intent://example.org',
    ]) {
      expect(messageLinkUri(blocked), isNull, reason: blocked);
    }
  });

  Future<void> tapSpan(WidgetTester tester, String label) async {
    final richText = find
        .byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().contains(label),
        )
        .first;
    final paragraph = tester.renderObject<RenderParagraph>(richText);
    final start = paragraph.text.toPlainText().indexOf(label);
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + label.length),
        )
        .first;
    await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
    await tester.pump();
  }

  testWidgets('prose delimiters stay outside web addresses', (tester) async {
    const url = 'https://example.org/cesta_';
    const query = 'https://example.org/a_(b)?filter[]=new&next=%2Fdocs';
    const ellipsisInPath = 'https://example.org/a…b_';
    final cases = [
      (source: '„$url“', label: url, target: url),
      (source: 'Viz $url“', label: url, target: url),
      (source: 'Viz $url…', label: url, target: url),
      (source: '„$url“…', label: url, target: url),
      (
        source: '$ellipsisInPath…',
        label: ellipsisInPath,
        target: 'https://example.org/a%E2%80%A6b_',
      ),
      (source: '[$url]', label: url, target: url),
      (source: '<$url>', label: url, target: url),
      (source: '($query).', label: query, target: Uri.parse(query).toString()),
      (source: '_${url}_', label: url, target: url),
      (source: '`curl $url`', label: url, target: null),
    ];

    final messenger = tester.binding.defaultBinaryMessenger;
    final opened = <String>[];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      expect(call.method, 'launch');
      opened.add(call.arguments['url'] as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));

    for (final item in cases) {
      for (final message in [
        MessageText(item.source),
        MessageMarkdown(data: item.source),
      ]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: message)));
        opened.clear();
        await tapSpan(tester, item.label);
        expect(
          opened,
          item.target == null ? isEmpty : [item.target],
          reason: '${message.runtimeType}: ${item.source}',
        );
        if (message is MessageText) {
          expect(find.text(item.source), findsOneWidget);
        }
      }
    }

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MessageMarkdown(data: '_Viz ${url}_')),
      ),
    );
    opened.clear();
    await tapSpan(tester, url);
    expect(opened, [url]);

    const target = 'https://example.net/other_';
    for (final data in [
      '[$url]($target)',
      '[$url][guide]\n\n[guide]: $target',
      '[$url]\n\n[$url]: $target',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessageMarkdown(data: data)),
        ),
      );
      opened.clear();
      await tapSpan(tester, url);
      expect(opened, [target], reason: data);
    }
  });

  testWidgets('plain messages and replies keep their own formatting', (
    tester,
  ) async {
    const source = '**Tučně** a _kurzíva_\nDalší řádek\n\n- položka';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MessageText(source))),
    );
    expect(find.text(source), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MessageMarkdown(data: source)),
      ),
    );
    expect(
      find.text('Tučně a kurzíva Další řádek', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('položka', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'chat links open on touch',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final opened = <String>[];
      messenger.setMockMethodCallHandler(launcher, (call) async {
        expect(call.method, 'launch');
        opened.add(call.arguments['url'] as String);
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(launcher, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: Column(
                children: [
                  const MessageMarkdown(
                    data:
                        '[Návod]($address)\n\n'
                        'Viz ($address).\n\n'
                        '<https://example.org/angle>\n\n'
                        '[Nebezpečný](file:///etc/hosts)\n\n'
                        '`https://example.org/code`',
                  ),
                  MessageText(
                    '@cto **text** https://example.net/a_(b), WWW.EXAMPLE.NET.',
                    plainSpan: (text) => TextSpan(text: text),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      for (final label in [
        'Návod',
        address,
        'https://example.org/angle',
        'https://example.net/a_(b)',
        'WWW.EXAMPLE.NET',
        'https://example.org/code',
        'Nebezpečný',
      ]) {
        await tapSpan(tester, label);
      }

      expect(opened, [
        address,
        address,
        'https://example.org/angle',
        'https://example.net/a_(b)',
        'http://www.example.net',
      ]);
      expect(find.textContaining('@cto **text**'), findsOneWidget);
      expect(find.text(Strings.current.linkOpenFailed), findsOneWidget);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
