import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'state/app_state.dart';
import 'state/network_status.dart';
import 'state/share_inbox.dart';
import 'ui/avatar_bitmap.dart';
import 'ui/hobs_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/offline_bar.dart';
import 'ui/login_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

void main() {
  // The bundled fonts' license, listed with the packages' in Settings.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Geist',
      'Geist Mono',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final binding = WidgetsFlutterBinding.ensureInitialized();
  Strings.current = Strings.forLocale(
    Strings.resolve(binding.platformDispatcher.locales),
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          // Notifications carry the Hob's face, drawn off screen.
          create: (_) => AppState()
            ..faceBitmap = AvatarBitmaps.of
            ..init(),
        ),
        // Shares from other apps wait here for the Hob list (see HobsScreen).
        ChangeNotifierProvider(create: (_) => ShareInbox()..start()),
        // No internet: a bar asks to turn it on (see OfflineGate). When it
        // comes back, reconnect right away instead of waiting out a backoff.
        ChangeNotifierProvider(
          create: (context) {
            final app = context.read<AppState>();
            return NetworkStatus(
              host: () => Uri.tryParse(app.serverUrl)?.host ?? '',
              onRestored: app.reconnect,
            )..start();
          },
        ),
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
    if (state == AppLifecycleState.resumed) {
      app.onAppResumed();
      // Network settings may have changed while the app was away.
      context.read<NetworkStatus>().recheck(quiet: true);
    }
    // On macOS a window behind other apps is "inactive" but still running:
    // the user isn't looking, so it should notify. On phones "inactive" is
    // a brief overlay (control center, app switcher) and doesn't count.
    if (state == AppLifecycleState.inactive &&
        defaultTargetPlatform == TargetPlatform.macOS) {
      app.setAppActive(false);
    }
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
      builder: (context, child) => OfflineGate(
        child: Stack(
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
      ),
      home: switch (phase) {
        AuthPhase.loading => const SplashScreen(),
        AuthPhase.signedOut => const LoginScreen(),
        AuthPhase.signedIn => const HobsScreen(),
      },
    );
  }
}
