import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/share_inbox.dart';
import 'hob_avatar.dart';

/// Asks which Hob gets what another app shared. Returns null when the user
/// closes the sheet.
Future<Hob?> showShareTargetSheet(
  BuildContext context,
  List<SharedItem> items,
) => showModalBottomSheet<Hob>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ShareTargetSheet(items: items),
);

class _ShareTargetSheet extends StatelessWidget {
  const _ShareTargetSheet({required this.items});

  final List<SharedItem> items;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final hobs = [...app.hobs]
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(s.shareTitle, style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                s.shareSummary(items.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (hobs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: app.loadingHobs
                      ? const CircularProgressIndicator()
                      : Text(s.shareNoHobs),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: hobs.length,
                  itemBuilder: (context, i) {
                    final hob = hobs[i];
                    return ListTile(
                      key: ValueKey('share-to-${hob.name}'),
                      leading: HobAvatar(hob: hob, size: 36),
                      title: Text(hob.displayName),
                      subtitle: hob.description.isEmpty
                          ? null
                          : Text(
                              hob.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => Navigator.pop(context, hob),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
