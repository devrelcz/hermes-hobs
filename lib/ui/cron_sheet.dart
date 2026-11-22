import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'cron_editor.dart';
import 'format.dart';
import 'placeholders.dart';
import 'sheets.dart';
import 'theme.dart';

/// The Hob's scheduled jobs, like the dashboard's "Scheduled jobs" rail:
/// switch them on and off, run one now, look at its runs, delete it, or
/// schedule a new one. A side sheet on wide windows, a tall bottom sheet on
/// phones; a job's detail opens in the same sheet.
Future<void> showCronSheet(BuildContext context, Hob hob) {
  final app = context.read<AppState>();
  return showScreenSheet<void>(
    context,
    kind: SheetKind.side,
    dragHandle: true,
    builder: (_) => CronSheet(app: app, hob: hob),
  );
}

class CronSheet extends StatefulWidget {
  const CronSheet({super.key, required this.app, required this.hob});

  final AppState app;
  final Hob hob;

  @override
  State<CronSheet> createState() => _CronSheetState();
}

class _CronSheetState extends State<CronSheet> {
  late Future<List<CronJob>> _jobs = widget.app.cronJobs(widget.hob);

  /// The job whose detail is open, by id.
  String? _open;

  /// Switch positions the server has not confirmed yet, by job id.
  final Map<String, bool> _switching = {};

  /// Jobs a manual run was just asked for, by id.
  final Set<String> _triggering = {};

  void _reload() {
    final jobs = widget.app.cronJobs(widget.hob);
    setState(() {
      _jobs = jobs;
    });
  }

