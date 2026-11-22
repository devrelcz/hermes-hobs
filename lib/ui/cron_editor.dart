import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/cron_schedule.dart';
import 'accounts_ui.dart' show FormErrorBox, accountField;
import 'sheets.dart';
import 'theme.dart';

/// Schedules a new job for a Hob, like the dashboard's "New cron job"
/// dialog: a name, what to do, when, how many times and where the result
/// goes. A full-screen sheet on phones, a large dialog on wide screens.
class CronEditorScreen extends StatefulWidget {
  const CronEditorScreen({super.key, required this.hob});

  final Hob hob;

  /// True when a job was created.
  static Future<bool?> open(BuildContext context, Hob hob) =>
      showScreenSheet<bool>(
        context,
        kind: SheetKind.fullscreen,
        guarded: true,
        builder: (_) => CronEditorScreen(hob: hob),
      );

  @override
  State<CronEditorScreen> createState() => _CronEditorScreenState();
}

class _CronEditorScreenState extends State<CronEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _prompt = TextEditingController();
  final _amount = TextEditingController(text: '30');
  final _expression = TextEditingController();
  final _repeat = TextEditingController();
  final _schedule = CronSchedule();
  bool _toChat = false;
  bool _continuity = false;
  bool _busy = false;
  String? Function()? _error;

  bool get _dirty =>
      _name.text.trim().isNotEmpty || _prompt.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _amount.dispose();
    _expression.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final schedule = _schedule.toSchedule();
    if (schedule == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    final name = _name.text.trim();
    final repeat = _schedule.repeats ? int.tryParse(_repeat.text.trim()) : null;
    try {
      await app.createCron(
        widget.hob,
        name: name,
        schedule: schedule,
        prompt: _prompt.text,
        repeat: repeat,
        continuity: _continuity,
        toChat: _toChat,
      );
      if (!mounted) return;
      showToast(context, Strings.of(context).jobCreated(name));
      nav.pop(true);
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _schedule.hour, minute: _schedule.minute),
    );
    if (picked == null) return;
    setState(() {
      _schedule.hour = picked.hour;
      _schedule.minute = picked.minute;
    });
  }

  String _freqLabel(Strings s, CronFreq f) => switch (f) {
    CronFreq.once => s.freqOnce,
    CronFreq.hourly => s.freqHourly,
    CronFreq.daily => s.freqDaily,
    CronFreq.weekdays => s.freqWeekdays,
    CronFreq.weekly => s.freqWeekly,
    CronFreq.monthly => s.freqMonthly,
    CronFreq.interval => s.freqInterval,
    CronFreq.advanced => s.freqAdvanced,
  };

  String _unitLabel(Strings s, CronUnit u) => switch (u) {
    CronUnit.minutes => s.unitMinutes,
    CronUnit.hours => s.unitHours,
    CronUnit.days => s.unitDays,
  };

  String? _positive(String? v, Strings s) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < 1 ? s.numberInvalid : null;
  }

  Widget _timeButton(BuildContext context, Strings s) {
    final t = TimeOfDay(hour: _schedule.hour, minute: _schedule.minute);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      onPressed: _busy ? null : _pickTime,
      icon: const Icon(Icons.schedule),
      label: Text('${s.atTime} ${t.format(context)}'),
    );
  }

  /// A count and its unit: the delay of a single run or the gap between
  /// runs.
  Widget _amountRow(BuildContext context, Strings s, String label) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextFormField(
          controller: _amount,
          decoration: accountField(context, label, Icons.timelapse),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) => _positive(v, s),
          onChanged: (v) =>
              setState(() => _schedule.amount = int.tryParse(v) ?? 0),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: DropdownButtonFormField<CronUnit>(
          initialValue: _schedule.unit,
          decoration: accountField(
            context,
            '',
            Icons.straighten,
          ).copyWith(labelText: null),
          items: [
            for (final u in CronUnit.values)
              DropdownMenuItem(value: u, child: Text(_unitLabel(s, u))),
          ],
          onChanged: _busy
              ? null
              : (u) => setState(() => _schedule.unit = u ?? _schedule.unit),
        ),
      ),
    ],
  );

  List<Widget> _whenDetails(BuildContext context, Strings s) {
    final theme = Theme.of(context);
    switch (_schedule.freq) {
      case CronFreq.once:
        return [_amountRow(context, s, s.inHowLong)];
      case CronFreq.interval:
        return [_amountRow(context, s, s.everyHowOften)];
      case CronFreq.hourly:
        return const [];
      case CronFreq.daily || CronFreq.weekdays:
        return [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _timeButton(context, s),
          ),
        ];
      case CronFreq.weekly:
        return [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                ChoiceChip(
                  label: Text(s.weekdaysShort[d - 1]),
                  selected: _schedule.weekday == d,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _schedule.weekday = d),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _timeButton(context, s),
          ),
        ];
      case CronFreq.monthly:
        return [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _schedule.dayOfMonth,
                  decoration: accountField(
                    context,
                    s.dayOfMonth,
                    Icons.calendar_today_outlined,
                  ),
                  items: [
                    for (var d = 1; d <= 28; d++)
                      DropdownMenuItem(value: d, child: Text('$d.')),
                  ],
                  onChanged: _busy
                      ? null
                      : (d) => setState(
                          () =>
                              _schedule.dayOfMonth = d ?? _schedule.dayOfMonth,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              _timeButton(context, s),
            ],
          ),
        ];
      case CronFreq.advanced:
        return [
          TextFormField(
            controller: _expression,
            decoration: accountField(
              context,
              s.cronExpression,
              Icons.code,
              hint: '0 9 * * 1-5',
            ),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: HobsTheme.monoFamily,
            ),
            autocorrect: false,
            validator: (v) =>
                CronSchedule.validExpression(v ?? '') ? null : s.cronInvalid,
            onChanged: (v) => setState(() => _schedule.expression = v),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final error = _error?.call();
    final schedule = _schedule.toSchedule();
    final label = theme.textTheme.labelLarge?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _askDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: inSheet(context) ? const CloseButton() : null,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.newJob),
              Text(
                widget.hob.displayName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _form,
              onChanged: () => setState(() {}),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: accountField(
                      context,
                      s.jobName,
                      Icons.label_outline,
                      hint: s.jobNameHint,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? s.fieldRequired : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _prompt,
                    decoration: accountField(
                      context,
                      s.jobPrompt,
                      Icons.notes,
                      hint: s.jobPromptHint,
                    ).copyWith(alignLabelWithHint: true),
                    minLines: 4,
                    maxLines: 10,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? s.fieldRequired : null,
                  ),
                  const SizedBox(height: 20),
                  Text(s.whenToRun, style: label),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CronFreq>(
                    initialValue: _schedule.freq,
                    decoration: accountField(
                      context,
                      '',
                      Icons.repeat,
                    ).copyWith(labelText: null),
                    items: [
                      for (final f in CronFreq.values)
                        DropdownMenuItem(
                          value: f,
                          child: Text(_freqLabel(s, f)),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (f) => setState(
                            () => _schedule.freq = f ?? _schedule.freq,
                          ),
                  ),
                  const SizedBox(height: 12),
                  ..._whenDetails(context, s),
                  if (schedule != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      schedule,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: HobsTheme.monoFamily,
                      ),
                    ),
                  ],
                  if (_schedule.repeats) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _repeat,
                      decoration: accountField(
                        context,
                        s.stopAfter,
                        Icons.stop_circle_outlined,
                        hint: '∞',
                        helper: s.stopAfterHelper,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? null : _positive(v, s),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(s.deliverTo, style: label),
                  RadioGroup<bool>(
                    groupValue: _toChat,
                    onChanged: (v) {
                      if (!_busy) setState(() => _toChat = v ?? false);
                    },
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          value: false,
                          title: Text(s.deliverHistory),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<bool>(
                          value: true,
                          title: Text(s.deliverChat(widget.hob.displayName)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  CheckboxListTile(
                    value: _continuity,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _continuity = v ?? false),
                    title: Text(s.continuity),
                    subtitle: Text(s.continuityHelper),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
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
                        : Text(s.createJob),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
