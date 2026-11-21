import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'format.dart';
import 'placeholders.dart';
import 'sheets.dart';
import 'theme.dart';

/// The hob's scheduled jobs (dashboard's "Scheduled jobs" rail), read-only.
/// A side sheet on wide windows, a tall bottom sheet on phones.
Future<void> showCronSheet(BuildContext context, Hob hob) {
  final app = context.read<AppState>();
  return showScreenSheet<void>(
    context,
    kind: SheetKind.side,
    dragHandle: true,
    builder: (_) => _CronList(app: app, hob: hob),
  );
}

class _CronList extends StatefulWidget {
  const _CronList({required this.app, required this.hob});

  final AppState app;
  final Hob hob;

  @override
  State<_CronList> createState() => _CronListState();
}

class _CronListState extends State<_CronList> {
  late Future<List<CronJob>> _jobs = widget.app.cronJobs(widget.hob);

  void _reload() => setState(() => _jobs = widget.app.cronJobs(widget.hob));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              isWideWindow(context) ? 16 : sheetHandleGap,
              8,
              8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.scheduledJobs, style: theme.textTheme.titleLarge),
                      Text(
                        widget.hob.displayName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: s.refresh,
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CronJob>>(
              future: _jobs,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const _JobsSkeleton();
                }
                if (snap.hasError) {
                  return EmptyState(
                    art: const EmptyArt(
                      icon: Icons.cloud_off_outlined,
                      error: true,
                    ),
                    title: s.jobsLoadFailed(
                      AppState.describeError(snap.error!),
                    ),
                    action: OutlinedButton(
                      onPressed: _reload,
                      child: Text(s.retry),
                    ),
                  );
                }
                final jobs = snap.data!;
                if (jobs.isEmpty) {
                  return EmptyState(
                    art: const EmptyArt(icon: Icons.event_available_outlined),
                    title: s.noJobs,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _JobCard(job: jobs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One job: what it is, when it runs next (the line that matters most),
/// its schedule as written, and how the last run went.
class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final CronJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final paused = !job.enabled || job.state == 'paused';
    final failed =
        job.lastStatus == 'error' ||
        job.lastStatus == 'failed' ||
        job.lastError != null;
    final (badgeBg, badgeFg, icon) = failed
        ? (cs.errorContainer, cs.onErrorContainer, Icons.error_outline)
        : paused
        ? (cs.surfaceContainerHighest, cs.onSurfaceVariant, Icons.pause)
        : (cs.primaryContainer, cs.onPrimaryContainer, Icons.schedule);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: badgeFg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  paused
                      ? s.paused
                      : job.nextRun != null
                      ? s.nextRun(dayTime(job.nextRun!))
                      : job.schedule,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: paused ? cs.onSurfaceVariant : cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        job.schedule,
                        style: muted?.copyWith(
                          fontFamily: HobsTheme.monoFamily,
                        ),
                      ),
                    ),
                    if (job.lastRun != null)
                      Text(
                        '${s.lastRun(dayTime(job.lastRun!))}'
                        '${failed ? ', ${s.failedTag}' : ''}',
                        style: muted?.copyWith(color: failed ? cs.error : null),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobsSkeleton extends StatelessWidget {
  const _JobsSkeleton();

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonBox(height: 96, radius: 16),
          ),
      ],
    ),
  );
}
