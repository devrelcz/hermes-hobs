import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../state/biometrics.dart';

import 'strings_cs.dart';
import 'strings_en.dart';

/// Every user-facing text of the app. One subclass per language pack:
/// [StringsCs] and [StringsEn].
///
/// Widgets read the pack with [Strings.of] so they rebuild when the language
/// changes. Code without a [BuildContext] (state, formatting) reads
/// [Strings.current].
abstract class Strings {
  const Strings();

  /// The active pack. Kept in sync by [delegate] and by the language setting.
  static Strings current = const StringsCs();

  static Strings of(BuildContext context) =>
      Localizations.of<Strings>(context, Strings) ?? current;

  static const supportedLocales = [Locale('cs'), Locale('en')];

  static const LocalizationsDelegate<Strings> delegate = _StringsDelegate();

  static Strings forLocale(Locale locale) =>
      locale.languageCode == 'cs' ? const StringsCs() : const StringsEn();

  /// Picks the app language for the device's preferred languages: the first
  /// one we have a pack for wins. Slovak readers get Czech; everyone else
  /// without a pack gets English.
  static Locale resolve(List<Locale>? preferred) {
    for (final l in preferred ?? const <Locale>[]) {
      switch (l.languageCode) {
        case 'cs' || 'sk':
          return const Locale('cs');
        case 'en':
          return const Locale('en');
      }
    }
    return const Locale('en');
  }

  /// Language code of this pack ("cs", "en").
  String get code;

  // --- login ---------------------------------------------------------------
  String get loginSubtitle;
  String get serverLabel;
  String get serverInvalid;
  String get usernameLabel;
  String get passwordLabel;
  String get showPassword;
  String get hidePassword;
  String get fieldRequired;
  String get rememberPassword;
  String get signIn;
  String get savedPasswordExpired;

  // --- errors --------------------------------------------------------------
  String get errorBadCredentials;
  String get errorNoPasswordLogin;
  String get errorTooManyAttempts;
  String get errorServerDown;
  String errorServer(String message);
  String errorUnreachable(String message);
  String errorTls(String message);
  String get errorTimeout;
  String get errorNotConnected;
  String get errorConnectionClosed;
  String get errorBadServerUrl;
  String get errorNoSessionCookie;

  // --- hob list ------------------------------------------------------------
  String get hobsTitle;
  String get pickHob;
  String get filterAll;
  String get filterUnread;
  String get filterPinned;
  String get filterActive;
  String get filterRecent;
  String get filterOlder;
  String get account;
  String get settings;
  String get signOut;
  String get searchHobs;
  String get clearSearch;
  String get searchModels;
  String get noModelMatches;
  String get retry;
  String get noHobs;
  String get noHobsTitle;
  String get hobsLoadFailed;
  String get showAllHobs;
  String get pickHobHint;
  String get noMatches;
  String get working;
  String get noMessagesYet;
  String get connected;
  String get connecting;
  String get disconnected;
  String get folderFallback;
  String get unassigned;
  String get renameFolder;
  String get renameFolderTitle;
  String get folderNameLabel;
  String get save;
  String get cancel;
  String get renameFolderFailed;
  String get folderOptions;
  String get moveFolder;

  // --- hob menu (long-press / right-click on a row) ------------------------
  String hobMenuLabel(String hob);
  String get pinHob;
  String get unpinHob;
  String get hideHob;
  String get unhideHob;
  String get moveToFolder;
  String get removeFromFolder;
  String get newFolder;
  String get newFolderTitle;
  String get hiddenHobs;
  String hobHidden(String hob);
  String get undo;
  String get hobChangeFailed;
  String get deleteHob;
  String deleteHobTitle(String hob);
  String get deleteHobMessage;
  String hobDeleted(String hob);
  String hobDeleteFailed(String reason);

  // --- hob profile ---------------------------------------------------------
  String get hobProfile;
  String editHob(String hob);
  String get appearance;
  String get blobFaceLabel;
  String get randomizeFace;
  String get shapeLabel;
  String get colorLabel;
  String get byName;
  String get autoLabel;
  String get hobTitleLabel;
  String get hobDescriptionLabel;
  String get hobDescriptionHint;
  String get modelSection;
  String get providerLabel;
  String get modelLabel;
  String get inheritModel;
  String get modelRequired;
  String get soulSection;
  String get profileSection;
  String get editSoul;
  String get soulEmpty;
  String get done;
  String get soulHint;
  String get setupLoadFailed;
  String get confirmModelTitle;
  String get confirmModelFallback;
  String get switchModel;
  String hobSaved(String hob);
  String hobSaveFailed(String reason);
  String get hobSaveRefused;
  String get discardChangesTitle;
  String get discardChanges;
  String get keepEditing;

  // --- new hob -------------------------------------------------------------
  String get newHob;
  String get newHobHint;
  String get newHobNameLabel;
  String get newHobNameHint;
  String get hobHandleLabel;
  String get editHobHandle;
  String get hobHandleHelp;
  String get hobHandleInvalid;
  String get hobHandleTaken;
  String hobCreated(String hob);
  String hobCreateFailed(String reason);

  // --- chat ----------------------------------------------------------------
  String get scheduledJobs;
  String get connectionLost;
  String get reconnectNow;

  // --- offline -------------------------------------------------------------
  String get offlineTitle;

  /// How to get back online: Wi-Fi or mobile data on a phone, a network on
  /// a desktop.
  String offlineHint({required bool phone});
  String get offlineRetry;
  String get offlineChecking;
  String newMessages(int n);
  String get jumpToEnd;
  String get tryAgain;
  String get openingChat;
  String workingOn(String? status);
  String get workingInBackground;
  String activeAgo(String age);
  String writeTo(String hob);
  String get interruptedTag;
  String get copy;
  String get copied;
  String get thinking;
  String get messageHint;
  String get stop;
  String get send;

