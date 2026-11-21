import 'fake_hermes_server.dart';

/// Demo mode: the app's own stand-in for a Hermes dashboard, so people
/// without a server (and Google Play's reviewers) can try the app. It runs
/// [FakeHermesServer] on the loopback interface with the demo data from the
/// README screenshots; nothing leaves the device.
///
/// A demo account stores [url] as its server address. The port changes on
/// every start, so the app asks [baseUrl] for the real address each time it
/// connects. The demo starts fresh with every app start.
class DemoHermes {
  DemoHermes._();

  /// The server address a demo account is saved with.
  static const url = 'demo://hermes';
  static const username = 'u';
  static const password = 'p';

  static bool isDemo(String serverUrl) => serverUrl.trim() == url;

  static Future<FakeHermesServer>? _starting;

  /// The address of the running demo server, starting it on first use.
  static Future<Uri> baseUrl() async {
    final server = await (_starting ??= _start());
    return server.baseUrl;
  }

  static Future<FakeHermesServer> _start() async {
    final server = seedDemo(FakeHermesServer());
    await server.start();
    return server;
  }
}

/// Fills [server] with the demo Hobs, chats and group chat.
FakeHermesServer seedDemo(FakeHermesServer server) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Map<String, dynamic> hob(
    String name,
    String title, {
    required String color,
    required String shape,
    String? section,
    bool pinned = false,
    required String preview,
    required int minutesAgo,
    String description = '',
  }) => {
    'name': name,
    'description': description,
    'ui_meta': {
      'hermes-bots': {
        'title': title,
        'color': color,
        'shape': shape,
        'pinned': ?(pinned ? true : null),
        'sectionId': ?(section == null ? null : 'sec-${section.toLowerCase()}'),
        'sectionName': ?section,
      },
    },
    'canonical_session': {
      'id': 'botchat-$name',
      'resolved_id': 'botchat-$name',
      'preview': preview,
      'last_active': now - minutesAgo * 60,
      'message_count': 12,
    },
  };

  server.roster = [
    hob(
      'research',
      'Researcher',
      color: '#F0997B',
      shape: 'circle',
      section: 'Daily',
      pinned: true,
      preview: 'Three sources agree on the Q3 numbers.',
      minutesAgo: 2,
      description: 'Digs up sources and checks facts.',
    ),
    hob(
      'mail',
      'Inbox',
      color: '#7BB4F0',
      shape: 'squircle',
      section: 'Daily',
      preview: 'Drafted replies to 4 threads, waiting for you.',
      minutesAgo: 14,
    ),
    hob(
      'ops',
      'Ops',
      color: '#8FD19E',
      shape: 'hexagon',
      section: 'Work',
      preview: 'Nightly backup finished in 3 min 12 s.',
      minutesAgo: 47,
    ),
    hob(
      'writer',
      'Writer',
      color: '#C59BF0',
      shape: 'cloud',
      section: 'Work',
      preview: 'Second draft of the launch post is ready.',
      minutesAgo: 95,
    ),
    hob(
      'analyst',
      'Analyst',
      color: '#F0D27B',
      shape: 'triangle',
      section: 'Work',
      preview: 'Churn dropped 0.4 pp after the pricing change.',
      minutesAgo: 180,
    ),
    hob(
      'chef',
      'Chef',
      color: '#F07B9B',
      shape: 'drop',
      section: 'Home',
      preview: 'Shopping list for the week is in Notes.',
      minutesAgo: 60 * 20,
    ),
    hob(
      'travel',
      'Travel',
      color: '#7BE0D8',
      shape: 'pill',
      section: 'Home',
      preview: 'Found 3 trains to Vienna under 40 EUR.',
      minutesAgo: 60 * 30,
    ),
  ];

  server.history = [
    {
      'role': 'user',
      'text': 'How did Q3 revenue compare with Q2? Check at least two sources.',
      'timestamp': now - 600,
    },
    {'role': 'tool', 'name': 'web_search', 'context': 'Q3 2026 revenue report'},
    {'role': 'tool', 'name': 'read_file', 'context': 'finance/q3-summary.xlsx'},
    {
      'role': 'assistant',
      'text':
          'Q3 revenue was **12.4 M EUR**, up **8 %** on Q2 (11.5 M EUR).\n\n'
          '- The finance summary and the investor letter give the same total.\n'
          '- Most of the growth came from subscriptions (+11 %).\n'
          '- One-off services fell slightly (-3 %).',
      'timestamp': now - 540,
    },
    {
      'role': 'user',
      'text': 'Great. Ask @analyst to chart it for Monday.',
      'timestamp': now - 180,
    },
    {'role': 'tool', 'name': 'message_agent', 'context': '@analyst'},
    {
      'role': 'assistant',
      'text':
          'Done. Analyst will have the chart ready by Monday 9:00 and post it '
          'in this chat.',
      'timestamp': now - 120,
    },
  ];

  const room = 'room-launch';
  server.rooms[room] = {
    'room_id': room,
    'name': 'Launch plan',
    'members': [
      for (final p in ['research', 'writer', 'analyst'])
        {
          'member_id': p,
          'profile': p,
          'target': {'kind': 'local', 'profile': p},
        },
    ],
    'authority_epoch': 1,
    'created_at': now - 3600,
    'updated_at': now - 60,
  };
  final log = server.roomLogs[room] = [];
  void add(String kind, Map<String, dynamic> actor, Map<String, dynamic> p) {
    log.add({
      'room_id': room,
      'seq': log.length + 1,
      'event_id': '$kind:${log.length + 1}',
      'kind': kind,
      'actor': actor,
      'authority_epoch': 1,
      'payload': p,
      'created_at': now - 900 + log.length * 60,
    });
  }

  void member(String id, String text) => add(
    'message.member',
    {'id': id, 'kind': 'member', 'profile': id},
    {'member_id': id, 'text': text},
  );

  add(
    'message.user',
    {'id': 'desktop', 'kind': 'user'},
    {'text': 'We launch on Thursday. What do we still need?'},
  );
  member(
    'research',
    'Competitor pricing is collected. Two of them raised prices last month.',
  );
  member(
    'writer',
    'The blog post and the email are drafted. I need the final numbers.',
  );
  member(
    'analyst',
    'Numbers are final: 8 % growth, churn down 0.4 pp. Sending them to Writer.',
  );
  add(
    'room.activity',
    {'id': 'install:fake', 'kind': 'gateway'},
    {'status': 'settled', 'reason_code': 'silent_round'},
  );

  server.replyParts = [
    'This is a demo Hob, ',
    'so the answer is canned. Add your own Hermes server to chat for real.',
  ];
  server.replyText = server.replyParts.join();
  server.memberReply = (_) =>
      'Demo answer. Add your own Hermes server to ask real Hobs.';
  return server;
}
