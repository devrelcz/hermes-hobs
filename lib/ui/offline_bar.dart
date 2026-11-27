import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../demo/demo_hermes.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/network_status.dart';

/// Whether the current account needs an internet connection and the device
/// has lost it. The demo runs entirely on this device.
bool isOffline(BuildContext context) {
  final demo = context.select<AppState?, bool>(
    (app) => DemoHermes.isDemo(app?.serverUrl ?? ''),
  );
  final offline = context.watch<NetworkStatus?>()?.offline ?? false;
  return !demo && offline;
}

/// Puts an offline bar above [child] while the device has no internet.
///
/// The bar takes over the status-bar area: as it slides in, [child]'s top
/// padding shrinks by the same amount, so nothing jumps and the app bar below
/// keeps its place. Sits above the navigator, so every screen (sign-in, lock,
/// an open chat) gets the same bar.
class OfflineGate extends StatelessWidget {
  const OfflineGate({super.key, required this.child});

  final Widget child;

  static const _duration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    final offline = isOffline(context);
    final mq = MediaQuery.of(context);
    final top = mq.padding.top;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: offline ? 1 : 0),
      duration: mq.disableAnimations ? Duration.zero : _duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The slot stays in the tree (empty when hidden) so [child] keeps
          // its place in the Column and never loses its state.
          if (t > 0)
            ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: t,
                child: _OfflineBar(statusBarHeight: top),
              ),
            )
          else
            const SizedBox.shrink(),
          Expanded(
            child: MediaQuery(
              data: mq.copyWith(
                padding: mq.padding.copyWith(top: top * (1 - t)),
                viewPadding: mq.viewPadding.copyWith(
                  top: mq.viewPadding.top * (1 - t),
                ),
              ),
              child: child!,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBar extends StatelessWidget {
  const _OfflineBar({required this.statusBarHeight});

  final double statusBarHeight;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final net = context.watch<NetworkStatus?>();
    final checking = net?.checking ?? false;
    final phone =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    final fg = cs.onInverseSurface;
    // The bar is the inverse of the page, so the status-bar icons flip too.
    final barIsDark =
        ThemeData.estimateBrightnessForColor(cs.inverseSurface) ==
        Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: barIsDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Material(
        color: cs.inverseSurface,
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, statusBarHeight + 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: fg, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.offlineTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.offlineHint(phone: phone),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: fg.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: cs.inversePrimary,
                    disabledForegroundColor: fg.withValues(alpha: 0.6),
                  ),
                  onPressed: checking || net == null ? null : net.recheck,
                  child: Text(checking ? s.offlineChecking : s.offlineRetry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
