import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/biometrics.dart';
import 'lock_screen.dart';
import 'sheets.dart';

/// App settings: the biometric lock (when the device has one),
/// notifications and the language (follow the device, or pin one of the language packs).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// A side sheet on wide screens, a tall bottom sheet on phones. Every
  /// switch saves at once, so it closes like any sheet.
  static Future<void> open(BuildContext context) => showScreenSheet<void>(
    context,
    kind: SheetKind.side,
    builder: (_) => const SettingsScreen(),
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final device = Strings.forLocale(
      Strings.resolve(View.of(context).platformDispatcher.locales),
    );
    return Scaffold(
      appBar: AppBar(
        leading: inSheet(context) ? const CloseButton() : null,
        title: Text(s.settings),
      ),
      body: ListView(
        children: [
          // Shown while it is on even without a biometric, so it can be
          // turned off after the face or finger was removed.
          if (app.biometricKind != null || app.biometricLock) ...[
            _Header(s.security),
            const _BiometricTile(),
          ],
          _Header(s.notifications),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: Text(s.notificationsSetting),
            subtitle: Text(
              app.notificationsEnabled && app.notificationsBlocked
                  ? s.notificationsBlocked
                  : s.notificationsHint,
            ),
            value: app.notificationsEnabled,
            onChanged: app.setNotificationsEnabled,
          ),
          _Header(s.language),
          _LanguageTile(
            title: s.languageSystem,
            subtitle: s.languageSystemNow(device.languageName),
            selected: app.languageCode == null,
            onTap: () => app.setLanguage(null),
          ),
          for (final locale in Strings.supportedLocales)
            _LanguageTile(
              // Each language is listed under its own name, so it can be
              // found by someone who cannot read the current one.
              title: Strings.forLocale(locale).languageName,
              selected: app.languageCode == locale.languageCode,
              onTap: () => app.setLanguage(locale.languageCode),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BiometricTile extends StatefulWidget {
  const _BiometricTile();

  @override
  State<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends State<_BiometricTile> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await app.setBiometricLock(value);
    } on BiometricException catch (e) {
      final message = describeBiometricFailure(e);
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final kind = app.biometricKind;
    return SwitchListTile(
      secondary: Icon(biometricIcon(kind)),
      title: Text(s.biometricSetting(kind ?? BiometricKind.generic)),
      subtitle: Text(s.biometricSettingHint),
      value: app.biometricLock,
      // Turning it on needs a working biometric; turning it off never does.
      onChanged: _busy || (kind == null && !app.biometricLock) ? null : _toggle,
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      selected: selected,
      trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
      onTap: onTap,
    );
  }
}
