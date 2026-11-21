import 'package:flutter/material.dart';

/// Grey shapes where content is about to appear, in the content's own
/// layout, so the screen does not jump when it arrives. They breathe slowly;
/// with animations turned off they hold still.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0.5;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween(
          begin: 0.45,
          end: 1.0,
        ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
        child: widget.child,
      ),
    );
  }
}

/// One grey block of a skeleton.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// The Hob list while it loads: rows of a face, a name and a preview line.
class HobListSkeleton extends StatelessWidget {
  const HobListSkeleton({super.key, this.rows = 7});

  final int rows;

  @override
  Widget build(BuildContext context) {
    // Name and preview widths vary a little, like real rows.
    const names = [0.34, 0.22, 0.4, 0.28, 0.18, 0.31, 0.25];
    const lines = [0.78, 0.6, 0.7, 0.85, 0.52, 0.66, 0.74];
    return SkeletonPulse(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12),
        itemCount: rows,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, c) {
              final text = c.maxWidth - 38 - 12;
              return Row(
                children: [
                  const SkeletonBox(width: 38, height: 38, radius: 19),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: text * names[i % 7], height: 12),
                      const SizedBox(height: 8),
                      SkeletonBox(width: text * lines[i % 7], height: 10),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A chat while its history loads: a question and two replies.
class ChatSkeleton extends StatelessWidget {
  const ChatSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget lines(List<double> widths) => LayoutBuilder(
      builder: (context, c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in widths) ...[
            SkeletonBox(width: c.maxWidth * w, height: 11),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
    return SkeletonPulse(
      child: ListView(
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        children: [
          lines(const [0.92, 0.84, 0.88, 0.4]),
          const SizedBox(height: 14),
          const SkeletonBox(height: 44, radius: 16),
          const SizedBox(height: 26),
          lines(const [0.9, 0.7, 0.55]),
          const SizedBox(height: 14),
          const SkeletonBox(height: 44, radius: 16),
        ],
      ),
    );
  }
}

/// A screen with nothing to show yet: a picture, what is missing, and the
/// one action that changes it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    this.body,
    this.action,
  });

  final Widget art;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        // Scrolls so pull-to-refresh still works on an empty list.
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    art,
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        body!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: 20),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon in a soft tinted circle, the art of the plainer empty states.
class EmptyArt extends StatelessWidget {
  const EmptyArt({super.key, required this.icon, this.error = false});

  final IconData icon;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: error ? cs.errorContainer : cs.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 32,
        color: error ? cs.onErrorContainer : cs.onSurfaceVariant,
      ),
    );
  }
}
