import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'state/app_state.dart';
import 'state/share_inbox.dart';
import 'ui/hobs_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/login_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  Strings.current = Strings.forLocale(
    Strings.resolve(binding.platformDispatcher.locales),
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..init()),
        // Shares from other apps wait here for the Hob list (see HobsScreen).
        ChangeNotifierProvider(create: (_) => ShareInbox()..start()),
      ],
      child: const HobsApp(),
    ),
  );
}

class HobsApp extends StatefulWidget {
  const HobsApp({super.key});

  @override
  State<HobsApp> createState() => _HobsAppState();
}

class _HobsAppState extends State<HobsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<AppState>();
    if (state == AppLifecycleState.hidden) app.onAppHidden();
    if (state == AppLifecycleState.resumed) app.onAppResumed();
  }

  @override
  Widget build(BuildContext context) {
    final phase = context.select<AppState, AuthPhase>((s) => s.phase);
    final language = context.select<AppState, String?>((s) => s.languageCode);
    final locked = context.select<AppState, bool>(
      (s) => s.locked && s.phase == AuthPhase.signedIn,
    );
    return MaterialApp(
      title: 'Hermes Hobs',
      debugShowCheckedModeBanner: false,
      // No explicit locale: follow the device's preferred languages.
      locale: language == null ? null : Locale(language),
      supportedLocales: Strings.supportedLocales,
      localizationsDelegates: const [
        Strings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      localeListResolutionCallback: (locales, _) => Strings.resolve(locales),
      theme: HobsTheme.lightTheme(),
      darkTheme: HobsTheme.darkTheme(),
      // The lock sits above the navigator, so it also covers pushed routes
      // (an open chat, settings) and they are still there after unlocking.
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: locked,
            child: ExcludeSemantics(
              excluding: locked,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          if (locked) const LockScreen(),
        ],
      ),
      home: switch (phase) {
        AuthPhase.loading => const SplashScreen(),
        AuthPhase.signedOut => const LoginScreen(),
        AuthPhase.signedIn => const HobsScreen(),
      },
    );
  }
}
