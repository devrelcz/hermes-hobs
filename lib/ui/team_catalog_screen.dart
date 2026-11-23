import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../api/team_catalog.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/team_import.dart';
import 'hob_avatar.dart';
import 'placeholders.dart';
import 'sheets.dart';

/// The corner radius of every large surface on these pages: cards, covers,
/// notes. Thumbnails and blocks inside them use 12.
const _radius = 18.0;

/// The marketplace of ready-made teams: the catalog, a team's members with
/// their instructions and jobs, then the import step by step. A full-screen
/// sheet on phones, a large dialog on wide screens.
class TeamCatalogScreen extends StatefulWidget {
  const TeamCatalogScreen({super.key});

  /// Opens the catalog. Returns the finished import, or null when the user
  /// backed out.
  static Future<TeamImport?> open(BuildContext context) =>
      showScreenSheet<TeamImport>(
        context,
        kind: SheetKind.fullscreen,
        guarded: true,
        builder: (_) => const TeamCatalogScreen(),
      );

  @override
  State<TeamCatalogScreen> createState() => _TeamCatalogScreenState();
}

class _TeamCatalogScreenState extends State<TeamCatalogScreen> {
  List<TeamCard>? _cards;
  String? _cardsError;

  TeamCard? _card;
  TeamPlan? _plan;
  String? _teamError;

  TeamImport? _import;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _import?.dispose();
    super.dispose();
  }

  String get _lang => Strings.current.code;

  Future<void> _loadCards() async {
    setState(() {
      _cards = null;
      _cardsError = null;
    });
    try {
      final cards = await context.read<AppState>().teamCatalog.fetchIndex();
      if (mounted) setState(() => _cards = cards);
    } catch (e) {
      if (mounted) setState(() => _cardsError = AppState.describeError(e));
    }
  }

  Future<void> _openCard(TeamCard card) async {
    final app = context.read<AppState>();
    setState(() {
      _card = card;
      _plan = null;
      _teamError = null;
    });
    try {
      final team = await app.teamCatalog.fetchTeam(card, _lang);
      final plan = await TeamPlan.make(app, team, lang: _lang);
      if (mounted && _card == card) setState(() => _plan = plan);
    } catch (e) {
      if (mounted && _card == card) {
        setState(() => _teamError = AppState.describeError(e));
      }
    }
  }

  void _backToList() => setState(() {
    _card = null;
    _plan = null;
    _teamError = null;
  });

  /// The picked team's picture, kept for the import page.
  Uri? _cover;

  Future<void> _start(TeamPlan plan) async {
    final app = context.read<AppState>();
    final import = TeamImport(app, plan);
    setState(() {
      _cover = _card == null ? null : app.teamCatalog.coverOf(_card!);
      _import = import;
    });
    await _run(import);
  }

  Future<void> _run(TeamImport import) async {
    final done = await import.run();
    if (done && mounted) Navigator.pop(context, import);
  }

  Future<void> _rollback(TeamImport import) async {
    final s = Strings.of(context);
    try {
      await import.rollback();
      if (!mounted) return;
      showToast(context, s.teamDeletedCreated);
      import.dispose();
      setState(() => _import = null);
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppState.describeError(e),
          icon: Icons.error_outline,
        );
      }
    }
  }

  /// Leaving a half-made team keeps what was created: say so first.
  Future<void> _askLeave() async {
    final s = Strings.of(context);
    final navigator = Navigator.of(context);
    final leave = await showConfirmSheet(
      context,
      title: s.teamLeaveTitle,
      confirmLabel: s.teamLeave,
      cancelLabel: s.teamFinish,
    );
    if (leave && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<AppState>().teamCatalog;
    final import = _import;
    if (import != null) {
      return ListenableBuilder(
        listenable: import,
        builder: (context, _) => PopScope(
          canPop: !import.running && import.created.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !import.running) _askLeave();
          },
          child: _ImportView(
            import: import,
            cover: _cover,
            onRetry: () => _run(import),
            onRollback: () => _rollback(import),
          ),
        ),
      );
    }
    final card = _card;
    if (card != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _backToList();
        },
        child: _TeamView(
          card: card,
          cover: catalog.coverOf(card),
          plan: _plan,
          error: _teamError,
          onBack: _backToList,
          onRetry: () => _openCard(card),
          onAdd: _start,
        ),
      );
    }
    return _CatalogView(
      cards: _cards,
      error: _cardsError,
      coverOf: catalog.coverOf,
      onRetry: _loadCards,
      onOpen: _openCard,
    );
  }
}

