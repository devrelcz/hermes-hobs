/// Importing a ready-made team: a plan made against the user's Hobs, then
/// the steps that carry it out, one at a time, resumable after a failure.
library;

import 'package:flutter/foundation.dart';

import '../api/group_models.dart';
import '../api/models.dart';
import '../api/team_catalog.dart';
import 'app_state.dart';

/// A member as it will be created: the handle it gets and the model it runs.
class PlannedMember {
  const PlannedMember({
    required this.spec,
    required this.handle,
    this.provider,
    this.model,
  });

  final TeamMemberSpec spec;

  /// The member's preferred handle, or `-2`, `-3`… when that is taken.
  final String handle;

  /// The first preferred model the server offers; null inherits.
  final String? provider;
  final String? model;
}

/// What importing [team] will create on this server, in [lang].
class TeamPlan {
  const TeamPlan({
    required this.team,
    required this.lang,
    required this.members,
    required this.folderId,
    required this.folderName,
    required this.groupName,
  });

  final TeamSpec team;
  final String lang;
  final List<PlannedMember> members;

  /// An existing folder of the same name is reused.
  final String folderId;
  final String folderName;

  /// Null when no group chat will be made: the team asks for none, or the
  /// server has no group chats.
  final String? groupName;

  static final _placeholder = RegExp(r'\{\{\s*@([a-z0-9][a-z0-9-]*)\s*\}\}');

  /// [text] with every `{{@key}}` turned into that member's `@handle`.
  String resolve(String text) => text.replaceAllMapped(_placeholder, (m) {
    final key = m.group(1)!;
    final member = members.where((p) => p.spec.key == key).firstOrNull;
    return '@${member?.handle ?? key}';
  });

  String soulOf(PlannedMember m) => resolve(m.spec.soul).trim();

  int get jobCount => members.fold(0, (n, m) => n + m.spec.jobs.length);

  /// Works out handles, models and the folder for [team] on [app]'s server.
  static Future<TeamPlan> make(
    AppState app,
    TeamSpec team, {
    required String lang,
  }) async {
    final providers = team.members.any((m) => m.preferModels.isNotEmpty)
        ? await app.modelProviders().catchError((_) => <ModelProvider>[])
        : const <ModelProvider>[];
    (String, String)? pickModel(List<String> prefer) {
      for (final id in prefer) {
        final cut = id.indexOf('/');
        final provider = id.substring(0, cut);
        final model = id.substring(cut + 1);
        final offered = providers.any(
          (p) =>
              p.slug == provider && p.authenticated && p.models.contains(model),
        );
        if (offered) return (provider, model);
      }
      return null;
    }

    final reserved = <String>{};
    final members = <PlannedMember>[];
    for (final spec in team.members) {
      final handle = app.freeHobNameFor(spec.handle, reserved: reserved);
      reserved.add(handle);
      final model = pickModel(spec.preferModels);
      members.add(
        PlannedMember(
          spec: spec,
          handle: handle,
          provider: model?.$1,
          model: model?.$2,
        ),
      );
    }

    final folderName = team.folder.isEmpty
        ? team.name.pick(lang)
        : team.folder.pick(lang);
    final existing = app.folders.where((f) => f.name == folderName).firstOrNull;
    final groupName = team.groupName.isEmpty
        ? team.name.pick(lang)
        : team.groupName.pick(lang);
    return TeamPlan(
      team: team,
      lang: lang,
      members: members,
      folderId: existing?.id ?? AppState.newFolderId(),
      folderName: folderName,
      groupName: team.createGroup && app.groupsSupported == true
          ? groupName
          : null,
    );
  }
}

enum TeamStepKind { member, job, group }

enum TeamStepState { pending, running, done, warning, failed }

/// One thing the import creates.
class TeamStep {
  TeamStep(this.kind, this.label, this.run);

  final TeamStepKind kind;

  /// The member's handle, the job's name or the group chat's name.
  final String label;

  /// Does the work. Returns false when it worked only in part (a Hob whose
  /// look was refused, a job that could not be paused): the import goes on,
  /// the step shows a warning.
  final Future<bool> Function() run;

  TeamStepState state = TeamStepState.pending;
}

