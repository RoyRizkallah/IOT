import 'package:flutter/material.dart';

/// Custom page transitions used for in-app navigation.
///
/// We avoid Material's default platform transition because on Android it's a
/// fast slide that flattens the design. A short fade + subtle vertical lift
/// reads as more polished and matches the "soft, considered" tone of the UI.
class FadeUpRoute<T> extends PageRouteBuilder<T> {
  FadeUpRoute({required Widget page})
      : super(
          opaque: true,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
