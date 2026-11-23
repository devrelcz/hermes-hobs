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
  String get welcomeTitle => 'Vítej u Hobíků';
  @override
  String get welcomeWhat =>
      'Každý Hobík je jeden agent na tvém serveru s vlastním úkolem a pamětí.';
  @override
  String get welcomeTalk =>
      'Piš mu jako v chatu. Odpoví a umí sáhnout po nástrojích.';
  @override
  String get welcomeSafe =>
      'Než spustí něco riskantního, dá ti to ke schválení.';
  @override
  String get welcomeStart => 'Začít';
  @override
  String get serverLabel => 'Server';
  @override
  String get serverInvalid => 'Zadej URL, např. https://hermes.example.com';
  @override
  String get usernameLabel => 'Uživatel';
  @override
  String get passwordLabel => 'Heslo';
  @override
  String get showPassword => 'Zobrazit heslo';
  @override
  String get hidePassword => 'Skrýt heslo';
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
  String get errorNotConnected => 'Aplikace není připojená k serveru.';
  @override
  String get errorConnectionClosed => 'Spojení se serverem se přerušilo.';
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
  String get markAllRead => 'Označit vše jako přečtené';
  @override
  String get signOut => 'Odhlásit';
  @override
  String get accounts => 'Účty';
  @override
  String get addServer => 'Přidat server';
  @override
  String get manageAccounts => 'Spravovat účty';
  @override
  String signOutFrom(String name) => 'Odhlásit z $name';
  @override
  String get accountName => 'Název účtu';
  @override
  String get accountNameHint => 'např. Doma, Práce';
  @override
  String get accountColor => 'Barva';
  @override
  String accountColorName(int i) => const [
    'zelená',
    'fialová',
    'oranžová',
    'modrá',
    'růžová',
    'jantarová',
  ][i % 6];
  @override
  String get signInAndSwitch => 'Přihlásit a přepnout';
  @override
  String get addServerHint => 'Účet se uloží, až se přihlášení povede.';
  @override
  String get tryDemo => 'Vyzkoušet demo bez serveru';
  @override
  String get demoAccountName => 'Demo';
  @override
  String get scanQr => 'Naskenovat QR kód serveru';
  @override
  String get enterManually => 'Zadat údaje ručně';
  @override
  String get back => 'Zpět';
  @override
  String get scanTitle => 'Naskenujte QR kód';
  @override
  String get scanInstruction =>
      'Na serveru spusťte ./pair.sh a namiřte fotoaparát na kód, který ukáže.';
  @override
  String get scanNotPairing => 'Tohle není párovací kód Hermes.';
  @override
  String get scanNewerVersion =>
      'Kód je pro novější verzi aplikace. Aktualizujte Hermes Hobs.';
  @override
  String get scanNoPermission =>
      'Fotoaparát není povolený. Povolte ho pro Hermes Hobs v nastavení systému, nebo údaje zadejte ručně.';
  @override
  String get scanNoCamera =>
      'Fotoaparát tu nejde použít. Zadejte přihlašovací údaje ručně.';
  @override
  String get scanTorchOn => 'Zapnout světlo';
  @override
  String get scanTorchOff => 'Vypnout světlo';
  @override
  String get otherServer => 'Jiný server';
  @override
  String get savedAccounts => 'Uložené účty';
  @override
  String switchedTo(String name) => 'Přepnuto na $name';
  @override
  String get editAccount => 'Upravit účet';
  @override
  String get newPassword => 'Nové heslo';
  @override
  String get newPasswordHint => 'Prázdné ponechá uložené heslo.';
  @override
  String get accountSaved => 'Účet uložen';
  @override
  String get removeAccount => 'Odebrat účet';
  @override
  String removeAccountTitle(String name) => 'Odebrat $name?';
  @override
  String get removeAccountBody =>
      'Z tohoto zařízení zmizí uložené heslo a přihlášení. Hobíci na serveru zůstanou.';
  @override
  String get remove => 'Odebrat';
  @override
  String get accountActive => 'Aktivní';
  @override
  String get accountsHint =>
      'Připojený je jen aktivní účet a jen ten posílá upozornění.';
  @override
  String get dragToReorder => 'Přetažením změníte pořadí';
  @override
  String get searchHobs => 'Hledat Hobíky';
  @override
  String get clearSearch => 'Vymazat hledání';
  @override
  String get searchModels => 'Hledat model';
  @override
  String get noModelMatches => 'Žádný model neodpovídá hledání.';
  @override
  String get retry => 'Zkusit znovu';
  @override
  String get noHobs => 'Založ prvního, dej mu jméno a napiš, s čím má pomáhat.';
  @override
  String get noHobsTitle => 'Zatím tu není žádný Hobík';
  @override
  String get hobsLoadFailed => 'Hobíky se nepodařilo načíst';
  @override
  String get showAllHobs => 'Ukázat všechny Hobíky';
  @override
  String get pickHobHint => 'Nového založíš přes + nahoře v seznamu.';
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
  @override
  String get deleteHob => 'Smazat';
  @override
  String deleteHobTitle(String hob) => 'Smazat Hobíka $hob?';
  @override
  String get deleteHobMessage =>
      'Ze serveru zmizí jeho profil i s nastavením, pamětí, dovednostmi a konverzacemi. Nejde to vrátit.';
  @override
  String hobDeleted(String hob) => 'Hobík $hob je smazaný';
  @override
  String get duplicateHob => 'Duplikovat';
  @override
  String hobCopyTitle(String hob) => '$hob (kopie)';
  @override
  String hobDuplicating(String hob) => 'Kopíruji Hobíka $hob…';
  @override
  String hobDuplicated(String copy) => 'Hobík $copy je vytvořený';
  @override
  String hobDuplicateFailed(String reason) =>
      'Hobíka se nepodařilo zkopírovat: $reason';
  @override
  String get hobDuplicateNoName => 'Pro kopii není volné jméno.';
  @override
  String get hobGroupsMenu => 'Skupinové chaty…';
  @override
  String hobGroupsTitle(String hob) => 'Skupinové chaty Hobíka $hob';
  @override
  String get hobNoGroups => 'Hobík zatím není v žádném skupinovém chatu.';
  @override
  String newGroupWith(String hob) => 'Nová skupina s Hobíkem $hob';
  @override
  String get hobGroupsHint =>
      'Členy existující skupiny server měnit nedovoluje. Pro jiné složení '
      'založ novou skupinu.';
  @override
  String hobDeleteFailed(String reason) =>
      'Hobíka se nepodařilo smazat: $reason';

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
  String get profileSection => 'Jméno a popis';
  @override
  String get editSoul => 'Upravit';
  @override
  String get soulEmpty =>
      'Zatím prázdné. Napiš, kdo Hobík je a jak má pracovat.';
  @override
  String get done => 'Hotovo';
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

  // --- new hob -------------------------------------------------------------
  @override
  String get newHob => 'Nový Hobík';
  @override
  String get newHobHint =>
      'Převezme nastavení, dovednosti a přihlášení výchozího profilu. Model a SOUL.md jde později upravit v jeho profilu.';
  @override
  String get newHobNameLabel => 'Jméno';
  @override
  String get newHobNameHint => 'Třeba Účetní Péťa';
  @override
  String get hobHandleLabel => 'Identifikátor';
  @override
  String get editHobHandle => 'Upravit identifikátor';
  @override
  String get hobHandleHelp =>
      'Pro @zmínky a název profilu na serveru. Později už nejde změnit.';
  @override
  String get hobHandleInvalid =>
      'Jen malá písmena bez diakritiky, čísla, - a _. Na začátku písmeno nebo číslo.';
  @override
  String get hobHandleTaken => 'Tenhle identifikátor už má jiný Hobík.';
  @override
  String hobCreated(String hob) => 'Hobík $hob je na světě';
  @override
  String hobCreateFailed(String reason) =>
      'Hobíka se nepodařilo vytvořit: $reason';

  // --- chat ----------------------------------------------------------------
  @override
  String get scheduledJobs => 'Naplánované úlohy';
  @override
  String get connectionLost =>
      'Spojení se serverem přerušeno, připojuji znovu…';
  @override
  String get reconnectNow => 'Teď';

  // --- offline -------------------------------------------------------------
  @override
  String get offlineTitle => 'Nejste připojeni k internetu';
  @override
  String offlineHint({required bool phone}) => phone
      ? 'Zapněte Wi-Fi nebo mobilní data.'
      : 'Připojte se k Wi-Fi nebo k síti.';
  @override
  String get offlineRetry => 'Zkusit znovu';
  @override
  String get offlineChecking => 'Ověřuji…';
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
  String activeSince(DateTime t, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(t);
    if (d.inMinutes < 1) return 'aktivní právě teď';
    if (d.inHours < 1) return 'aktivní před ${d.inMinutes} min';
    if (d.inDays < 1) return 'aktivní před ${d.inHours} h';
    if (d.inDays == 1) return 'aktivní včera';
    if (d.inDays < 7) return 'aktivní před ${d.inDays} dny';
    return 'naposledy aktivní ${shortDate(t)}';
  }

  @override
  String get chatMenu => 'Další možnosti';
  @override
  String get a11yPinned => 'připnutý';
  @override
  String get a11yUnread => 'nepřečteno';
  @override
  String messageFrom(String who) => '$who:';
  @override
  String get toolsUsed => 'Použité nástroje';
  @override
  String get searchInChat => 'Hledat v konverzaci';
  @override
  String get searchNone => 'Nic';
  @override
  String searchCount(int at, int of) => '$at z $of';
  @override
  String get searchOlder => 'Starší výskyt';
  @override
  String get searchNewer => 'Novější výskyt';
  @override
  String get linkLabel => 'Odkaz';
  @override
  String get fileLabel => 'Soubor';
  @override
  String get resizeList => 'Šířka seznamu, táhni do stran';
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
  String get chatSettings => 'Nastavení konverzace';
  @override
  String get approvalHeading => 'Schvalování příkazů';
  @override
  String get approvalScope =>
      'Platí pro celého Hobíka, ne jen pro tuhle konverzaci.';
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
  String get approvalWaiting => 'Čeká na tvé schválení';
  @override
  String get clarifyWaiting => 'Odpověz a bude pokračovat';
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
  String get groupPickTitle => 'Nová skupina';
  @override
  String get groupPickHint => 'Vyber 2 až 6 Hobíků, kteří budou spolu mluvit.';
  @override
  String get groupNameLabel => 'Název skupiny';
  @override
  String groupPickCount(int picked, int max) =>
      'Vybráno $picked z nejvýš $max, aspoň 2.';
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
  String get memberWaits => 'čeká na tebe';
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
  @override
  String get newJob => 'Nová úloha';
  @override
  String get jobName => 'Název';
  @override
  String get jobNameHint => 'Ranní přehled';
  @override
  String get jobPrompt => 'Co má Hobík udělat';
  @override
  String get jobPromptHint =>
      'Projdi nepřečtené e-maily a pošli mi pět nejdůležitějších.';
  @override
  String get whenToRun => 'Kdy spouštět';
  @override
  String get freqOnce => 'Jednou, za…';
  @override
  String get freqHourly => 'Každou hodinu';
  @override
  String get freqDaily => 'Každý den';
  @override
  String get freqWeekdays => 'Ve všední dny';
  @override
  String get freqWeekly => 'Každý týden';
  @override
  String get freqMonthly => 'Každý měsíc';
  @override
  String get freqInterval => 'Opakovaně po…';
  @override
  String get freqAdvanced => 'Vlastní (cron)';
  @override
  String get atTime => 'V čase';
  @override
  String get onDay => 'Den';
  @override
  String get dayOfMonth => 'Den v měsíci';
  @override
  String get inHowLong => 'Za';
  @override
  String get everyHowOften => 'Každých';
  @override
  String get unitMinutes => 'minut';
  @override
  String get unitHours => 'hodin';
  @override
  String get unitDays => 'dní';
  @override
  List<String> get weekdaysShort => const [
    'po',
    'út',
    'st',
    'čt',
    'pá',
    'so',
    'ne',
  ];
  @override
  String get cronExpression => 'Cron výraz';
  @override
  String get cronInvalid => 'Zadej pět polí, třeba 0 9 * * 1-5.';
  @override
  String get numberInvalid => 'Zadej celé číslo od 1.';
  @override
  String get stopAfter => 'Skončit po počtu běhů';
  @override
  String get stopAfterHelper => 'Prázdné pole znamená bez konce.';
  @override
  String get deliverTo => 'Kam poslat výsledek';
  @override
  String get deliverHistory => 'Jen do historie běhů';
  @override
  String deliverChat(String hob) =>
      'Do chatu Hobíka $hob, který na výsledek odpoví';
  @override
  String get continuity => 'Navazovat na předchozí běh';
  @override
  String get continuityHelper =>
      'Každý běh uvidí výstup toho minulého, takže nehlásí nic dvakrát.';
  @override
  String get createJob => 'Vytvořit úlohu';
  @override
  String jobCreated(String name) => 'Úloha $name je naplánovaná';
  @override
  String get jobCreateFailed => 'Úlohu se nepodařilo vytvořit.';
  @override
  String get runNow => 'Spustit teď';
  @override
  String get runStarted => 'Úloha běží';
  @override
  String get runningNow => 'Právě běží';
  @override
  String get jobOn => 'Zapnuto';
  @override
  String jobUpdateFailed(Object? e) => 'Úlohu se nepodařilo změnit: $e';
  @override
  String get deleteJob => 'Smazat úlohu';
  @override
  String deleteJobTitle(String name) => 'Smazat úlohu $name?';
  @override
  String get deleteJobMessage =>
      'Úloha zmizí ze serveru a už se nespustí. Vrátit to nepůjde.';
  @override
  String get jobDeleted => 'Úloha je smazaná';
  @override
  String get scheduleLabel => 'Plán';
  @override
  String get resultLabel => 'Výsledek';
  @override
  String chatWith(String hob) => 'Chat Hobíka $hob';
  @override
  String repeatProgress(int done, int times) => 'Proběhlo $done z $times';
  @override
  String get promptLabel => 'Zadání';
  @override
  String get lastErrorLabel => 'Poslední chyba';
  @override
  String get lastRunLabel => 'Poslední běh';
  @override
  String get showMore => 'Zobrazit vše';
  @override
  String get showLess => 'Zobrazit méně';
  @override
  String get runHistory => 'Historie běhů';
  @override
  String get noRuns => 'Úloha ještě neběžela.';
  @override
  String runsLoadFailed(Object? e) => 'Historii se nepodařilo načíst: $e';
  @override
  String runDuration(String d) => 'trvalo $d';
  @override
  String toolCallCount(int n) => switch (n) {
    1 => '1 nástroj',
    >= 2 && <= 4 => '$n nástroje',
    _ => '$n nástrojů',
  };
  @override
  String get scheduledRun => 'Naplánovaná úloha';
  @override
  String scheduledRunPrompt(String job) => 'Naplánovaná úloha: $job';
  @override
  String messageFromHob(String? sender) =>
      sender == null ? 'Zpráva od jiného Hobíka' : 'Zpráva od $sender';
  @override
  String replyTo(String? sender) =>
      sender == null ? 'Odpověď' : 'Odpověď pro $sender';
  @override
  String get withReply => 's odpovědí';
  @override
  String get delegationDone => 'Úloha na pozadí je hotová';
  @override
  String get processDone => 'Proces na pozadí skončil';

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
  String get about => 'O aplikaci';
  @override
  String get appVersion => 'Verze';
  @override
  String get signedInAs => 'Přihlášen jako';
  @override
  String get licenses => 'Licence';
  @override
  String get licensesHint => 'Písmo Geist a knihovny s otevřeným kódem';
  @override
  String get unofficialApp => 'Neoficiální komunitní aplikace';
  @override
  String get unofficialAppHint =>
      'Nevytváří ji, nepodporuje ani neschvaluje Nous Research, autoři '
      'Hermes Agent.';
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
  String weekday(int day) => const [
    'pondělí',
    'úterý',
    'středa',
    'čtvrtek',
    'pátek',
    'sobota',
    'neděle',
  ][day - 1];
  @override
  String shortDate(DateTime t) => '${t.day}. ${t.month}.';
}
