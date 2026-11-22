/// How often a new scheduled job runs, as the job editor offers it.
enum CronFreq {
  once,
  hourly,
  daily,
  weekdays,
  weekly,
  monthly,
  interval,
  advanced,
}

/// A length of time the editor counts in.
enum CronUnit { minutes, hours, days }

/// What the job editor holds, turned into the schedule string Hermes reads:
/// a five-field cron expression for the calendar choices, `every <n>m` for
/// an interval and `<n>m|h|d` for a single run after a delay, the way the
/// dashboard writes them.
class CronSchedule {
  CronSchedule({
    this.freq = CronFreq.daily,
    this.hour = 9,
    this.minute = 0,
    this.weekday = DateTime.monday,
    this.dayOfMonth = 1,
    this.amount = 30,
    this.unit = CronUnit.minutes,
    this.expression = '',
  });

  CronFreq freq;
  int hour;
  int minute;

  /// [DateTime.monday] to [DateTime.sunday].
  int weekday;
  int dayOfMonth;

  /// The delay of a single run or the gap between runs, in [unit]s.
  int amount;
  CronUnit unit;

  /// The cron expression typed for [CronFreq.advanced].
  String expression;

  /// A run count limit applies: a single run has nothing to count.
  bool get repeats => freq != CronFreq.once;

  static final _field = RegExp(r'^[0-9A-Za-z*/,\-?LW#]+$');

  /// Whether [text] has the five fields of a cron expression.
  static bool validExpression(String text) {
    final fields = text.trim().split(RegExp(r'\s+'));
    return fields.length == 5 && fields.every(_field.hasMatch);
  }

  int get _minutes => switch (unit) {
    CronUnit.minutes => amount,
    CronUnit.hours => amount * 60,
    CronUnit.days => amount * 1440,
  };

  String get _unitLetter => switch (unit) {
    CronUnit.minutes => 'm',
    CronUnit.hours => 'h',
    CronUnit.days => 'd',
  };

  /// The schedule to send, or null while it is incomplete.
  String? toSchedule() {
    final m = minute.clamp(0, 59);
    final h = hour.clamp(0, 23);
    return switch (freq) {
      CronFreq.once => amount >= 1 ? '$amount$_unitLetter' : null,
      CronFreq.hourly => '$m * * * *',
      CronFreq.daily => '$m $h * * *',
      CronFreq.weekdays => '$m $h * * 1-5',
      // Cron counts Sunday as 0.
      CronFreq.weekly => '$m $h * * ${weekday % 7}',
      CronFreq.monthly => '$m $h ${dayOfMonth.clamp(1, 31)} * *',
      CronFreq.interval => amount >= 1 ? 'every ${_minutes}m' : null,
      CronFreq.advanced =>
        validExpression(expression)
            ? expression.trim().split(RegExp(r'\s+')).join(' ')
            : null,
    };
  }
}
