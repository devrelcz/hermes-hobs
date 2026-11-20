import '../state/biometrics.dart';
import 'strings.dart';

/// Czech language pack. Informal voice: the app is on first-name terms.
class StringsCs extends Strings {
  const StringsCs();

  @override
  String get code => 'cs';

  // --- login ---------------------------------------------------------------
  @override
  String get loginSubtitle => 'Přihlášení k Hermes Agent dashboardu';
  @override
  String get serverLabel => 'Server';
  @override
  String get serverInvalid => 'Zadej URL, např. https://hermes.devrel.cz';
  @override
  String get usernameLabel => 'Uživatel';
  @override
  String get passwordLabel => 'Heslo';
  @override
  String get fieldRequired => 'Povinné';
  @override
  String get rememberPassword => 'Zapamatovat heslo';
  @override
  String get signIn => 'Přihlásit';
  @override
  String get savedPasswordExpired =>
      'Uložené heslo už neplatí, přihlas se znovu.';

  // --- errors --------------------------------------------------------------
  @override
  String get errorBadCredentials => 'Neplatné jméno nebo heslo.';
  @override
  String get errorNoPasswordLogin =>
      'Server nepodporuje přihlášení heslem (provider "basic").';
  @override
  String get errorTooManyAttempts => 'Příliš mnoho pokusů, chvíli počkej.';
  @override
  String get errorServerDown => 'Server je nedostupný (503).';
  @override
  String errorServer(String message) => 'Chyba serveru: $message';
  @override
  String errorUnreachable(String message) => 'Server nedostupný: $message';
  @override
  String errorTls(String message) => 'TLS chyba: $message';
  @override
  String get errorTimeout => 'Vypršel časový limit.';
  @override
  String get errorBadServerUrl => 'Neplatná adresa serveru.';
  @override
  String get errorNoSessionCookie => 'Server nevrátil session cookie';

  // --- hob list ------------------------------------------------------------
  @override
  String get hobsTitle => 'Hobíci';
  @override
  String get pickHob => 'Vyber Hobíka vlevo';
  @override
  String get filterAll => 'Vše';
  @override
  String get filterUnread => 'Nepřečtené';
  @override
  String get filterPinned => 'Připnutí';
  @override
  String get filterActive => 'Aktivní';
  @override
  String get filterRecent => 'Nedávno';
  @override
  String get filterOlder => 'Starší';
  @override
  String get account => 'Účet';
  @override
  String get settings => 'Nastavení';
  @override
  String get signOut => 'Odhlásit';
  @override
  String get searchHobs => 'Hledat Hobíky';
  @override
  String get retry => 'Zkusit znovu';
  @override
  String get noHobs => 'Na serveru nejsou žádní Hobíci.';
  @override
  String get noMatches => 'Filtru nic neodpovídá.';
  @override
  String get working => 'pracuje';
  @override
  String get noMessagesYet => 'Zatím bez zpráv';
  @override
  String get connected => 'Připojeno';
  @override
  String get connecting => 'Připojuji…';
  @override
  String get disconnected => 'Odpojeno';
  @override
  String get folderFallback => 'Složka';
  @override
  String get unassigned => 'Nezařazení';
  @override
  String get renameFolder => 'Přejmenovat';
  @override
  String get renameFolderTitle => 'Přejmenovat složku';
  @override
  String get folderNameLabel => 'Název složky';
  @override
  String get save => 'Uložit';
  @override
  String get cancel => 'Zrušit';
  @override
  String get renameFolderFailed =>
      'Složku se nepodařilo přejmenovat. Zkuste to znovu.';
  @override
  String get folderOptions => 'Možnosti složky';
  @override
  String get moveFolder => 'Přesunout složku';

  // --- hob menu ------------------------------------------------------------
  @override
  String hobMenuLabel(String hob) => 'Možnosti: $hob';
  @override
  String get pinHob => 'Připnout';
  @override
  String get unpinHob => 'Odepnout';
  @override
  String get hideHob => 'Skrýt';
  @override
  String get unhideHob => 'Zobrazit v seznamu';
  @override
  String get moveToFolder => 'Přesunout do složky';
  @override
  String get removeFromFolder => 'Vyjmout ze složky';
  @override
  String get newFolder => 'Nová složka…';
  @override
  String get newFolderTitle => 'Nová složka';
  @override
  String get hiddenHobs => 'Skrytí Hobíci';
  @override
  String hobHidden(String hob) => '$hob je skrytý';
  @override
  String get undo => 'Zpět';
  @override
  String get hobChangeFailed => 'Změnu se nepodařilo uložit. Zkuste to znovu.';

