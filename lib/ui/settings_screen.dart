import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/biometrics.dart';
import 'accounts_ui.dart';
import 'format.dart';
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _Group(
            title: s.accounts,
            children: [
              if (app.activeAccount case final active?)
                ListTile(
                  leading: AccountBadge(account: active),
                  title: Text(active.label, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    accountLine(active),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: Text(s.manageAccounts),
                trailing: Text(
                  '${app.accounts.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                onTap: () => AccountsScreen.open(context),
              ),
            ],
          ),
          // Shown while it is on even without a biometric, so it can be
          // turned off after the face or finger was removed.
          if (app.biometricKind != null || app.biometricLock)
            _Group(title: s.security, children: const [_BiometricTile()]),
          _Group(
            title: s.notifications,
            children: [
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
            ],
          ),
          _Group(
            title: s.language,
            children: [
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
          _Group(
            title: s.about,
            children: [_About(app: app)],
          ),
        ],
      ),
    );
  }
}

/// One part of the settings: a title over a soft card of rows.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title),
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// The commit and time a build was made from, set by
/// tool/install_android.sh; empty for a plain `flutter run`.
const _gitSha = String.fromEnvironment('GIT_SHA');
const _buildTime = String.fromEnvironment('BUILD_TIME');

/// The app's version, where it is signed in, and the licenses.
class _About extends StatelessWidget {
  const _About({required this.app});

  final AppState app;

  /// "a1b2c3d · 21. 11. 18:47", or null when the build carries neither.
  static String? _buildLine() {
    final when = DateTime.tryParse(_buildTime);
    final parts = [
      if (_gitSha.isNotEmpty) _gitSha,
      if (when != null) dayTime(when),
    ];
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final host = Uri.tryParse(app.serverUrl)?.host ?? '';
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final info = snap.data;
        final version = info == null
            ? ''
            : info.buildNumber.isEmpty
            ? info.version
            : '${info.version} (${info.buildNumber})';
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(s.appVersion),
              subtitle: _buildLine() == null ? null : Text(_buildLine()!),
              trailing: Text(version),
            ),
            if (host.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(s.serverLabel),
                subtitle: Text(host),
              ),
            if (app.username.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(s.signedInAs),
                subtitle: Text(app.username),
              ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(s.licenses),
              subtitle: Text(s.licensesHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Hermes Hobs',
                applicationVersion: version,
              ),
            ),
          ],
        );
      },
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
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
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