/// Centers a column of content at a readable width.
class _Body extends StatelessWidget {
  const _Body({required this.children, this.maxWidth = 620});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: children,
      ),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: TextStyle(color: cs.onErrorContainer)),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: cs.onErrorContainer),
              child: Text(Strings.of(context).retry),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// --- the catalog ------------------------------------------------------------

/// The marketplace: its sections, for now the teams. Each team is one
/// compact row (picture, name, what it does, who is in it), so the whole
/// shelf fits on a phone screen; two columns once the sheet is wide.
class _CatalogView extends StatelessWidget {
  const _CatalogView({
    required this.cards,
    required this.error,
    required this.coverOf,
    required this.onRetry,
    required this.onOpen,
  });

  final List<TeamCard>? cards;
  final String? error;
  final Uri? Function(TeamCard card) coverOf;
  final VoidCallback onRetry;
  final ValueChanged<TeamCard> onOpen;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final list = cards;
    return Scaffold(
      appBar: AppBar(
        leading: inSheet(context) ? const CloseButton() : null,
        title: Text(s.teamsTitle),
      ),
      body: _Body(
        maxWidth: 980,
        children: [
          Text(
            s.marketplaceIntro,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // One section per kind of thing the marketplace offers; teams
          // are the first.
          _MarketSection(title: s.teamsSection, subtitle: s.teamsIntro),
          if (error != null)
            _ErrorBox(message: s.teamsLoadFailed(error!), onRetry: onRetry)
          else if (list == null)
            const _CatalogSkeleton()
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(s.teamsEmpty, textAlign: TextAlign.center),
            )
          else
            _RowGrid(
              children: [
                for (final card in list)
                  _TeamRow(
                    card: card,
                    cover: coverOf(card),
                    onTap: () => onOpen(card),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The heading of one kind of thing in the marketplace.
class _MarketSection extends StatelessWidget {
  const _MarketSection({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A team's picture at 16:9. While it loads, and when it cannot be had,
/// a calm moss-tinted panel with a team icon stands in.
class _Cover extends StatelessWidget {
  const _Cover({required this.uri, this.radius = 0});

  final Uri? uri;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: cs.primaryContainer,
      child: Center(
        child: Icon(
          Icons.groups_outlined,
          size: 48,
          color: cs.onPrimaryContainer.withValues(alpha: 0.5),
        ),
      ),
    );
    final url = uri?.toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: url == null
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                frameBuilder: (context, child, frame, sync) => sync
                    ? child
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: frame == null ? placeholder : child,
                      ),
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.card,
    required this.cover,
    required this.onTap,
  });

  final TeamCard card;
  final Uri? cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = card.name.pick(s.code);
    final summary = card.summary.pick(s.code);
    return Semantics(
      button: true,
      label: [
        name,
        if (summary.isNotEmpty) summary,
        if (card.members > 0) s.teamMemberCount(card.members),
      ].join('. '),
      excludeSemantics: true,
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(width: 112, child: _Cover(uri: cover, radius: 12)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (card.faces.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _FaceStack(
                          faces: [
                            for (final (i, f) in card.faces.indexed)
                              ('${card.id}-$i', f),
                          ],
                          size: 22,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows one under another on a phone, two side by side once there is room.
class _RowGrid extends StatelessWidget {
  const _RowGrid({required this.children});

  final List<Widget> children;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 720 ? 2 : 1;
      final width = (c.maxWidth - _gap * (columns - 1)) / columns;
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// The shelf while the catalog loads: rows shaped like the real ones.
class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget row() => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 112, height: 63, radius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 16),
                SizedBox(height: 8),
                SkeletonBox(height: 12),
                SizedBox(height: 6),
                SkeletonBox(width: 90, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
    return SkeletonPulse(
      child: _RowGrid(children: [for (var i = 0; i < 4; i++) row()]),
    );
  }
}

/// The members' faces side by side, overlapping a little: the team at a
/// glance, the way it will look in the Hob list. Each face is a name (it
/// seeds a face without a shape) and the face the catalog gives it.
class _FaceStack extends StatelessWidget {
  const _FaceStack({required this.faces, this.size = 36});

  final List<(String, TeamFace)> faces;
  final double size;

  @override
  Widget build(BuildContext context) {
    final step = size * 0.78;
    return SizedBox(
      width: size + step * (faces.length - 1),
      height: size,
      child: Stack(
        children: [
          for (final (i, (name, face)) in faces.indexed)
            Positioned(
              left: step * i,
              child: HobAvatar(
                hob: Hob(name: name, displayName: name),
                size: size,
                face: HobAvatar.resolve(
                  name: name,
                  shape: face.shape,
                  color: face.color,
                  custom: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- one team ---------------------------------------------------------------

/// A team's page: its picture, who joins and what they will do, and the
/// one button that adds it.
class _TeamView extends StatelessWidget {
  const _TeamView({
    required this.card,
    required this.cover,
    required this.plan,
    required this.error,
    required this.onBack,
    required this.onRetry,
    required this.onAdd,
  });

  final TeamCard card;
  final Uri? cover;
  final TeamPlan? plan;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final ValueChanged<TeamPlan> onAdd;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = plan;
    final lang = s.code;
    final summary = card.summary.pick(lang);
    final description = p?.team.description.pick(lang) ?? '';
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: onBack)),
      bottomNavigationBar: p == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () => onAdd(p),
                        icon: const Icon(Icons.group_add_outlined),
                        label: Text(s.addTeam),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: _Body(
        children: [
          _Cover(uri: cover, radius: _radius),
          const SizedBox(height: 16),
          Text(
            card.name.pick(lang),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            _ErrorBox(message: s.teamsLoadFailed(error!), onRetry: onRetry),
          ] else if (p == null)
            const _TeamSkeleton()
          else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _FaceStack(
                  faces: [for (final m in p.members) (m.handle, m.spec.face)],
                ),
                const SizedBox(width: 12),
                Text(
                  s.teamMemberCount(p.members.length),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(description, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: 16),
            // What adding the team makes, in one place.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.folder_outlined,
                    text: s.teamFolder(p.folderName),
                  ),
                  if (p.groupName != null)
                    _InfoRow(
                      icon: Icons.forum_outlined,
                      text: s.teamGroup(p.groupName!),
                    ),
                  if (p.jobCount > 0)
                    _InfoRow(icon: Icons.schedule, text: s.teamJobsOff),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 20,
                    color: cs.onTertiaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.teamReviewNote,
                      style: TextStyle(color: cs.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            _SectionLabel(s.teamMembersHeading),
            for (final m in p.members) _MemberTile(plan: p, member: m),
          ],
        ],
      ),
    );
  }
}

/// A team's page while it loads: lines where the faces and text will be.
class _TeamSkeleton extends StatelessWidget {
  const _TeamSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
    child: Padding(
      padding: EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 160, height: 36, radius: 18),
          SizedBox(height: 18),
          SkeletonBox(height: 14),
          SizedBox(height: 8),
          SkeletonBox(height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: 200, height: 14),
          SizedBox(height: 20),
          SkeletonBox(height: 96, radius: _radius),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A member as it will be created: face, role and handle, unfolding to its
/// instructions and jobs.
class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.plan, required this.member});

  final TeamPlan plan;
  final PlannedMember member;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final spec = member.spec;
    final title = spec.title.pick(plan.lang);
    final description = spec.description.pick(plan.lang);
    final soul = plan.soulOf(member);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'GeistMono',
      height: 1.45,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: HobAvatar(
            hob: Hob(name: member.handle, displayName: title),
            size: 40,
            face: HobAvatar.resolve(
              name: member.handle,
              shape: spec.face.shape,
              color: spec.face.color,
              custom: true,
            ),
          ),
          title: Text(title),
          subtitle: Text(
            [
              '@${member.handle}',
              if (description.isNotEmpty) description,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (member.handle != spec.handle)
              _Note(s.teamHandleTaken(spec.handle)),
            if (member.model != null) _Note(s.teamModel(member.model!)),
            if (soul.isNotEmpty) ...[
              _SubLabel(s.teamInstructions),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(soul, style: mono),
              ),
            ],
            if (spec.jobs.isNotEmpty) ...[
              _SubLabel(s.teamJobsHeading),
              for (final job in spec.jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${job.name.pick(plan.lang)} · ${job.schedule}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        plan.resolve(job.prompt.pick(plan.lang)),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// --- the import -------------------------------------------------------------

class _ImportView extends StatelessWidget {
  const _ImportView({
    required this.import,
    required this.cover,
    required this.onRetry,
    required this.onRollback,
  });

  final TeamImport import;
  final Uri? cover;
  final VoidCallback onRetry;
  final VoidCallback onRollback;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final plan = import.plan;
    final error = import.error;
    final stopped = import.failed && !import.running;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: stopped && inSheet(context) ? const CloseButton() : null,
        title: Text(plan.team.name.pick(plan.lang)),
      ),
      body: _Body(
        children: [
          _Cover(uri: cover, radius: _radius),
          const SizedBox(height: 20),
          Text(
            stopped
                ? s.teamImportFailed(AppState.describeError(error ?? ''))
                : s.teamImporting,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: import.steps.isEmpty
                ? null
                : import.doneCount / import.steps.length,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          for (final step in import.steps) _StepRow(step: step, plan: plan),
          if (stopped) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: onRetry, child: Text(s.teamFinish)),
                if (import.created.isNotEmpty)
                  TextButton(
                    onPressed: onRollback,
                    child: Text(s.teamDeleteCreated),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.plan});

  final TeamStep step;
  final TeamPlan plan;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final member = step.kind == TeamStepKind.member
        ? plan.members.firstWhere((m) => m.handle == step.label)
        : null;
    final (IconData kindIcon, String label) = switch (step.kind) {
      TeamStepKind.member => (
        Icons.person_outline,
        '${member!.spec.title.pick(plan.lang)} · @${member.handle}',
      ),
      TeamStepKind.job => (Icons.schedule, step.label),
      TeamStepKind.group => (Icons.forum_outlined, step.label),
    };
    final status = switch (step.state) {
      TeamStepState.pending => Icon(
        Icons.circle_outlined,
        size: 20,
        color: cs.outlineVariant,
      ),
      TeamStepState.running => const SizedBox.square(
        dimension: 20,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      TeamStepState.done => Icon(
        Icons.check_circle,
        size: 20,
        color: cs.primary,
      ),
      TeamStepState.warning => Icon(
        Icons.warning_amber_rounded,
        size: 20,
        color: cs.tertiary,
      ),
      TeamStepState.failed => Icon(Icons.error, size: 20, color: cs.error),
    };
    final warning = step.state == TeamStepState.warning
        ? (step.kind == TeamStepKind.job
              ? s.teamStepJobNotPaused
              : s.teamStepLookRefused)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          status,
          const SizedBox(width: 12),
          Icon(kindIcon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (warning != null)
                  Text(
                    warning,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
