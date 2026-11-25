import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'state/app_state.dart';
import 'state/network_status.dart';
import 'state/pairing.dart';
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
  final appLinks = defaultTargetPlatform == TargetPlatform.android
      ? AppLinks().uriLinkStream
      : null;
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
      child: HobsApp(pairingLinks: appLinks),
    ),
  );
}

class HobsApp extends StatefulWidget {
  const HobsApp({super.key, this.pairingLinks});

  final Stream<Uri>? pairingLinks;

  @override
  State<HobsApp> createState() => _HobsAppState();
}

class _HobsAppState extends State<HobsApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final AppState _app;
  StreamSubscription<Uri>? _links;
  MobilePairingLink? _pendingPairing;
  bool _pairing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app = context.read<AppState>()..addListener(_schedulePairing);
    _links = widget.pairingLinks?.listen((uri) {
      final link = MobilePairingLink.tryParse(uri);
      if (link == null) return;
      _pendingPairing = link;
      _schedulePairing();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_schedulePairing);
    unawaited(_links?.cancel());
    super.dispose();
  }

  void _schedulePairing() {
    if (_pendingPairing == null || _pairing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPairing());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openPairing() async {
    final link = _pendingPairing;
    final nav = _navigator.currentState;
    if (!mounted ||
        link == null ||
        nav == null ||
        _app.locked ||
        _pairing ||
        _app.phase == AuthPhase.loading) {
      return;
    }
    final strings = Strings.current;
    _pendingPairing = null;
    _pairing = true;
    try {
      if (_app.phase == AuthPhase.signedIn) {
        final accepted = await showDialog<bool>(
          context: nav.context,
          builder: (context) => AlertDialog(
            title: Text(strings.mobilePairingTitle),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.signIn),
              ),
            ],
          ),
        );
        if (accepted != true || !mounted || _app.locked) return;
      }
      final code = await link.redeem();
      if (!mounted || _app.locked) return;
      await _app.login(
        serverUrl: code.serverUrl,
        username: code.username,
        password: code.password,
        rememberPassword: true,
      );
      // Existing nested screens belong to the previous account.
      _navigator.currentState?.popUntil((route) => route.isFirst);
    } catch (_) {
      _messenger.currentState?.showSnackBar(
        SnackBar(content: Text(Strings.current.mobilePairingUnavailable)),
      );
    } finally {
      _pairing = false;
      if (mounted) _schedulePairing();
    }
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
      title: 'HobCrew',
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
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
