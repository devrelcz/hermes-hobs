import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/ui/model_picker.dart';

const _codex = ModelChoice(provider: 'openai-codex', model: 'gpt-6.2-sol');

void main() {
  testWidgets('the profile picker searches models and offers inheriting', (
    tester,
  ) async {
    final providers = [
      ModelProvider(slug: 'nous', name: 'Nous', models: ['hermes-4']),
      ModelProvider(
        slug: 'openai-codex',
        name: 'Codex',
        models: ['gpt-6.2-sol', 'gpt-6.2-mini'],
      ),
    ];
    ModelChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: Strings.supportedLocales,
        localizationsDelegates: const [Strings.delegate],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await pickProfileModel(
                context,
                providers: providers,
                current: _codex,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('hermes-4'), findsOneWidget);
    expect(find.text('Inherit from the default profile'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'MINI');
    await tester.pumpAndSettle();
    expect(find.text('hermes-4'), findsNothing);
    expect(find.text('gpt-6.2-sol'), findsNothing);
    expect(find.text('Inherit from the default profile'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(find.text('No model matches the search.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mini');
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-6.2-mini'));
    await tester.pumpAndSettle();
    expect(
      picked,
      const ModelChoice(provider: 'openai-codex', model: 'gpt-6.2-mini'),
    );
  });
}