/// Carries out a [TeamPlan] step by step. A failed step stops the import;
/// [run] again picks up from that step, [rollback] deletes the Hobs made so
/// far (their jobs go with them).
class TeamImport extends ChangeNotifier {
  TeamImport(this.app, this.plan) {
    final origin = {
      'id': plan.team.id,
      'version': plan.team.version,
      'imported': DateTime.now().millisecondsSinceEpoch,
    };
    for (final m in plan.members) {
      steps.add(
        TeamStep(TeamStepKind.member, m.handle, () async {
          final ok = await app.createTeamHob(
            name: m.handle,
            title: m.spec.title.pick(plan.lang),
            description: m.spec.description.pick(plan.lang),
            soul: plan.soulOf(m),
            shape: m.spec.face.shape,
            color: m.spec.face.color,
            folderId: plan.folderId,
            folderName: plan.folderName,
            origin: {...origin, 'key': m.spec.key},
            provider: m.provider,
            model: m.model,
          );
          _created.add(m.handle);
          return ok;
        }),
      );
    }
    for (final m in plan.members) {
      for (final job in m.spec.jobs) {
        final name = job.name.pick(plan.lang);
        steps.add(
          // Jobs come after every member: a run stops at a failed member, so
          // by now each Hob exists.
          TeamStep(TeamStepKind.job, name, () async {
            return app.addPausedTeamJob(
              m.handle,
              name: name,
              schedule: job.schedule,
              prompt: plan.resolve(job.prompt.pick(plan.lang)),
              repeat: job.repeat,
              continuity: job.continuity,
              toChat: job.toChat,
            );
          }),
        );
      }
    }
    final groupName = plan.groupName;
    if (groupName != null) {
      steps.add(
        TeamStep(TeamStepKind.group, groupName, () async {
          room = await app.createGroup([
            for (final m in plan.members)
              Hob(name: m.handle, displayName: m.spec.title.pick(plan.lang)),
          ], name: groupName);
          return true;
        }),
      );
    }
  }

  final AppState app;
  final TeamPlan plan;
  final List<TeamStep> steps = [];
  final List<String> _created = [];

  /// The group chat, once made.
  GroupRoom? room;

  /// Why the last run stopped, or null.
  Object? error;

  bool running = false;
  bool rolledBack = false;

  /// Handles of the Hobs created so far.
  List<String> get created => List.unmodifiable(_created);

  bool get finished => steps.every(
    (s) => s.state == TeamStepState.done || s.state == TeamStepState.warning,
  );

  bool get failed => steps.any((s) => s.state == TeamStepState.failed);

  int get doneCount => steps
      .where(
        (s) =>
            s.state == TeamStepState.done || s.state == TeamStepState.warning,
      )
      .length;

  /// Runs every step not done yet, in order. Returns true when all are done.
  Future<bool> run() async {
    if (running || rolledBack) return false;
    running = true;
    error = null;
    notifyListeners();
    try {
      for (final step in steps) {
        if (step.state == TeamStepState.done ||
            step.state == TeamStepState.warning) {
          continue;
        }
        step.state = TeamStepState.running;
        notifyListeners();
        try {
          final ok = await step.run();
          step.state = ok ? TeamStepState.done : TeamStepState.warning;
        } catch (e) {
          step.state = TeamStepState.failed;
          error = e;
          return false;
        } finally {
          notifyListeners();
        }
      }
      return true;
    } finally {
      running = false;
      await app.refreshHobs(silent: true);
      notifyListeners();
    }
  }

  /// Deletes every Hob this import created. Their profiles take their jobs
  /// with them. Throws the first refusal after trying all of them.
  Future<void> rollback() async {
    if (running) return;
    running = true;
    notifyListeners();
    Object? firstError;
    try {
      for (final handle in List.of(_created)) {
        try {
          await app.deleteHob(
            app.hobNamed(handle) ?? Hob(name: handle, displayName: handle),
          );
          _created.remove(handle);
        } catch (e) {
          firstError ??= e;
        }
      }
      if (_created.isEmpty) rolledBack = true;
    } finally {
      running = false;
      notifyListeners();
    }
    if (firstError != null) throw firstError;
  }
}