  // Attachments and sharing
  String get addAttachment;
  String get takePhoto;
  String get choosePhotos;
  String get chooseFiles;
  String get addLink;
  String get pasteImage;
  String get noImageInClipboard;
  String get linkHint;
  String get linkInvalid;
  String get add;
  String get removeAttachment;
  String uploadFailed(Object error);
  String get uploadNoPath;
  String attachmentTooLarge(int mb);
  String pickFailed(Object error);
  String get waitForUploads;
  String get linkOpenFailed;
  String get shareTitle;
  String shareSummary(int count);
  String get shareNoHobs;
  String get modelTooltip;
  String get sessionModelTitle;
  String get sessionModelHint;
  String get hobDefaultTag;
  String get useHobDefaultModel;
  String get sessionModelTag;
  String modelSwitchDeferred(String model);
  String get modelsUnavailable;
  String get reasoningLevel;
  String get chatSettings;
  String get approvalHeading;
  String get approvalScope;
  String get reasoning;
  String get approvalModeTooltip;
  String approvalModeLabel(String mode);
  String approvalModeHint(String mode);
  String approvalTitle(String? tool);
  String get allowOnce;
  String get allowSession;
  String get allowAlways;
  String get deny;
  String get hobAsks;
  String get orOwnAnswer;
  String get answerHint;
  String get skip;
  String get answer;

  /// Short label of a tool family in the activity line, or null to show the
  /// tool's own name.
  String? toolLabel(String tool);

  // --- chat state ----------------------------------------------------------
  String openChatFailed(Object e);
  String recoverFailed(Object e);
  String get chatNotReady;
  String interruptFailed(Object e);
  String reasoningChangeFailed(Object e);
  String modelChangeFailed(Object e);
  String approvalModeChangeFailed(Object e);
  String approvalAnswerFailed(Object e);
  String clarifyAnswerFailed(Object e);
  String preparingTool(String? tool);
  String get unknownError;
  String get interruptedNotice;
  String get replyFailed;

  // --- group chats ---------------------------------------------------------
  String get groupChats;
  String get newGroupChat;
  String get groupPickTitle;
  String get groupPickHint;
  String get groupNameLabel;
  String get create;
  String get groupCreateFailed;
  String groupLoadFailed(String reason);
  String get groupSendUnconfirmed;
  String get groupDisbandUnconfirmed;
  String groupMembers(int n);
  String get groupMessageHint;
  String get groupEmpty;
  String get groupOptions;
  String get renameGroup;
  String get renameGroupTitle;
  String get disbandGroup;
  String get disbandGroupBody;
  String get disband;
  String get groupDisbanded;
  String get you;
  String mention(String handle);
  String memberStateLabel(String state);
  String get roundCapped;
  String get continueRound;
  String turnFailed(String member, String? reason);
  String get turnCancelled;
  String memberAsks(String member);
  String memberFailed(String member);
  String get discardTurn;
  String groupWorking(String members);

  // --- scheduled jobs ------------------------------------------------------
  String get refresh;
  String jobsLoadFailed(Object? e);
  String get noJobs;
  String nextRun(String when);
  String get paused;
  String lastRun(String when);
  String get failedTag;
  String get jobFallback;

  // --- biometric lock ------------------------------------------------------
  /// Lock screen button, e.g. "Unlock with Face ID".
  String unlockWith(BiometricKind kind);

  /// Login screen button, e.g. "Sign in with Face ID".
  String signInWith(BiometricKind kind);

  /// Settings switch, e.g. "Unlock with Face ID".
  String biometricSetting(BiometricKind kind);
  String get biometricSettingHint;

  /// Shown by the system prompt itself.
  String get biometricReason;
  String get locked;
  String get signInWithPassword;
  String get biometricFailed;
  String get biometricUnavailable;

  // --- settings ------------------------------------------------------------
  String get security;
  String get language;
  String get languageSystem;
  String languageSystemNow(String name);

  /// This pack's language, written in that language.
  String get languageName;

  // --- notifications -------------------------------------------------------
  String get notifications;

  /// Settings switch.
  String get notificationsSetting;
  String get notificationsHint;

  /// The system refuses them (permission denied or turned off for the app).
  String get notificationsBlocked;

  /// Body of the notification for a pending approval.
  String notifyApproval(String what);

  /// Body of the notification for a clarify question.
  String notifyClarify(String question);

  /// Body when the finished reply has no text to preview.
  String get notifyReplyDone;

  /// Body of a group chat's notification for a member turn that failed and
  /// waits for the user to retry or drop it.
  String get notifyGroupFailed;

  /// Android notification channel shown in the system settings.
  String get notifyChannelName;
  String get notifyChannelDescription;

  // --- dates ---------------------------------------------------------------
  String get now;
  String get today;
  String get tomorrow;
  String get yesterday;
  String shortDate(DateTime t);
}

class _StringsDelegate extends LocalizationsDelegate<Strings> {
  const _StringsDelegate();

  @override
  bool isSupported(Locale locale) => Strings.supportedLocales.any(
    (l) => l.languageCode == locale.languageCode,
  );

  @override
  Future<Strings> load(Locale locale) {
    final strings = Strings.forLocale(locale);
    Strings.current = strings;
    return SynchronousFuture(strings);
  }

  @override
  bool shouldReload(_StringsDelegate old) => false;
}