  // --- hob profile ---------------------------------------------------------
  @override
  String get hobProfile => 'Profil Hobíka';
  @override
  String editHob(String hob) => 'Upravit profil: $hob';
  @override
  String get appearance => 'Vzhled';
  @override
  String get blobFaceLabel => 'Obličej';
  @override
  String get randomizeFace => 'Jiný obličej';
  @override
  String get shapeLabel => 'Klasický tvar';
  @override
  String get colorLabel => 'Barva';
  @override
  String get byName => 'Podle jména';
  @override
  String get autoLabel => 'Auto';
  @override
  String get hobTitleLabel => 'Název';
  @override
  String get hobDescriptionLabel => 'Popis';
  @override
  String get hobDescriptionHint => 'S čím má Hobík pomáhat?';
  @override
  String get modelSection => 'Model';
  @override
  String get providerLabel => 'Poskytovatel';
  @override
  String get modelLabel => 'Model';
  @override
  String get inheritModel => 'Zdědit z výchozího profilu';
  @override
  String get modelRequired => 'Vyplňte poskytovatele i model.';
  @override
  String get soulSection => 'SOUL.md';
  @override
  String get soulHint => 'Persona a trvalé pokyny Hobíka';
  @override
  String get setupLoadFailed =>
      'Model a SOUL.md se nepodařilo načíst. Zbytek profilu upravit lze.';
  @override
  String get confirmModelTitle => 'Přepnout model?';
  @override
  String get confirmModelFallback => 'Server žádá potvrzení změny modelu.';
  @override
  String get switchModel => 'Přepnout';
  @override
  String hobSaved(String hob) => 'Profil $hob je uložený';
  @override
  String hobSaveFailed(String reason) => 'Uložení se nepovedlo: $reason';
  @override
  String get hobSaveRefused => 'Server změnu odmítl. Zkuste to znovu.';
  @override
  String get discardChangesTitle => 'Zahodit neuložené změny?';
  @override
  String get discardChanges => 'Zahodit';
  @override
  String get keepEditing => 'Pokračovat';

  // --- chat ----------------------------------------------------------------
  @override
  String get scheduledJobs => 'Naplánované úlohy';
  @override
  String get connectionLost =>
      'Spojení se serverem přerušeno, připojuji znovu…';
  @override
  String get reconnectNow => 'Teď';
  @override
  String newMessages(int n) => switch (n) {
    1 => '1 nová',
    2 || 3 || 4 => '$n nové',
    _ => '$n nových',
  };
  @override
  String get jumpToEnd => 'Na konec';
  @override
  String get tryAgain => 'Znovu';
  @override
  String get openingChat => 'Otevírám chat s Hobíkem…';
  @override
  String workingOn(String? status) =>
      status != null ? 'pracuje · $status' : 'pracuje…';
  @override
  String get workingInBackground => 'pracuje na pozadí';
  @override
  String activeAgo(String age) => 'aktivní $age';
  @override
  String writeTo(String hob) => 'Napiš zprávu pro $hob';
  @override
  String get interruptedTag => 'přerušeno';
  @override
  String get copy => 'Kopírovat';
  @override
  String get copied => 'Zkopírováno';
  @override
  String get thinking => 'Přemýšlí…';
  @override
  String get messageHint => 'Napiš zprávu';
  @override
  String get stop => 'Zastavit';
  @override
  String get send => 'Odeslat';

