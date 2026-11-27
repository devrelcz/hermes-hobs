import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';

/// Accept only absolute web addresses from chat messages.
Uri? messageLinkUri(String? destination) {
  final uri = destination == null ? null : Uri.tryParse(destination);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.authority.contains('@')) {
    return null;
  }
  return uri;
}

Future<void> _openMessageLink(BuildContext context, String? href) async {
  final messenger = ScaffoldMessenger.of(context);
  final failure = Strings.of(context).linkOpenFailed;
  final uri = messageLinkUri(href);
  try {
    if (uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {
    // A browser may be unavailable or reject the URL.
  }
  if (messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(failure)));
  }
}

/// Recognize web addresses in prose without re-encoding existing escapes.
class _WebAutolinkSyntax extends md.AutolinkExtensionSyntax {
  // Brackets may appear inside a query (e.g. filter[]=new). Match paired
  // brackets there, leaving standalone closing brackets outside the address.
  static final _address = RegExp(
    r'(?:https?://|www\.)(?:[-_a-z0-9]+\.)*[-a-z0-9]+\.[-a-z0-9]+'
    r'(?:[^\s<>\[\]"„“”«»‚‘’‹›`]|\[[^\s<>\[\]"„“”«»‚‘’‹›`]*\])*',
    caseSensitive: false,
  );
  static final _boundary = RegExp(r"""[\s*_~(<>\["'„“”«»‚‘’‹›]""");
  static final _trailingPunctuation = RegExp(r"""[?!.,:*~'…]+$""");
  static final _trailingEntity = RegExp(r'&[0-9a-z]+;$');
  static final _closingParenthesis = RegExp(r'\)+$');
  static final _openParenthesis = RegExp(r'\(');
  static final _closeParenthesis = RegExp(r'\)');
  static final _www = RegExp(r'^www\.', caseSensitive: false);

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    final source = parser.source;
    final match = _address.matchAsPrefix(source, start);
    if (match == null) {
      // Preserve the Markdown extension's existing email parsing.
      return pattern.matchAsPrefix(source, start)?[2] != null &&
          super.tryMatch(parser, start);
    }

    final before = start == 0 ? '' : source[start - 1];
    if (start > 0 && !_boundary.hasMatch(before)) return false;

    final raw = match[0]!;
    final after = match.end < source.length ? source[match.end] : '';
    final markdown = parser.document.withDefaultInlineSyntaxes;
    if (before == '[' && markdown) {
      // Let Markdown resolve [label](target), [label][ref] and [label]
      // reference links before treating a bare [address] as a web address.
      if (after != ']' ||
          source.startsWith('](', match.end) ||
          source.startsWith('][', match.end) ||
          parser.document.linkReferences.containsKey(raw.toLowerCase())) {
        return false;
      }
    }

    final label = before == '<' && after == '>'
        ? raw
        : _trimProseSuffix(raw, source, start, markdown: markdown);
    final address = _www.hasMatch(label) ? 'http://$label' : label;
    final uri = messageLinkUri(address);

    parser
      ..writeText()
      ..addNode(
        uri == null
            ? md.Text(label)
            : (md.Element.text('a', label)
                ..attributes['href'] = uri.toString()),
      )
      ..consume(label.length);
    return true;
  }

  static String _trimProseSuffix(
    String raw,
    String source,
    int start, {
    required bool markdown,
  }) {
    var label = raw.replaceFirst(_trailingPunctuation, '');
    final trailing = _closingParenthesis.firstMatch(label);
    if (trailing != null) {
      final extra =
          _closeParenthesis.allMatches(label).length -
          _openParenthesis.allMatches(label).length;
      if (extra > 0) {
        label = label.substring(
          0,
          label.length - extra.clamp(0, trailing[0]!.length),
        );
      }
    }
    if (label.endsWith('_') && start > 0) {
      final endOfOpener = markdown
          ? source.lastIndexOf('_', start - 1)
          : (source[start - 1] == '_' ? start - 1 : -1);
      var beforeOpener = endOfOpener - 1;
      while (beforeOpener >= 0 && source[beforeOpener] == '_') {
        beforeOpener--;
      }
      // Leave URL underscores alone unless the nearest underscore run
      // can open emphasis, as in _read https://example.org/page_.
      if (endOfOpener >= 0 &&
          (beforeOpener < 0 || _boundary.hasMatch(source[beforeOpener])) &&
          source[endOfOpener + 1].trim().isNotEmpty) {
        final openingCount = endOfOpener - beforeOpener;
        var end = label.length;
        while (label[end - 1] == '_' && label.length - end < openingCount) {
          end--;
        }
        label = label.substring(0, end);
      }
    }
    return label.replaceFirst(_trailingEntity, '');
  }
}

class _LiteralCodeSyntax extends md.CodeSyntax {
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(match[0]!));
    return true;
  }
}

final _webAutolink = _WebAutolinkSyntax();
final _chatMarkdown = md.ExtensionSet(
  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
  [
    for (final syntax in md.ExtensionSet.gitHubFlavored.inlineSyntaxes)
      syntax is md.AutolinkExtensionSyntax ? _webAutolink : syntax,
  ],
);
final _plainMessage = md.Document(
  inlineSyntaxes: [_LiteralCodeSyntax(), _webAutolink],
  withDefaultInlineSyntaxes: false,
  encodeHtml: false,
);

class MessageMarkdown extends StatelessWidget {
  const MessageMarkdown({super.key, required this.data, this.styleSheet});

  final String data;
  final MarkdownStyleSheet? styleSheet;

  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    extensionSet: _chatMarkdown,
    styleSheet: styleSheet,
    onTapLink: (_, href, _) => _openMessageLink(context, href),
  );
}

/// Keep the user's text and mentions as written, adding taps to web addresses.
class MessageText extends StatefulWidget {
  const MessageText(this.data, {super.key, this.plainSpan, this.style});

  final String data;
  final TextSpan Function(String)? plainSpan;
  final TextStyle? style;

  @override
  State<MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends State<MessageText> {
  late List<md.Node> _nodes;
  final _recognizers = <md.Node, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(MessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) {
      _disposeRecognizers();
      _parse();
    }
  }

  void _parse() {
    _nodes = _plainMessage.parseInline(widget.data);
    for (final node in _nodes.whereType<md.Element>()) {
      final href = node.attributes['href'];
      if (messageLinkUri(href) != null) {
        _recognizers[node] = TapGestureRecognizer()
          ..onTap = () => _openMessageLink(context, href);
      }
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        for (final node in _nodes)
          if (_recognizers[node] case final recognizer?)
            TextSpan(
              text: node.textContent,
              style: const TextStyle(decoration: TextDecoration.underline),
              recognizer: recognizer,
              mouseCursor: SystemMouseCursors.click,
            )
          else
            widget.plainSpan?.call(node.textContent) ??
                TextSpan(text: node.textContent),
      ],
    ),
    style: widget.style,
  );
}
