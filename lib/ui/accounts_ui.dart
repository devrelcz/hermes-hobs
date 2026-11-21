import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/credentials_store.dart';
import 'sheets.dart';

Color accountColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return Color((v ?? 0x1D9E75) | 0xFF000000);
}

/// "dan · hermes.example.com": who and where, under the account's name.
String accountLine(ServerAccount a) =>
    a.username.isEmpty ? a.host : '${a.username} · ${a.host}';

/// Checks a server address typed into a form; null when it is fine.
String? validateServerUrl(String? value, Strings s) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return s.fieldRequired;
  final u = Uri.tryParse(text);
  if (u == null ||
      !(u.scheme == 'https' || u.scheme == 'http') ||
      u.host.isEmpty) {
    return s.serverInvalid;
  }
  return null;
}

/// An account's mark: its color with the first letter of its name.
class AccountBadge extends StatelessWidget {
  const AccountBadge({super.key, required this.account, this.size = 36});

  final ServerAccount account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = accountColor(account.color);
    final label = account.label;
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF14201A);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: label.isEmpty
            ? Icon(Icons.dns_outlined, size: size * 0.5, color: ink)
            : Text(
                label.characters.first.toUpperCase(),
                style: TextStyle(
                  color: ink,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
      ),
    );
  }
}

/// Flat filled fields, like the login form.
InputDecoration accountField(
  BuildContext context,
  String label,
  IconData icon, {
  Widget? suffix,
  String? hint,
  String? helper,
}) {
  final cs = Theme.of(context).colorScheme;
  final flat = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 2,
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
}