  // Attachments and sharing
  @override
  String get addAttachment => 'Přidat přílohu';
  @override
  String get takePhoto => 'Vyfotit';
  @override
  String get choosePhotos => 'Vybrat fotky';
  @override
  String get chooseFiles => 'Vybrat soubory';
  @override
  String get addLink => 'Přidat odkaz';
  @override
  String get pasteImage => 'Vložit obrázek ze schránky';
  @override
  String get noImageInClipboard => 'Ve schránce není žádný obrázek.';
  @override
  String get linkHint => 'https://…';
  @override
  String get linkInvalid =>
      'Zadej celou adresu začínající http:// nebo https://';
  @override
  String get add => 'Přidat';
  @override
  String get removeAttachment => 'Odebrat přílohu';
  @override
  String uploadFailed(Object error) => 'Nahrání selhalo: $error';
  @override
  String get uploadNoPath => 'Server nevrátil cestu k nahranému souboru.';
  @override
  String attachmentTooLarge(int mb) => 'Soubor je větší než $mb MB.';
  @override
  String pickFailed(Object error) => 'Výběr se nepodařilo otevřít: $error';
  @override
  String get waitForUploads => 'Počkej, až se přílohy nahrají';
  @override
  String get linkOpenFailed => 'Odkaz se nepodařilo otevřít.';
  @override
  String get shareTitle => 'Poslat Hobíkovi';
  @override
  String shareSummary(int count) => switch (count) {
    1 => '1 položka se vloží do konverzace. Odeslání je na tobě.',
    2 ||
    3 ||
    4 => '$count položky se vloží do konverzace. Odeslání je na tobě.',
    _ => '$count položek se vloží do konverzace. Odeslání je na tobě.',
  };
  @override
  String get shareNoHobs => 'Zatím tu nejsou žádní Hobíci.';
  @override
  String get modelTooltip => 'Model téhle konverzace';
  @override
  String get sessionModelTitle => 'Model téhle konverzace';
  @override
  String get sessionModelHint =>
      'Platí jen pro tuhle konverzaci. Hobík si nechá svůj výchozí model.';
  @override
  String get hobDefaultTag => 'Výchozí model Hobíka';
  @override
  String get useHobDefaultModel => 'Použít výchozí model Hobíka';
  @override
  String get sessionModelTag => 'jen tahle konverzace';
  @override
  String modelSwitchDeferred(String model) =>
      '$model převezme po dokončení rozepsané odpovědi.';
  @override
  String get modelsUnavailable => 'Seznam modelů se nepodařilo načíst.';
  @override
  String get reasoningLevel => 'Úroveň uvažování';
  @override
  String get reasoning => 'Uvažování';
  @override
  String get approvalModeTooltip =>
      'Schvalování nebezpečných příkazů (platí pro celého Hobíka)';
  @override
  String approvalModeLabel(String mode) => switch (mode) {
    'manual' => 'Ručně',
    'smart' => 'Chytře',
    'off' => 'Bez ptaní',
    _ => 'Schvalování',
  };
  @override
  String approvalModeHint(String mode) => switch (mode) {
    'manual' => 'Na každý nebezpečný příkaz se zeptá',
    'smart' => 'Bezpečné schválí sám, ptá se jen u rizikových',
    'off' => 'Nic neschvaluje, spouští vše hned',
    _ => mode,
  };
  @override
  String approvalTitle(String? tool) =>
      'Hobík žádá o schválení${tool != null ? ' ($tool)' : ''}';
  @override
  String get allowOnce => 'Povolit jednou';
  @override
  String get allowSession => 'Povolit v konverzaci';
  @override
  String get allowAlways => 'Povolit vždy';
  @override
  String get deny => 'Zamítnout';
  @override
  String get hobAsks => 'Hobík se ptá';
  @override
  String get orOwnAnswer => 'nebo vlastní odpověď';
  @override
  String get answerHint => 'Odpověď';
  @override
  String get skip => 'Přeskočit';
  @override
  String get answer => 'Odpovědět';

  @override
  String? toolLabel(String tool) => switch (tool) {
    'message_agent' || 'send_message' => 'zpráva agentovi',
    'skill_view' || 'skills_list' || 'skill_load' => 'skill',
    'terminal' || 'execute_code' => 'příkaz',
    'web_search' => 'hledání na webu',
    'web_extract' || 'browser_navigate' => 'web',
    'read_file' || 'search_files' => 'soubory',
    'write_file' || 'patch' => 'úprava souboru',
    'clarify' => 'dotaz',
    'cronjob' => 'naplánovaná úloha',
    'todo' => 'úkoly',
    'memory' => 'paměť',
    'delegate_task' => 'delegace',
    _ => null,
  };

