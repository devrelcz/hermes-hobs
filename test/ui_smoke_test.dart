import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/hob_avatar.dart';
import 'package:hobs/ui/format.dart';
import 'package:hobs/ui/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('login screen asks for a server, with no default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    expect(find.text('Hermes Hobs'), findsOneWidget);
    expect(find.text('https://hermes.devrel.cz'), findsNothing);
    await tester.tap(find.text('Zadat údaje ručně'));
    await tester.pump();
    await tester.tap(find.text('Přihlásit'));
    await tester.pump();
    expect(find.text('Povinné'), findsNWidgets(3));
  });

  testWidgets('password can be shown and hidden again', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.tap(find.text('Zadat údaje ručně'));
    await tester.pump();
    EditableText password() => tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Heslo'),
        matching: find.byType(EditableText),
      ),
    );
    expect(password().obscureText, isTrue);
    await tester.tap(find.byTooltip('Zobrazit heslo'));
    await tester.pump();
    expect(password().obscureText, isFalse);
    await tester.tap(find.byTooltip('Skrýt heslo'));
    await tester.pump();
    expect(password().obscureText, isTrue);
  });

  testWidgets('avatars render for every shape', (tester) async {
    const shapes = [
      'circle',
      'squircle',
      'pill',
      'triangle',
      'hexagon',
      'cloud',
      'drop',
      'blobatar:7:a',
      'weird',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: [
            for (final s in shapes)
              HobAvatar(
                hob: Hob(name: 'b$s', displayName: s, shape: s),
                working: s == 'pill',
              ),
          ],
        ),
      ),
    );
    expect(find.byType(HobAvatar), findsNWidgets(shapes.length));
    expect(
      HobAvatar.colorFor(Hob(name: 'x', displayName: 'x', color: '#F0997B')),
      const Color(0xFFF0997B),
    );
  });

  test('faces follow the dashboard formulas', () {
    // "a" hashes to 97: shape 97 % 7, hue 97.
    final a = HobAvatar.resolve(name: 'a');
    expect(a.shape, 'drop');
    expect(a.color, const HSLColor.fromAHSL(1, 97, .68, .58).toColor());
    // The hash wraps at 32 bits, like the dashboard's `>>> 0`.
    expect(HobAvatar.autoShape('financni-poradce'), 'hexagon');

    // The default profile keeps its fixed face until the user picks one.
    final fixed = HobAvatar.resolve(name: 'Default', shape: 'drop');
    expect((fixed.shape, fixed.color), ('squircle', const Color(0xFF8B5CF6)));
    expect(
      HobAvatar.resolve(name: 'default', shape: 'drop', custom: true).shape,
      'drop',
    );

    expect(
      HobAvatar.parseColor('hsl(30 68% 58%)'),
      const HSLColor.fromAHSL(1, 30, .68, .58).toColor(),
    );
    expect(HobAvatar.palette.length, 12);
    expect(HobAvatar.resolve(name: 'a', color: '#101010').lightEyes, isTrue);
    expect(HobAvatar.resolve(name: 'a', shape: 'hex').shape, 'hexagon');
    expect(HobAvatar.resolve(name: 'a', shape: 'weird').shape, 'drop');

    final blob = HobAvatar.resolve(name: 'a', shape: 'blobatar:k3x:sun');
    expect((blob.blobSeed, blob.blobKind), ('k3x', 'sun'));
    expect(HobAvatar.resolve(name: 'a', shape: 'blobatar').blobSeed, 'a');
    expect(HobAvatar.blobShape('', null), 'blobatar');
    expect(HobAvatar.blobShape('k3x', null), 'blobatar:k3x');
  });

  test('hob parsing edge cases used by the list UI', () {
    final b = Hob.fromJson({
      'name': 'research_bot',
      'display_name': '',
      'model': '',
    });
    expect(b.displayName, 'research_bot');
    expect(b.model, isNull);
    expect(b.initials, 'RB');
  });

  test('relative age and previews', () {
    final now = DateTime(2026, 11, 20, 16);
    expect(
      relativeAge(now.subtract(const Duration(seconds: 20)), now: now),
      'teď',
    );
    expect(
      relativeAge(now.subtract(const Duration(minutes: 56)), now: now),
      '56m',
    );
    expect(relativeAge(now.subtract(const Duration(hours: 2)), now: now), '2h');
    expect(relativeAge(now.subtract(const Duration(days: 3)), now: now), '3d');
    expect(dayTime(DateTime(2026, 11, 21, 9), now: now), 'zítra 09:00');
    expect(
      plainPreview('**Analytik** ověřil\n\n`zdroje`'),
      'Analytik ověřil zdroje',
    );
    // Links read as their text, even when the server cut the preview short.
    expect(
      plainPreview('V [archivu AI Weekly](https://aiweekly.devrel.cz/a) je'),
      'V archivu AI Weekly je',
    );
    expect(
      plainPreview('V [archivu AI Weekly](https://aiweekly.devrel.cz/…'),
      'V archivu AI Weekly',
    );
    expect(plainPreview('- jedna\n- dvě\n1. tři'), 'jedna dvě tři');
    expect(plainPreview('• Klikni až po ověření'), 'Klikni až po ověření');
  });
}
