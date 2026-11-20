import '../state/biometrics.dart';
import 'strings.dart';

/// English language pack. Same voice as the Czech one: short, plain, casual.
class StringsEn extends Strings {
  const StringsEn();

  @override
  String get code => 'en';

  // --- login ---------------------------------------------------------------
  @override
  String get loginSubtitle => 'Sign in to your Hermes Agent dashboard';
  @override
  String get serverLabel => 'Server';
  @override
  String get serverInvalid => 'Enter a URL, like https://hermes.devrel.cz';
  @override
  String get usernameLabel => 'Username';
  @override
  String get passwordLabel => 'Password';
  @override
  String get fieldRequired => 'Required';
  @override
  String get rememberPassword => 'Remember password';
  @override
  String get signIn => 'Sign in';
  @override
  String get savedPasswordExpired =>
      'Your saved password no longer works. Sign in again.';

  // --- errors --------------------------------------------------------------
  @override
  String get errorBadCredentials => 'Wrong username or password.';
  @override
  String get errorNoPasswordLogin =>
      'This server doesn\'t allow password sign-in (provider "basic").';
  @override
  String get errorTooManyAttempts => 'Too many attempts. Wait a moment.';
  @override
  String get errorServerDown => 'The server is unavailable (503).';
  @override
  String errorServer(String message) => 'Server error: $message';
  @override
  String errorUnreachable(String message) =>
      'Can\'t reach the server: $message';
  @override
  String errorTls(String message) => 'TLS error: $message';
  @override
  String get errorTimeout => 'The request timed out.';
  @override
  String get errorBadServerUrl => 'That server address isn\'t valid.';
  @override
  String get errorNoSessionCookie =>
      'The server didn\'t return a session cookie';

  // --- hob list ------------------------------------------------------------
  @override
  String get hobsTitle => 'Hobs';
  @override
  String get pickHob => 'Pick a Hob on the left';
  @override
  String get filterAll => 'All';
  @override
  String get filterUnread => 'Unread';
  @override
  String get filterPinned => 'Pinned';
  @override
  String get filterActive => 'Active';
  @override
  String get filterRecent => 'Recent';
  @override
  String get filterOlder => 'Older';
  @override
  String get account => 'Account';
  @override
  String get settings => 'Settings';
  @override
  String get signOut => 'Sign out';
  @override
  String get searchHobs => 'Search Hobs';
  @override
  String get retry => 'Try again';
  @override
  String get noHobs => 'This server has no Hobs yet.';
  @override
  String get noMatches => 'No Hobs match this filter.';
  @override
  String get working => 'working';
  @override
  String get noMessagesYet => 'No messages yet';
  @override
  String get connected => 'Connected';
  @override
  String get connecting => 'Connecting…';
  @override
  String get disconnected => 'Disconnected';
  @override
  String get folderFallback => 'Folder';
  @override
  String get unassigned => 'Unsorted';
  @override
  String get renameFolder => 'Rename';
  @override
  String get renameFolderTitle => 'Rename folder';
  @override
  String get folderNameLabel => 'Folder name';
  @override
  String get save => 'Save';
  @override
  String get cancel => 'Cancel';
  @override
  String get renameFolderFailed => 'Could not rename the folder. Try again.';
  @override
  String get folderOptions => 'Folder options';
  @override
  String get moveFolder => 'Move folder';