  // --- chat state ----------------------------------------------------------
  @override
  String openChatFailed(Object e) => 'Nepodařilo se otevřít konverzaci: $e';
  @override
  String recoverFailed(Object e) => 'Obnovení po výpadku spojení selhalo: $e';
  @override
  String get chatNotReady => 'Konverzace není připravená.';
  @override
  String interruptFailed(Object e) => 'Přerušení selhalo: $e';
  @override
  String modelChangeFailed(Object e) => 'Přepnutí modelu selhalo: $e';
  @override
  String reasoningChangeFailed(Object e) =>
      'Změna úrovně uvažování selhala: $e';
  @override
  String approvalModeChangeFailed(Object e) =>
      'Změna režimu schvalování selhala: $e';
  @override
  String approvalAnswerFailed(Object e) => 'Odpověď na schválení selhala: $e';
  @override
  String clarifyAnswerFailed(Object e) => 'Odpověď na dotaz selhala: $e';
  @override
  String preparingTool(String? tool) => 'Připravuje ${tool ?? 'nástroj'}…';
  @override
  String get unknownError => 'Neznámá chyba';
  @override
  String get interruptedNotice => 'Přerušeno';
  @override
  String get replyFailed => 'Odpověď skončila chybou';

  // --- group chats ---------------------------------------------------------
  @override
  String get groupChats => 'Skupinové chaty';
  @override
  String get newGroupChat => 'Nový skupinový chat';
  @override
  String get groupPickTitle => 'Nový skupinový chat';
  @override
  String get groupPickHint => 'Vyber 2 až 6 Hobíků, kteří budou spolu mluvit.';
  @override
  String get groupNameLabel => 'Název skupiny';
  @override
  String get create => 'Vytvořit';
  @override
  String get groupCreateFailed => 'Skupinový chat se nepodařilo vytvořit.';
  @override
  String groupLoadFailed(String reason) =>
      'Skupinový chat se nepodařilo načíst: $reason';
  @override
  String get groupSendUnconfirmed =>
      'Server zprávu nepotvrdil. Zkontroluj chat a případně ji pošli znovu.';
  @override
  String get groupDisbandUnconfirmed =>
      'Server ukončení skupiny nepotvrdil. Zkus to znovu.';
  @override
  String groupMembers(int n) => switch (n) {
    1 => '1 Hobík',
    >= 2 && <= 4 => '$n Hobíci',
    _ => '$n Hobíků',
  };
  @override
  String get groupMessageHint => 'Napiš skupině, @zmínkou úkol přidělíš';
  @override
  String get groupEmpty => 'Napiš první zprávu, odpoví ti všichni Hobíci.';
  @override
  String get groupOptions => 'Možnosti skupiny';
  @override
  String get renameGroup => 'Přejmenovat';
  @override
  String get renameGroupTitle => 'Přejmenovat skupinu';
  @override
  String get disbandGroup => 'Ukončit skupinu';
  @override
  String get disbandGroupBody =>
      'Skupinový chat se ukončí na všech zařízeních. Konverzace Hobíků v '
      'něm skončí a nedá se obnovit.';
  @override
  String get disband => 'Ukončit';
  @override
  String get groupDisbanded => 'Tento skupinový chat byl ukončen.';
  @override
  String get you => 'Ty';
  @override
  String mention(String handle) => 'Oslovit @$handle';
  @override
  String memberStateLabel(String state) => switch (state) {
    'queued' => 've frontě',
    'working' => 'pracuje',
    'replied' => 'odpověděl',
    'passed' => 'mlčí',
    'failed' => 'selhal',
    'cancelled' => 'zastaven',
    _ => 'čeká',
  };
  @override
  String get roundCapped => 'Hobíci došli na limit kol.';
  @override
  String get continueRound => 'Pokračovat';
  @override
  String turnFailed(String member, String? reason) =>
      reason == null || reason.isEmpty
      ? '$member neodpověděl.'
      : '$member neodpověděl: $reason';
  @override
  String get turnCancelled => 'Zastaveno.';
  @override
  String memberAsks(String member) => '$member žádá o schválení';
  @override
  String memberFailed(String member) => 'Tah Hobíka $member selhal';
  @override
  String get discardTurn => 'Zahodit';
  @override
  String groupWorking(String members) => 'pracuje: $members';