/// The colors an account can take, as a row of round swatches.
class AccountColorPicker extends StatelessWidget {
  const AccountColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (i, hex) in accountColors.indexed)
          Semantics(
            label: s.accountColorName(i),
            selected: hex == value,
            inMutuallyExclusiveGroup: true,
            button: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onChanged(hex),
              child: Padding(
                // 48 points to tap, the swatch itself smaller.
                padding: const EdgeInsets.all(6),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accountColor(hex),
                    shape: BoxShape.circle,
                    border: hex == value
                        ? Border.all(color: cs.onSurface, width: 2.5)
                        : null,
                  ),
                  child: hex == value
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The error under a form, read out when it appears.
class FormErrorBox extends StatelessWidget {
  const FormErrorBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: cs.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A password field with a show/hide eye.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return TextFormField(
      controller: widget.controller,
      decoration: accountField(
        context,
        widget.label,
        Icons.lock_outline,
        helper: widget.helper,
        suffix: IconButton(
          icon: Icon(
            _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
          tooltip: _show ? s.hidePassword : s.showPassword,
          onPressed: () => setState(() => _show = !_show),
        ),
      ),
      obscureText: !_show,
      autofillHints: const [AutofillHints.password],
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
    );
  }
}

/// Adds a Hermes server under a name and color, signs in to it and
/// switches there. Nothing is saved until the sign-in works.
class AddServerScreen extends StatefulWidget {
  const AddServerScreen({super.key});

  /// A full-screen sheet on phones, a large dialog on wide windows. True
  /// when the new account signed in.
  static Future<bool?> open(BuildContext context) => showScreenSheet<bool>(
    context,
    kind: SheetKind.fullscreen,
    guarded: true,
    builder: (_) => const AddServerScreen(),
  );

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _server = TextEditingController(text: 'https://');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  late String _color = context.read<AppState>().nextAccountColor();
  bool _remember = true;
  bool _busy = false;
  String? Function()? _error;

  bool get _dirty =>
      _name.text.isNotEmpty ||
      _user.text.isNotEmpty ||
      _pass.text.isNotEmpty ||
      _server.text.trim() != 'https://';

  @override
  void dispose() {
    _name.dispose();
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    try {
      await app.addAccount(
        name: _name.text.trim(),
        color: _color,
        serverUrl: _server.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
        rememberPassword: _remember,
      );
      if (mounted) nav.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = () => AppState.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askDiscard() async {
    final s = Strings.of(context);
    final nav = Navigator.of(context);
    final ok = await showConfirmSheet(
      context,
      title: s.discardChangesTitle,
      confirmLabel: s.discardChanges,
      cancelLabel: s.keepEditing,
      destructive: true,
    );
    if (ok && mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final error = _error?.call();
    final preview = ServerAccount(
      id: '',
      name: _name.text,
      color: _color,
      serverUrl: _server.text.trim(),
      username: _user.text.trim(),
    );
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _askDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: inSheet(context) ? const CloseButton() : null,
          title: Text(s.addServer),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _form,
              onChanged: () => setState(() {}),
              child: AutofillGroup(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Center(child: AccountBadge(account: preview, size: 72)),
                    const SizedBox(height: 8),
                    Text(
                      preview.label.isEmpty ? s.addServer : preview.label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      decoration: accountField(
                        context,
                        s.accountName,
                        Icons.label_outline,
                        hint: s.accountNameHint,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.accountColor,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AccountColorPicker(
                      value: _color,
                      onChanged: (c) => setState(() => _color = c),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _server,
                      decoration: accountField(
                        context,
                        s.serverLabel,
                        Icons.dns_outlined,
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: (v) => validateServerUrl(v, s),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _user,
                      decoration: accountField(
                        context,
                        s.usernameLabel,
                        Icons.person_outline,
                      ),
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? s.fieldRequired : null,
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      controller: _pass,
                      label: s.passwordLabel,
                      onSubmitted: (_) => _submit(),
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
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(s.signInAndSwitch),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.addServerHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

/// Settings > Accounts: every saved server, in the user's order, to rename,
/// recolor, give a new password or remove.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  static Future<void> open(BuildContext context) => showScreenSheet<void>(
    context,
    kind: SheetKind.side,
    builder: (_) => const AccountsScreen(),
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts = app.accounts;
    return Scaffold(
      appBar: AppBar(
        leading: inSheet(context) ? const CloseButton() : null,
        title: Text(s.accounts),
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        buildDefaultDragHandles: false,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(
            s.accountsHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        footer: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => AddServerScreen.open(context),
            icon: const Icon(Icons.add),
            label: Text(s.addServer),
          ),
        ),
        itemCount: accounts.length,
        onReorderItem: app.reorderAccounts,
        itemBuilder: (context, i) {
          final a = accounts[i];
          final active = a.id == app.activeId;
          return Padding(
            key: ValueKey('account-${a.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 14, right: 4),
                leading: AccountBadge(account: a),
                title: Text(a.label, overflow: TextOverflow.ellipsis),
                subtitle: Text(accountLine(a), overflow: TextOverflow.ellipsis),
                onTap: () => EditAccountScreen.open(context, a.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (active)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          s.accountActive,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (accounts.length > 1)
                      ReorderableDragStartListener(
                        index: i,
                        child: Tooltip(
                          message: s.dragToReorder,
                          child: const SizedBox.square(
                            dimension: 48,
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One account's name, color and password, and the way to remove it.
class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key, required this.id});

  final String id;

  static Future<void> open(BuildContext context, String id) =>
      showScreenSheet<void>(
        context,
        kind: SheetKind.side,
        builder: (_) => EditAccountScreen(id: id),
      );

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final _form = GlobalKey<FormState>();
  late final ServerAccount _initial = context.read<AppState>().accountById(
    widget.id,
  )!;
  late final _name = TextEditingController(text: _initial.name);
  final _pass = TextEditingController();
  late String _color = _initial.color;
  bool _busy = false;
  String? Function()? _error;

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final app = context.read<AppState>();
    final s = Strings.of(context);
    final nav = Navigator.of(context);
    final root = Navigator.of(context, rootNavigator: true).context;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pass.text.isNotEmpty) {
        await app.setAccountPassword(widget.id, _pass.text);
      }
      await app.updateAccount(
        widget.id,
        name: _name.text.trim(),
        color: _color,
      );
      if (!mounted) return;
      nav.pop();
      if (root.mounted) showToast(root, s.accountSaved);
    } catch (e) {
      if (mounted) setState(() => _error = () => AppState.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final app = context.read<AppState>();
    final s = Strings.of(context);
    final nav = Navigator.of(context);
    final account = app.accountById(widget.id);
    if (account == null) return;
    final ok = await showConfirmSheet(
      context,
      title: s.removeAccountTitle(account.label),
      message: s.removeAccountBody,
      confirmLabel: s.remove,
      cancelLabel: s.cancel,
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    final wasActive = account.id == app.activeId;
    // The active account leaves the screen under the sheets: close them all.
    if (wasActive) {
      nav.popUntil((r) => r.isFirst);
    } else {
      nav.pop();
    }
    await app.removeAccount(account.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final account = context.select<AppState, ServerAccount?>(
      (a) => a.accountById(widget.id),
    );
    if (account == null) return const SizedBox.shrink();
    final error = _error?.call();
    final preview = account.copyWith(name: _name.text, color: _color);
    return Scaffold(
      appBar: AppBar(
        leading: inSheet(context) ? const CloseButton() : null,
        title: Text(s.editAccount),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(s.save),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(child: AccountBadge(account: preview, size: 64)),
            const SizedBox(height: 8),
            Text(
              preview.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              accountLine(account),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              decoration: accountField(
                context,
                s.accountName,
                Icons.label_outline,
                hint: account.host,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            Text(
              s.accountColor,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            AccountColorPicker(
              value: _color,
              onChanged: (c) => setState(() => _color = c),
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _pass,
              label: s.newPassword,
              helper: s.newPasswordHint,
              onSubmitted: (_) => _save(),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              FormErrorBox(error),
            ],
            const SizedBox(height: 32),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_outline),
              label: Text(s.removeAccount),
            ),
          ],
        ),
      ),
    );
  }
}