  // --- hob profile ---------------------------------------------------------
  @override
  String get hobProfile => 'Hob profile';
  @override
  String editHob(String hob) => 'Edit profile: $hob';
  @override
  String get appearance => 'Appearance';
  @override
  String get blobFaceLabel => 'Face';
  @override
  String get randomizeFace => 'Another face';
  @override
  String get shapeLabel => 'Classic shape';
  @override
  String get colorLabel => 'Color';
  @override
  String get byName => 'From the name';
  @override
  String get autoLabel => 'Auto';
  @override
  String get hobTitleLabel => 'Title';
  @override
  String get hobDescriptionLabel => 'Description';
  @override
  String get hobDescriptionHint => 'What should this Hob help with?';
  @override
  String get modelSection => 'Model';
  @override
  String get providerLabel => 'Provider';
  @override
  String get modelLabel => 'Model';
  @override
  String get inheritModel => 'Inherit from the default profile';
  @override
  String get modelRequired => 'Fill in both the provider and the model.';
  @override
  String get soulSection => 'SOUL.md';
  @override
  String get soulHint => 'The Hob\'s persona and standing instructions';
  @override
  String get setupLoadFailed =>
      'Could not load the model and SOUL.md. The rest of the profile can be edited.';
  @override
  String get confirmModelTitle => 'Switch the model?';
  @override
  String get confirmModelFallback =>
      'The server asks you to confirm the model change.';
  @override
  String get switchModel => 'Switch';
  @override
  String hobSaved(String hob) => '$hob profile saved';
  @override
  String hobSaveFailed(String reason) => 'Could not save: $reason';
  @override
  String get hobSaveRefused => 'The server refused the change. Try again.';
  @override
  String get discardChangesTitle => 'Discard unsaved changes?';
  @override
  String get discardChanges => 'Discard';
  @override
  String get keepEditing => 'Keep editing';

  // --- chat ----------------------------------------------------------------
  @override
  String get scheduledJobs => 'Scheduled jobs';
  @override
  String get connectionLost =>
      'Lost the connection to the server. Reconnecting…';
  @override
  String get reconnectNow => 'Now';
  @override
  String newMessages(int n) => '$n new';
  @override
  String get jumpToEnd => 'Jump to latest';
  @override
  String get tryAgain => 'Retry';
  @override
  String get openingChat => 'Opening Hob Chat…';
  @override
  String workingOn(String? status) =>
      status != null ? 'working · $status' : 'working…';
  @override
  String get workingInBackground => 'working in the background';
  @override
  String activeAgo(String age) => 'active $age';
  @override
  String writeTo(String hob) => 'Send $hob a message';
  @override
  String get interruptedTag => 'stopped';
  @override
  String get copy => 'Copy';
  @override
  String get copied => 'Copied';
  @override
  String get thinking => 'Thinking…';
  @override
  String get messageHint => 'Write a message';
  @override
  String get stop => 'Stop';
  @override
  String get send => 'Send';
  @override
  String get modelTooltip => 'The Hob\'s model (change it in the profile)';
  @override
  String get reasoningLevel => 'Reasoning level';
  @override
  String get reasoning => 'Reasoning';
  @override
  String get approvalModeTooltip =>
      'Approval of dangerous commands (applies to the whole Hob)';
  @override
  String approvalModeLabel(String mode) => switch (mode) {
    'manual' => 'Manual',
    'smart' => 'Smart',
    'off' => 'Off',
    _ => 'Approvals',
  };
  @override
  String approvalModeHint(String mode) => switch (mode) {
    'manual' => 'Asks before every dangerous command',
    'smart' => 'Approves safe ones itself, asks only about risky ones',
    'off' => 'Never asks, runs everything right away',
    _ => mode,
  };
  @override
  String approvalTitle(String? tool) =>
      'The Hob needs your approval${tool != null ? ' ($tool)' : ''}';
  @override
  String get allowOnce => 'Allow once';
  @override
  String get allowSession => 'Allow in this chat';
  @override
  String get allowAlways => 'Always allow';
  @override
  String get deny => 'Deny';
  @override
  String get hobAsks => 'The Hob has a question';
  @override
  String get orOwnAnswer => 'or write your own answer';
  @override
  String get answerHint => 'Your answer';
  @override
  String get skip => 'Skip';
  @override
  String get answer => 'Answer';