  // --- scheduled jobs ------------------------------------------------------
  @override
  String get refresh => 'Obnovit';
  @override
  String jobsLoadFailed(Object? e) => 'Úlohy se nepodařilo načíst: $e';
  @override
  String get noJobs => 'Hobík nemá žádné naplánované úlohy.';
  @override
  String nextRun(String when) => 'Další běh: $when';
  @override
  String get paused => 'Pozastaveno';
  @override
  String lastRun(String when) => 'Poslední běh: $when';
  @override
  String get failedTag => 'chyba';
  @override
  String get jobFallback => 'Úloha';

  // --- biometric lock ------------------------------------------------------
  @override
  String unlockWith(BiometricKind kind) => switch (kind) {
    BiometricKind.faceId => 'Odemknout přes Face ID',
    BiometricKind.touchId => 'Odemknout přes Touch ID',
    BiometricKind.fingerprint => 'Odemknout otiskem prstu',
    BiometricKind.face => 'Odemknout obličejem',
    BiometricKind.generic => 'Odemknout biometrií',
  };
  @override
  String signInWith(BiometricKind kind) => switch (kind) {
    BiometricKind.faceId => 'Přihlásit přes Face ID',
    BiometricKind.touchId => 'Přihlásit přes Touch ID',
    BiometricKind.fingerprint => 'Přihlásit otiskem prstu',
    BiometricKind.face => 'Přihlásit obličejem',
    BiometricKind.generic => 'Přihlásit biometrií',
  };
  @override
  String biometricSetting(BiometricKind kind) => switch (kind) {
    BiometricKind.faceId => 'Odemykat přes Face ID',
    BiometricKind.touchId => 'Odemykat přes Touch ID',
    BiometricKind.fingerprint => 'Odemykat otiskem prstu',
    BiometricKind.face => 'Odemykat obličejem',
    BiometricKind.generic => 'Odemykat biometrií',
  };
  @override
  String get biometricSettingHint =>
      'Při spuštění a po minutě mimo aplikaci. Přihlášení bez psaní hesla.';
  @override
  String get biometricReason => 'Ověř, že jsi to ty';
  @override
  String get locked => 'Zamčeno';
  @override
  String get signInWithPassword => 'Přihlásit se heslem';
  @override
  String get biometricFailed => 'Ověření se nepovedlo, zkus to znovu.';
  @override
  String get biometricUnavailable =>
      'Biometrie teď není k dispozici. Přihlas se heslem.';

  // --- settings ------------------------------------------------------------
  @override
  String get security => 'Zabezpečení';
  @override
  String get language => 'Jazyk';
  @override
  String get languageSystem => 'Podle zařízení';
  @override
  String languageSystemNow(String name) => 'Teď: $name';
  @override
  String get languageName => 'Čeština';

  // --- notifications -------------------------------------------------------
  @override
  String get notifications => 'Oznámení';
  @override
  String get notificationsSetting => 'Upozorňovat na Hobíky';
  @override
  String get notificationsHint =>
      'Když Hobík dopíše odpověď nebo čeká na tvé schválení či odpověď, '
      'zatímco je aplikace na pozadí.';
  @override
  String get notificationsBlocked =>
      'Oznámení má tahle aplikace vypnutá v nastavení systému.';
  @override
  String notifyApproval(String what) => 'Žádá o schválení: $what';
  @override
  String notifyClarify(String question) => 'Ptá se: $question';
  @override
  String get notifyReplyDone => 'Dopsal odpověď.';
  @override
  String get notifyGroupFailed =>
      'Odpověď se nepovedla. Zkusit znovu, nebo zahodit?';
  @override
  String get notifyChannelName => 'Hobíci';
  @override
  String get notifyChannelDescription =>
      'Dokončené odpovědi a otázky od tvých Hobíků a ze skupinových chatů';

  // --- dates ---------------------------------------------------------------
  @override
  String get now => 'teď';
  @override
  String get today => 'dnes';
  @override
  String get tomorrow => 'zítra';
  @override
  String get yesterday => 'včera';
  @override
  String shortDate(DateTime t) => '${t.day}. ${t.month}.';
}
