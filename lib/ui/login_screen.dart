import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/biometrics.dart';
import '../state/credentials_store.dart';
import '../state/pairing.dart';
import 'accounts_ui.dart';
import 'lock_screen.dart';
import 'pair_scan_screen.dart';
import 'splash_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.scanPairingCode});

  /// Reads a server's pairing QR code; null when the user backs out. The
  /// camera scanner unless a test supplies its own.
  final Future<PairingCode?> Function(BuildContext context)? scanPairingCode;

  /// The scanner is offered where the device has a camera to point at a
  /// screen: on phones and tablets.
  static bool get canScan => PairScanScreen.canScan;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _remember = true;
  bool _showPassword = false;

  /// The saved accounts are offered first; the form opens for one that
  /// cannot sign in on its own, or for another server.
  bool _picking = false;

  /// Where a camera can read the server's pairing code, a new server starts
  /// with the choice between scanning it and typing the details; the form
  /// opens for the second.
  bool _choosing = false;

  bool get _canScan => widget.scanPairingCode != null || LoginScreen.canScan;

  /// The account being signed in from the list.
  String? _opening;

  /// Built at paint time, so a language switch re-words it.
  String? Function()? _error;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _fillFrom(app);
    if (app.authError != null) _error = () => app.authError;
    // A failed sign-in says why next to the form it came from.
    _picking = app.accounts.isNotEmpty && app.authError == null;
    _choosing = !_picking && app.authError == null && _canScan;
  }

  void _fillFrom(AppState app) {
    _server.text = app.serverUrl;
    _user.text = app.username;
    // With the biometric lock on, the remembered password is reached only
    // through the biometric, never by just pressing Sign in.
    _pass.text = app.biometricLock ? '' : app.savedPassword ?? '';
  }

  /// Signs a saved account in with what it keeps: its session, its
  /// password (behind the biometric when the lock is on). Opens the form
  /// for it when that is not enough.
  Future<void> _openAccount(ServerAccount account) async {
    final app = context.read<AppState>();
    setState(() {
      _opening = account.id;
      _error = null;
    });
    try {
      if (app.biometricLock) {
        await app.selectAccount(account.id);
        if (app.canBiometricSignIn) {
          await app.biometricSignIn();
          return;
        }
      } else {
        await app.switchAccount(account.id, showLoading: false);
        if (app.phase == AuthPhase.signedIn) return;
      }
      if (!mounted) return;
      _fillFrom(app);
      setState(() {
        _picking = false;
        if (app.authError != null) _error = () => app.authError;
      });
    } on BiometricException catch (e) {
      // The form for this account, where the password is the other way in.
      if (!mounted) return;
      _fillFrom(app);
      setState(() {
        _picking = false;
        _error = () => describeBiometricFailure(e);
      });
    } catch (e) {
      if (mounted) setState(() => _error = () => AppState.describeError(e));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  void _otherServer() {
    setState(() {
      _picking = false;
      _choosing = _canScan;
      _error = null;
      _server.text = 'https://';
      _user.clear();
      _pass.clear();
    });
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login(
        serverUrl: _server.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
        rememberPassword: _remember,
      );
    } catch (e) {
      if (mounted) setState(() => _error = () => AppState.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Scans the server's pairing code and signs in with what it carries.
  Future<void> _scan() async {
    final scan = widget.scanPairingCode ?? PairScanScreen.open;
    final code = await scan(context);
    if (code == null || !mounted) return;
    // The filled form, so a refused sign-in says why next to what the code
    // carried.
    setState(() {
      _choosing = false;
      _server.text = code.serverUrl;
      _user.text = code.username;
      _pass.text = code.password;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _submit();
  }

  Future<void> _tryDemo() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().tryDemo();
    } catch (e) {
      if (mounted) setState(() => _error = () => AppState.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _biometricSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().biometricSignIn();
    } on BiometricException catch (e) {
      if (mounted) setState(() => _error = () => describeBiometricFailure(e));
    } catch (e) {
      if (mounted) setState(() => _error = () => AppState.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _picker(BuildContext context, AppState app) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final error = _error?.call();
    final biometric = app.biometricLock ? app.biometricKind : null;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Semantics(
          header: true,
          child: Text(
            s.savedAccounts,
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      for (final a in app.accounts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
              enabled: _opening == null,
              leading: AccountBadge(account: a, size: 40),
              title: Text(a.label, overflow: TextOverflow.ellipsis),
              subtitle: Text(accountLine(a), overflow: TextOverflow.ellipsis),
              trailing: _opening == a.id
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      biometric != null
                          ? biometricIcon(biometric)
                          : Icons.chevron_right,
                      color: cs.onSurfaceVariant,
                    ),
              onTap: () => _openAccount(a),
            ),
          ),
        ),
      if (error != null) ...[
        const SizedBox(height: 4),
        FormErrorBox(error),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _opening == null ? _otherServer : null,
        icon: const Icon(Icons.add),
        label: Text(s.otherServer),
      ),
    ];
  }

  /// A new server: scan its pairing code, or type the details.
  List<Widget> _chooser(BuildContext context, AppState app) {
    final s = Strings.of(context);
    final error = _error?.call();
    return [
      if (app.accounts.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _choosing = false;
                    _picking = true;
                    _error = null;
                  }),
            icon: const Icon(Icons.arrow_back),
            label: Text(s.savedAccounts),
          ),
        ),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _busy ? null : _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(s.scanQr),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _busy
            ? null
            : () => setState(() {
                _choosing = false;
                _error = null;
              }),
        icon: const Icon(Icons.keyboard_outlined),
        label: Text(s.enterManually),
      ),
      if (error != null) ...[const SizedBox(height: 12), FormErrorBox(error)],
      const SizedBox(height: 24),
      _demoButton(s),
    ];
  }

  /// No server yet (or reviewing the app): the demo server built into the
  /// app.
  Widget _demoButton(Strings s) => TextButton.icon(
    onPressed: _busy ? null : _tryDemo,
    icon: const Icon(Icons.play_circle_outline),
    label: Text(s.tryDemo),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final app = context.watch<AppState>();
    final biometric = app.canBiometricSignIn ? app.biometricKind : null;
    final error = _error?.call();
    final cs = theme.colorScheme;
    // Flat fields like the search above the Hob list: filled, outlined
    // only while focused.
    final flat = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    InputDecoration field(String label, IconData icon, {Widget? suffix}) =>
        InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: cs.onSurfaceVariant),
          suffixIcon: suffix,
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          border: flat,
          enabledBorder: flat,
          focusedBorder: flat.copyWith(
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
          errorBorder: flat.copyWith(borderSide: BorderSide(color: cs.error)),
          focusedErrorBorder: flat.copyWith(
            borderSide: BorderSide(color: cs.error, width: 1.5),
          ),
        );
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The app's mark as on the home screen: the hob on moss.
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: SplashScreen.moss,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: SplashScreen.moss.withValues(alpha: 0.25),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const HobGlyph(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'HobCrew',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_picking)
                      ..._picker(context, app)
                    else if (_choosing)
                      ..._chooser(context, app)
                    else ...[
                      // Back to the choice of scanning, or to the saved
                      // accounts where there is no scanner.
                      if (_canScan || app.accounts.isNotEmpty)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    if (_canScan) {
                                      _choosing = true;
                                    } else {
                                      _picking = true;
                                    }
                                    _error = null;
                                  }),
                            icon: const Icon(Icons.arrow_back),
                            label: Text(_canScan ? s.back : s.savedAccounts),
                          ),
                        ),
                      TextFormField(
                        controller: _server,
                        decoration: field(s.serverLabel, Icons.dns_outlined),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        validator: (v) => validateServerUrl(v, s),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _user,
                        decoration: field(
                          s.usernameLabel,
                          Icons.person_outline,
                        ),
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? s.fieldRequired : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pass,
                        decoration: field(
                          s.passwordLabel,
                          Icons.lock_outline,
                          suffix: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            tooltip: _showPassword
                                ? s.hidePassword
                                : s.showPassword,
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        obscureText: !_showPassword,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) =>
                            (v ?? '').isEmpty ? s.fieldRequired : null,
                      ),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        value: _remember,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _remember = v ?? true),
                        title: Text(s.rememberPassword),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        FormErrorBox(error),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(s.signIn),
                      ),
                      if (biometric != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _busy ? null : _biometricSignIn,
                          icon: Icon(biometricIcon(biometric)),
                          label: Text(s.signInWith(biometric)),
                        ),
                      ],
                      // With a scanner the demo is offered on the choice
                      // before the form.
                      if (!_canScan) ...[
                        const SizedBox(height: 24),
                        _demoButton(s),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