  void _failed(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          Strings.of(context).jobUpdateFailed(AppState.describeError(e)),
        ),
      ),
    );
  }

  Future<void> _setEnabled(CronJob job, bool on) async {
    setState(() => _switching[job.id] = on);
    try {
      await widget.app.setCronEnabled(job, on);
      if (!mounted) return;
      final jobs = widget.app.cronJobs(widget.hob);
      await jobs.then((_) {}, onError: (_) {});
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _switching.remove(job.id);
      });
    } catch (e) {
      if (mounted) setState(() => _switching.remove(job.id));
      _failed(e);
    }
  }

  Future<void> _trigger(CronJob job) async {
    setState(() => _triggering.add(job.id));
    try {
      await widget.app.triggerCron(job);
      if (!mounted) return;
      showToast(
        context,
        Strings.of(context).runStarted,
        icon: Icons.play_circle_outline,
      );
      _reload();
    } catch (e) {
      _failed(e);
    } finally {
      if (mounted) setState(() => _triggering.remove(job.id));
    }
  }

  Future<void> _delete(CronJob job) async {
    final s = Strings.of(context);
    final ok = await showConfirmSheet(
      context,
      title: s.deleteJobTitle(job.name),
      message: s.deleteJobMessage,
      confirmLabel: s.deleteJob,
      cancelLabel: s.cancel,
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    try {
      await widget.app.deleteCron(job);
      if (!mounted) return;
      showToast(context, s.jobDeleted, icon: Icons.delete_outline);
      setState(() => _open = null);
      _reload();
    } catch (e) {
      _failed(e);
    }
  }

  Future<void> _create() async {
    final created = await CronEditorScreen.open(context, widget.hob);
    if (created == true && mounted) _reload();
  }

  /// [job] with the switch position the user just chose.
  CronJob _shown(CronJob job) {
    final on = _switching[job.id];
    if (on == null) return job;
    return CronJob(
      id: job.id,
      name: job.name,
      schedule: job.schedule,
      prompt: job.prompt,
      enabled: on,
      state: on ? 'scheduled' : 'paused',
      nextRun: job.nextRun,
      lastRun: job.lastRun,
      lastStatus: job.lastStatus,
      lastError: job.lastError,
      deliver: job.deliver,
      repeatTimes: job.repeatTimes,
      repeatCompleted: job.repeatCompleted,
      running: job.running,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    return Material(
      type: MaterialType.transparency,
      child: FutureBuilder<List<CronJob>>(
        future: _jobs,
        builder: (context, snap) {
          final jobs = snap.data;
          final open = _open == null || jobs == null
              ? null
              : jobs.where((j) => j.id == _open).firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  open == null ? 20 : 8,
                  isWideWindow(context) ? 16 : sheetHandleGap,
                  8,
                  8,
                ),
                child: Row(
                  children: [
                    if (open != null)
                      IconButton(
                        tooltip: s.back,
                        onPressed: () => setState(() => _open = null),
                        icon: const BackButtonIcon(),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            open?.name ?? s.scheduledJobs,
                            style: theme.textTheme.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                    if (open == null)
                      IconButton(
                        tooltip: s.newJob,
                        onPressed: _create,
                        icon: const Icon(Icons.add),
                      ),
                  ],
                ),
              ),
              Expanded(child: _body(context, snap, open)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncSnapshot<List<CronJob>> snap,
    CronJob? open,
  ) {
    final s = Strings.of(context);
    if (snap.connectionState != ConnectionState.done && !snap.hasData) {
      return const _JobsSkeleton();
    }
    if (snap.hasError) {
      return EmptyState(
        art: const EmptyArt(icon: Icons.cloud_off_outlined, error: true),
        title: s.jobsLoadFailed(AppState.describeError(snap.error!)),
        action: OutlinedButton(onPressed: _reload, child: Text(s.retry)),
      );
    }
    if (open != null) {
      final job = _shown(open);
      return _JobDetail(
        key: ValueKey('job-${job.id}'),
        app: widget.app,
        job: job,
        switching: _switching.containsKey(job.id),
        triggering: _triggering.contains(job.id),
        onEnabled: (on) => _setEnabled(open, on),
        onTrigger: () => _trigger(open),
        onDelete: () => _delete(open),
      );
    }
    final jobs = snap.data!;
    if (jobs.isEmpty) {
      return EmptyState(
        art: const EmptyArt(icon: Icons.event_available_outlined),
        title: s.noJobs,
        action: FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: Text(s.newJob),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final job = _shown(jobs[i]);
        return _JobCard(
          job: job,
          switching: _switching.containsKey(job.id),
          onTap: () => setState(() => _open = job.id),
          onEnabled: (on) => _setEnabled(jobs[i], on),
        );
      },
    );
  }
}

/// The badge in front of a job: failed, paused, running or waiting.
(Color, Color, IconData) _badge(ColorScheme cs, CronJob job) => job.failed
    ? (cs.errorContainer, cs.onErrorContainer, Icons.error_outline)
    : job.paused
    ? (cs.surfaceContainerHighest, cs.onSurfaceVariant, Icons.pause)
    : job.running
    ? (cs.tertiaryContainer, cs.onTertiaryContainer, Icons.play_arrow)
    : (cs.primaryContainer, cs.onPrimaryContainer, Icons.schedule);

/// The line that matters most: running, paused, or when it runs next.
String _statusLine(Strings s, CronJob job) => job.running
    ? s.runningNow
    : job.paused
    ? s.paused
    : job.nextRun != null
    ? s.nextRun(dayTime(job.nextRun!))
    : job.schedule;

/// One job: what it is, when it runs next, its schedule as written, how the
/// last run went, and its switch.
class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.switching,
    required this.onTap,
    required this.onEnabled,
  });

  final CronJob job;
  final bool switching;
  final VoidCallback onTap;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final (badgeBg, badgeFg, icon) = _badge(cs, job);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Material(
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: badgeBg,
                  shape: BoxShape.circle,
                ),
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
                      _statusLine(s, job),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: job.paused ? cs.onSurfaceVariant : cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _ScheduleChip(job.schedule),
                        if (job.lastRun != null)
                          Text(
                            '${s.lastRun(dayTime(job.lastRun!))}'
                            '${job.failed ? ', ${s.failedTag}' : ''}',
                            style: muted?.copyWith(
                              color: job.failed ? cs.error : null,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Semantics(
                label: s.jobOn,
                child: Switch(
                  value: job.enabled && job.state != 'paused',
                  onChanged: switching ? null : onEnabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleChip extends StatelessWidget {
  const _ScheduleChip(this.schedule);

  final String schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        schedule,
        style: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontFamily: HobsTheme.monoFamily,
        ),
      ),
    );
  }
}

/// "1 h 5 min", "3 min", "45 s".
String _duration(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds} s';
  if (d.inHours < 1) return '${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
}

/// One job in full: its switch, run now and delete, the schedule, where the
/// output goes, the prompt, and the latest runs.
class _JobDetail extends StatefulWidget {
  const _JobDetail({
    super.key,
    required this.app,
    required this.job,
    required this.switching,
    required this.triggering,
    required this.onEnabled,
    required this.onTrigger,
    required this.onDelete,
  });

  final AppState app;
  final CronJob job;
  final bool switching;
  final bool triggering;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onTrigger;
  final VoidCallback onDelete;

  @override
  State<_JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends State<_JobDetail> {
  late Future<List<CronRun>> _runs = widget.app.cronRuns(widget.job);
  bool _fullPrompt = false;

  @override
  void didUpdateWidget(_JobDetail old) {
    super.didUpdateWidget(old);
    // A reload after a run or a switch: the history may have grown.
    if (!identical(old.job, widget.job) &&
        (old.job.lastRun != widget.job.lastRun ||
            old.job.running != widget.job.running)) {
      _runs = widget.app.cronRuns(widget.job);
    }
  }

  String _deliverText(Strings s) {
    final job = widget.job;
    final hob = job.deliverHob;
    if (hob != null) {
      return s.chatWith(widget.app.hobNamed(hob)?.displayName ?? hob);
    }
    if (job.deliver == null || job.deliver == 'local') return s.deliverHistory;
    return job.deliver!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final job = widget.job;
    final (badgeBg, badgeFg, icon) = _badge(cs, job);
    final label = theme.textTheme.labelLarge?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final longPrompt = job.prompt.length > 400;

    Widget fact(String name, Widget value) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: label),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: badgeFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusLine(s, job),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: job.paused ? cs.onSurfaceVariant : cs.primary,
                ),
              ),
            ),
            Text(s.jobOn, style: muted),
            const SizedBox(width: 4),
            Switch(
              value: job.enabled && job.state != 'paused',
              onChanged: widget.switching ? null : widget.onEnabled,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: widget.triggering || job.running
                    ? null
                    : widget.onTrigger,
                icon: widget.triggering
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(s.runNow),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: cs.error,
                ),
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(s.deleteJob),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        fact(
          s.scheduleLabel,
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ScheduleChip(job.schedule),
              if (job.repeatTimes != null)
                Text(
                  s.repeatProgress(job.repeatCompleted, job.repeatTimes!),
                  style: muted,
                ),
            ],
          ),
        ),
        fact(
          s.resultLabel,
          Text(_deliverText(s), style: theme.textTheme.bodyMedium),
        ),
        if (job.lastRun != null)
          fact(
            s.lastRunLabel,
            Text(
              '${dayTime(job.lastRun!)}${job.failed ? ', ${s.failedTag}' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: job.failed ? cs.error : null,
              ),
            ),
          ),
        if (job.lastError != null)
          fact(
            s.lastErrorLabel,
            Text(
              job.lastError!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        if (job.prompt.isNotEmpty)
          fact(
            s.promptLabel,
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    longPrompt && !_fullPrompt
                        ? '${job.prompt.substring(0, 400).trimRight()}…'
                        : job.prompt,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                  if (longPrompt)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () =>
                          setState(() => _fullPrompt = !_fullPrompt),
                      child: Text(_fullPrompt ? s.showLess : s.showMore),
                    ),
                ],
              ),
            ),
          ),
        Text(s.runHistory, style: label),
        const SizedBox(height: 8),
        FutureBuilder<List<CronRun>>(
          future: _runs,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonPulse(
                child: SkeletonBox(height: 56, radius: 12),
              );
            }
            if (snap.hasError) {
              return Text(
                s.runsLoadFailed(AppState.describeError(snap.error!)),
                style: muted?.copyWith(color: cs.error),
              );
            }
            final runs = snap.data!;
            if (runs.isEmpty) return Text(s.noRuns, style: muted);
            return Column(children: [for (final r in runs) _RunRow(run: r)]);
          },
        ),
      ],
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final CronRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final (color, icon) = run.active
        ? (cs.tertiary, Icons.play_circle_outline)
        : run.failed
        ? (cs.error, Icons.error_outline)
        : (cs.primary, Icons.check_circle_outline);
    final details = [
      if (run.active) s.runningNow,
      if (run.duration != null) s.runDuration(_duration(run.duration!)),
      if (run.toolCalls > 0) s.toolCallCount(run.toolCalls),
      if (run.failed) s.failedTag,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.startedAt != null ? dayTime(run.startedAt!) : '—',
                  style: theme.textTheme.bodyMedium,
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: run.failed ? cs.error : cs.onSurfaceVariant,
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
