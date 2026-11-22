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
  String get welcomeTitle => 'Welcome to the Hobs';
  @override
  String get welcomeWhat =>
      'Each Hob is one agent on your server, with its own job and memory.';
  @override
  String get welcomeTalk =>
      'Write to it like in a chat. It answers and can reach for tools.';
  @override
  String get welcomeSafe =>
      'Before it runs anything risky, it asks for your approval.';
  @override
  String get welcomeStart => 'Get started';
  @override
  String get serverLabel => 'Server';
  @override
  String get serverInvalid => 'Enter a URL, like https://hermes.example.com';
  @override
  String get usernameLabel => 'Username';
  @override
  String get passwordLabel => 'Password';
  @override
  String get showPassword => 'Show password';
  @override
  String get hidePassword => 'Hide password';
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
  String get errorNotConnected => 'The app is not connected to the server.';
  @override
  String get errorConnectionClosed => 'The connection to the server dropped.';
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
  String get markAllRead => 'Mark all as read';
  @override
  String get signOut => 'Sign out';
  @override
  String get accounts => 'Accounts';
  @override
  String get addServer => 'Add server';
  @override
  String get manageAccounts => 'Manage accounts';
  @override
  String signOutFrom(String name) => 'Sign out of $name';
  @override
  String get accountName => 'Account name';
  @override
  String get accountNameHint => 'e.g. Home, Work';
  @override
  String get accountColor => 'Color';
  @override
  String accountColorName(int i) =>
      const ['green', 'purple', 'orange', 'blue', 'pink', 'amber'][i % 6];
  @override
  String get signInAndSwitch => 'Sign in and switch';
  @override
  String get addServerHint => 'The account is saved once signing in works.';
  @override
  String get tryDemo => 'Try the demo, no server needed';
  @override
  String get demoAccountName => 'Demo';
  @override
  String get scanQr => 'Scan the server\'s QR code';
  @override
  String get enterManually => 'Type the details';
  @override
  String get back => 'Back';
  @override
  String get scanTitle => 'Scan the QR code';
  @override
  String get scanInstruction =>
      'Run ./pair.sh on your server and point the camera at the code it shows.';
  @override
  String get scanNotPairing => 'This is not a Hermes pairing code.';
  @override
  String get scanNewerVersion =>
      'This code is for a newer version of the app. Update Hermes Hobs.';
  @override
  String get scanNoPermission =>
      'The camera is not allowed. Allow it for Hermes Hobs in the system settings, or type the sign-in details.';
  @override
  String get scanNoCamera =>
      'The camera cannot be used here. Type the sign-in details instead.';
  @override
  String get scanTorchOn => 'Turn the light on';
  @override
  String get scanTorchOff => 'Turn the light off';
  @override
  String get otherServer => 'Another server';
  @override
  String get savedAccounts => 'Saved accounts';
  @override
  String switchedTo(String name) => 'Switched to $name';
  @override
  String get editAccount => 'Edit account';
  @override
  String get newPassword => 'New password';
  @override
  String get newPasswordHint => 'Leave empty to keep the saved password.';
  @override
  String get accountSaved => 'Account saved';
  @override
  String get removeAccount => 'Remove account';
  @override
  String removeAccountTitle(String name) => 'Remove $name?';
  @override
  String get removeAccountBody =>
      'Its saved password and session leave this device. The Hobs on the server stay.';
  @override
  String get remove => 'Remove';
  @override
  String get accountActive => 'Active';
  @override
  String get accountsHint =>
      'Only the active account is connected and sends notifications.';
  @override
  String get dragToReorder => 'Drag to reorder';
  @override
  String get searchHobs => 'Search Hobs';
  @override
  String get clearSearch => 'Clear search';
  @override
  String get searchModels => 'Search models';
  @override
  String get noModelMatches => 'No model matches the search.';
  @override
  String get retry => 'Try again';
  @override
  String get noHobs =>
      'Create the first one, name it and say what it should help with.';
  @override
  String get noHobsTitle => 'No Hobs here yet';
  @override
  String get hobsLoadFailed => 'Could not load the Hobs';
  @override
  String get showAllHobs => 'Show all Hobs';
  @override
  String get pickHobHint => 'Create a new one with + above the list.';
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

  // --- hob menu ------------------------------------------------------------
  @override
  String hobMenuLabel(String hob) => 'Options: $hob';
  @override
  String get pinHob => 'Pin';
  @override
  String get unpinHob => 'Unpin';
  @override
  String get hideHob => 'Hide';
  @override
  String get unhideHob => 'Show in the list';
  @override
  String get moveToFolder => 'Move to folder';
  @override
  String get removeFromFolder => 'Remove from folder';
  @override
  String get newFolder => 'New folder…';
  @override
  String get newFolderTitle => 'New folder';
  @override
  String get hiddenHobs => 'Hidden Hobs';
  @override
  String hobHidden(String hob) => '$hob is hidden';
  @override
  String get undo => 'Undo';
  @override
  String get hobChangeFailed => 'Could not save the change. Try again.';
  @override
  String get deleteHob => 'Delete';
  @override
  String deleteHobTitle(String hob) => 'Delete $hob?';
  @override
  String get deleteHobMessage =>
      'Its profile leaves the server with its settings, memory, skills and conversations. This cannot be undone.';
  @override
  String hobDeleted(String hob) => '$hob was deleted';
  @override
  String hobDeleteFailed(String reason) => 'Could not delete the Hob: $reason';

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
  String get profileSection => 'Name and description';
  @override
  String get editSoul => 'Edit';
  @override
  String get soulEmpty =>
      'Empty so far. Write who the Hob is and how it should work.';
  @override
  String get done => 'Done';
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

  // --- new hob -------------------------------------------------------------
  @override
  String get newHob => 'New Hob';
  @override
  String get newHobHint =>
      'It takes over the default profile\'s settings, skills and sign-ins. Its model and SOUL.md can be changed later in its profile.';
  @override
  String get newHobNameLabel => 'Name';
  @override
  String get newHobNameHint => 'For example Bookkeeper Pete';
  @override
  String get hobHandleLabel => 'Handle';
  @override
  String get editHobHandle => 'Edit handle';
  @override
  String get hobHandleHelp =>
      'Used for @mentions and as the profile name on the server. It cannot be changed later.';
  @override
  String get hobHandleInvalid =>
      'Only lowercase letters, numbers, - and _, starting with a letter or number.';
  @override
  String get hobHandleTaken => 'Another Hob already has this handle.';
  @override
  String hobCreated(String hob) => '$hob is ready';
  @override
  String hobCreateFailed(String reason) => 'Could not create the Hob: $reason';

  // --- chat ----------------------------------------------------------------
  @override
  String get scheduledJobs => 'Scheduled jobs';
  @override
  String get connectionLost =>
      'Lost the connection to the server. Reconnecting…';
  @override
  String get reconnectNow => 'Now';

  // --- offline -------------------------------------------------------------
  @override
  String get offlineTitle => 'You are offline';
  @override
  String offlineHint({required bool phone}) => phone
      ? 'Turn on Wi-Fi or mobile data.'
      : 'Connect to Wi-Fi or a network.';
  @override
  String get offlineRetry => 'Try again';
  @override
  String get offlineChecking => 'Checking…';
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
  String activeSince(DateTime t, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(t);
    if (d.inMinutes < 1) return 'active just now';
    if (d.inHours < 1) return 'active ${d.inMinutes} min ago';
    if (d.inDays < 1) return 'active ${d.inHours} h ago';
    if (d.inDays == 1) return 'active yesterday';
    if (d.inDays < 7) return 'active ${d.inDays} days ago';
    return 'last active ${shortDate(t)}';
  }

  @override
  String get chatMenu => 'More options';
  @override
  String get a11yPinned => 'pinned';
  @override
  String get a11yUnread => 'unread';
  @override
  String messageFrom(String who) => '$who:';
  @override
  String get toolsUsed => 'Tools used';
  @override
  String get searchInChat => 'Search this chat';
  @override
  String get searchNone => 'None';
  @override
  String searchCount(int at, int of) => '$at of $of';
  @override
  String get searchOlder => 'Older match';
  @override
  String get searchNewer => 'Newer match';
  @override
  String get linkLabel => 'Link';
  @override
  String get fileLabel => 'File';
  @override
  String get resizeList => 'List width, drag sideways';
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

  // Attachments and sharing
  @override
  String get addAttachment => 'Add attachment';
  @override
  String get takePhoto => 'Take photo';
  @override
  String get choosePhotos => 'Choose photos';
  @override
  String get chooseFiles => 'Choose files';
  @override
  String get addLink => 'Add link';
  @override
  String get pasteImage => 'Paste image';
  @override
  String get noImageInClipboard => 'There is no image in the clipboard.';
  @override
  String get linkHint => 'https://…';
  @override
  String get linkInvalid =>
      'Enter a full address starting with http:// or https://';
  @override
  String get add => 'Add';
  @override
  String get removeAttachment => 'Remove attachment';
  @override
  String uploadFailed(Object error) => 'Upload failed: $error';
  @override
  String get uploadNoPath => 'The server did not return a path for the upload.';
  @override
  String attachmentTooLarge(int mb) => 'The file is larger than $mb MB.';
  @override
  String pickFailed(Object error) => 'Could not open the picker: $error';
  @override
  String get waitForUploads => 'Wait until the attachments are uploaded';
  @override
  String get linkOpenFailed => 'Could not open the link.';
  @override
  String get shareTitle => 'Send to a Hob';
  @override
  String shareSummary(int count) => count == 1
      ? '1 item goes into the chat; you send it yourself.'
      : '$count items go into the chat; you send them yourself.';
  @override
  String get shareNoHobs => 'There are no Hobs yet.';
  @override
  String get modelTooltip => 'Model for this chat';
  @override
  String get sessionModelTitle => 'Model for this chat';
  @override
  String get sessionModelHint =>
      'Applies to this chat only. The Hob keeps its default model.';
  @override
  String get hobDefaultTag => 'Hob\'s default';
  @override
  String get useHobDefaultModel => 'Use the Hob\'s default';
  @override
  String get sessionModelTag => 'this chat only';
  @override
  String modelSwitchDeferred(String model) =>
      '$model takes over once the current reply is done.';
  @override
  String get modelsUnavailable => 'Couldn\'t load the list of models.';
  @override
  String get reasoningLevel => 'Reasoning level';
  @override
  String get chatSettings => 'Chat settings';
  @override
  String get approvalHeading => 'Command approval';
  @override
  String get approvalScope => 'Applies to the whole Hob, not just this chat.';
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
  String get approvalWaiting => 'Waiting for your approval';
  @override
  String get clarifyWaiting => 'Answer and it carries on';
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
  String modelChangeFailed(Object e) => 'Couldn\'t switch the model: $e';
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

  // --- group chats ---------------------------------------------------------
  @override
  String get groupChats => 'Group chats';
  @override
  String get newGroupChat => 'New group chat';
  @override
  String get groupPickTitle => 'New group';
  @override
  String get groupPickHint => 'Pick 2 to 6 Hobs to talk together.';
  @override
  String get groupNameLabel => 'Group name';
  @override
  String groupPickCount(int picked, int max) =>
      '$picked picked of at most $max, at least 2.';
  @override
  String get create => 'Create';
  @override
  String get groupCreateFailed => 'Could not create the group chat.';
  @override
  String groupLoadFailed(String reason) =>
      'Could not load the group chat: $reason';
  @override
  String get groupSendUnconfirmed =>
      'The server did not confirm the message. Check the chat and send it again if needed.';
  @override
  String get groupDisbandUnconfirmed =>
      'The server did not confirm ending the group. Try again.';
  @override
  String groupMembers(int n) => n == 1 ? '1 Hob' : '$n Hobs';
  @override
  String get groupMessageHint => 'Message the group, @mention to assign';
  @override
  String get groupEmpty => 'Write the first message; every Hob answers.';
  @override
  String get groupOptions => 'Group options';
  @override
  String get renameGroup => 'Rename';
  @override
  String get renameGroupTitle => 'Rename group';
  @override
  String get disbandGroup => 'End group';
  @override
  String get disbandGroupBody =>
      'The group chat ends on every device. The Hobs stop talking in it and '
      'it cannot be brought back.';
  @override
  String get disband => 'End';
  @override
  String get groupDisbanded => 'This group chat has ended.';
  @override
  String get you => 'You';
  @override
  String mention(String handle) => 'Mention @$handle';
  @override
  String get memberWaits => 'waiting for you';
  @override
  String memberStateLabel(String state) => switch (state) {
    'queued' => 'queued',
    'working' => 'working',
    'replied' => 'replied',
    'passed' => 'passed',
    'failed' => 'failed',
    'cancelled' => 'stopped',
    _ => 'idle',
  };
  @override
  String get roundCapped => 'The Hobs reached the round limit.';
  @override
  String get continueRound => 'Continue';
  @override
  String turnFailed(String member, String? reason) =>
      reason == null || reason.isEmpty
      ? '$member did not answer.'
      : '$member did not answer: $reason';
  @override
  String get turnCancelled => 'Stopped.';
  @override
  String memberAsks(String member) => '$member asks for approval';
  @override
  String memberFailed(String member) => "$member's turn failed";
  @override
  String get discardTurn => 'Discard';
  @override
  String groupWorking(String members) => 'working: $members';

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
  @override
  String get newJob => 'New job';
  @override
  String get jobName => 'Name';
  @override
  String get jobNameHint => 'Morning briefing';
  @override
  String get jobPrompt => 'What the Hob should do';
  @override
  String get jobPromptHint =>
      'Go through my unread email and send me the five that matter most.';
  @override
  String get whenToRun => 'When to run';
  @override
  String get freqOnce => 'Once, in…';
  @override
  String get freqHourly => 'Every hour';
  @override
  String get freqDaily => 'Every day';
  @override
  String get freqWeekdays => 'Weekdays';
  @override
  String get freqWeekly => 'Every week';
  @override
  String get freqMonthly => 'Every month';
  @override
  String get freqInterval => 'Repeat every…';
  @override
  String get freqAdvanced => 'Custom (cron)';
  @override
  String get atTime => 'At';
  @override
  String get onDay => 'Day';
  @override
  String get dayOfMonth => 'Day of the month';
  @override
  String get inHowLong => 'In';
  @override
  String get everyHowOften => 'Every';
  @override
  String get unitMinutes => 'minutes';
  @override
  String get unitHours => 'hours';
  @override
  String get unitDays => 'days';
  @override
  List<String> get weekdaysShort => const [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  @override
  String get cronExpression => 'Cron expression';
  @override
  String get cronInvalid => 'Enter five fields, like 0 9 * * 1-5.';
  @override
  String get numberInvalid => 'Enter a whole number from 1.';
  @override
  String get stopAfter => 'Stop after this many runs';
  @override
  String get stopAfterHelper => 'Leave it empty to run with no end.';
  @override
  String get deliverTo => 'Send the result to';
  @override
  String get deliverHistory => 'Run history only';
  @override
  String deliverChat(String hob) => 'The chat with $hob, which answers it';
  @override
  String get continuity => 'Continue from the previous run';
  @override
  String get continuityHelper =>
      'Each run sees the last one\'s output, so nothing is reported twice.';
  @override
  String get createJob => 'Create job';
  @override
  String jobCreated(String name) => '$name is scheduled';
  @override
  String get jobCreateFailed => 'Couldn\'t create the job.';
  @override
  String get runNow => 'Run now';
  @override
  String get runStarted => 'The job is running';
  @override
  String get runningNow => 'Running now';
  @override
  String get jobOn => 'On';
  @override
  String jobUpdateFailed(Object? e) => 'Couldn\'t change the job: $e';
  @override
  String get deleteJob => 'Delete job';
  @override
  String deleteJobTitle(String name) => 'Delete $name?';
  @override
  String get deleteJobMessage =>
      'The job leaves the server and won\'t run again. This can\'t be undone.';
  @override
  String get jobDeleted => 'Job deleted';
  @override
  String get scheduleLabel => 'Schedule';
  @override
  String get resultLabel => 'Result';
  @override
  String chatWith(String hob) => 'Chat with $hob';
  @override
  String repeatProgress(int done, int times) => '$done of $times runs done';
  @override
  String get promptLabel => 'Prompt';
  @override
  String get lastErrorLabel => 'Last error';
  @override
  String get lastRunLabel => 'Last run';
  @override
  String get showMore => 'Show all';
  @override
  String get showLess => 'Show less';
  @override
  String get runHistory => 'Run history';
  @override
  String get noRuns => 'This job hasn\'t run yet.';
  @override
  String runsLoadFailed(Object? e) => 'Couldn\'t load the history: $e';
  @override
  String runDuration(String d) => 'took $d';
  @override
  String toolCallCount(int n) => n == 1 ? '1 tool' : '$n tools';
  @override
  String get scheduledRun => 'Scheduled job';
  @override
  String scheduledRunPrompt(String job) => 'Scheduled job: $job';

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
  String get about => 'About';
  @override
  String get appVersion => 'Version';
  @override
  String get signedInAs => 'Signed in as';
  @override
  String get licenses => 'Licenses';
  @override
  String get licensesHint => 'The Geist typeface and open-source libraries';
  @override
  String get unofficialApp => 'Unofficial community app';
  @override
  String get unofficialAppHint =>
      'Not made, endorsed or supported by Nous Research, the makers of '
      'Hermes Agent.';
  @override
  String get language => 'Language';
  @override
  String get languageSystem => 'Same as device';
  @override
  String languageSystemNow(String name) => 'Now: $name';
  @override
  String get languageName => 'English';

  // --- notifications -------------------------------------------------------
  @override
  String get notifications => 'Notifications';
  @override
  String get notificationsSetting => 'Notify me about Hobs';
  @override
  String get notificationsHint =>
      'When a Hob finishes a reply or waits for your approval or answer '
      'while the app is in the background.';
  @override
  String get notificationsBlocked =>
      'Notifications are turned off for this app in the system settings.';
  @override
  String notifyApproval(String what) => 'Wants your approval: $what';
  @override
  String notifyClarify(String question) => 'Asks: $question';
  @override
  String get notifyReplyDone => 'Finished the reply.';
  @override
  String get notifyGroupFailed => 'The reply failed. Retry or drop it?';
  @override
  String get notifyChannelName => 'Hobs';
  @override
  String get notifyChannelDescription =>
      'Finished replies and questions from your Hobs and group chats';

  // --- dates ---------------------------------------------------------------
  @override
  String get now => 'now';
  @override
  String get today => 'today';
  @override
  String get tomorrow => 'tomorrow';
  @override
  String get yesterday => 'yesterday';
  @override
  String weekday(int day) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][day - 1];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  String shortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';
}
