import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/biometrics.dart';
import 'lock_screen.dart';
import 'splash_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

  /// Built at paint time, so a language switch re-words it.
  String? Function()? _error;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _server.text = app.serverUrl;
    _user.text = app.username;
    // With the biometric lock on, the remembered password is reached only
    // through the biometric, never by just pressing Sign in.
    if (!app.biometricLock) _pass.text = app.savedPassword ?? '';
    if (app.authError != null) _error = () => app.authError;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final app = context.watch<AppState>();
    final biometric = app.canBiometricSignIn ? app.biometricKind : null;
    final error = _error?.call();
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
                    const Center(
                      child: CustomPaint(
                        size: Size.square(88),
                        painter: HobGlyphPainter(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hermes Hobs',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _server,
                      decoration: InputDecoration(
                        labelText: s.serverLabel,
                        prefixIcon: const Icon(Icons.dns_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return s.fieldRequired;
                        final u = Uri.tryParse(text);
                        if (u == null ||
                            !(u.scheme == 'https' || u.scheme == 'http') ||
                            u.host.isEmpty) {
                          return s.serverInvalid;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _user,
                      decoration: InputDecoration(
                        labelText: s.usernameLabel,
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? s.fieldRequired : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      decoration: InputDecoration(
                        labelText: s.passwordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
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
                      const SizedBox(height: 16),
                      Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(s.signIn),
                    ),
                    if (biometric != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _biometricSignIn,
                        icon: Icon(biometricIcon(biometric)),
                        label: Text(s.signInWith(biometric)),
                      ),
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