  @override
  String? toolLabel(String tool) => switch (tool) {
    'message_agent' || 'send_message' => 'message to agent',
    'skill_view' || 'skills_list' || 'skill_load' => 'skill',
    'terminal' || 'execute_code' => 'command',
    'web_search' => 'web search',
    'web_extract' || 'browser_navigate' => 'web',
    'read_file' || 'search_files' => 'files',
    'write_file' || 'patch' => 'file edit',
    'clarify' => 'question',
    'cronjob' => 'scheduled job',
    'todo' => 'to-dos',
    'memory' => 'memory',
    'delegate_task' => 'delegation',
    _ => null,
  };

  // --- chat state ----------------------------------------------------------
  @override
  String openChatFailed(Object e) => 'Couldn\'t open the chat: $e';
  @override
  String recoverFailed(Object e) =>
      'Couldn\'t restore the chat after the connection dropped: $e';
  @override
  String get chatNotReady => 'The chat isn\'t ready yet.';
  @override
  String interruptFailed(Object e) => 'Couldn\'t stop the Hob: $e';
  @override
  String reasoningChangeFailed(Object e) =>
      'Couldn\'t change the reasoning level: $e';
  @override
  String approvalModeChangeFailed(Object e) =>
      'Couldn\'t change the approval mode: $e';
  @override
  String approvalAnswerFailed(Object e) => 'Couldn\'t send your approval: $e';
  @override
  String clarifyAnswerFailed(Object e) => 'Couldn\'t send your answer: $e';
  @override
  String preparingTool(String? tool) => 'Preparing ${tool ?? 'a tool'}…';
  @override
  String get unknownError => 'Unknown error';
  @override
  String get interruptedNotice => 'Stopped';
  @override
  String get replyFailed => 'The reply ended with an error';

  // --- scheduled jobs ------------------------------------------------------
  @override
  String get refresh => 'Refresh';
  @override
  String jobsLoadFailed(Object? e) => 'Couldn\'t load the jobs: $e';
  @override
  String get noJobs => 'This Hob has no scheduled jobs.';
  @override
  String nextRun(String when) => 'Next run: $when';
  @override
  String get paused => 'Paused';
  @override
  String lastRun(String when) => 'Last run: $when';
  @override
  String get failedTag => 'failed';
  @override
  String get jobFallback => 'Job';

  // --- biometric lock ------------------------------------------------------
  @override
  String unlockWith(BiometricKind kind) => 'Unlock with ${_name(kind)}';
  @override
  String signInWith(BiometricKind kind) => 'Sign in with ${_name(kind)}';
  @override
  String biometricSetting(BiometricKind kind) => 'Unlock with ${_name(kind)}';

  static String _name(BiometricKind kind) => switch (kind) {
    BiometricKind.faceId => 'Face ID',
    BiometricKind.touchId => 'Touch ID',
    BiometricKind.fingerprint => 'fingerprint',
    BiometricKind.face => 'face',
    BiometricKind.generic => 'biometrics',
  };
  @override
  String get biometricSettingHint =>
      'When the app starts and after a minute away. Sign in without typing '
      'the password.';
  @override
  String get biometricReason => "Confirm it's you";
  @override
  String get locked => 'Locked';
  @override
  String get signInWithPassword => 'Sign in with password';
  @override
  String get biometricFailed => "Couldn't verify you. Try again.";
  @override
  String get biometricUnavailable =>
      "Biometrics aren't available right now. Sign in with your password.";

  // --- settings ------------------------------------------------------------
  @override
  String get security => 'Security';
  @override
  String get language => 'Language';
  @override
  String get languageSystem => 'Same as device';
  @override
  String languageSystemNow(String name) => 'Now: $name';
  @override
  String get languageName => 'English';

  // --- dates ---------------------------------------------------------------
  @override
  String get now => 'now';
  @override
  String get today => 'today';
  @override
  String get tomorrow => 'tomorrow';
  @override
  String get yesterday => 'yesterday';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  String shortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';
}
