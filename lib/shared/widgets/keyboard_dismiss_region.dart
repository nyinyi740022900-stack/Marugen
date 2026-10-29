import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A visible exit for numeric keyboards (which have no Done key on iOS),
/// plus consistent outside-tap and drag dismissal across routes and dialogs.
/// Dismissal never submits a form or changes its current value.
class KeyboardDismissRegion extends StatelessWidget {
  const KeyboardDismissRegion({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final mobile = {
      TargetPlatform.iOS,
      TargetPlatform.android,
    }.contains(Theme.of(context).platform);
    final visible = mobile && media.viewInsets.bottom > 0;
    final toolbarHeight = visible
        ? math.max(48.0, media.textScaler.scale(15) + 16)
        : 0.0;
    return Actions(
      actions: {
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              // Reserve space above the IME so the toolbar does not cover
              // fields, form actions or the bottom of a modal route.
              padding: EdgeInsets.only(bottom: toolbarHeight),
              child: child,
            ),
            if (visible)
              Positioned(
                left: 0,
                right: 0,
                bottom: media.viewInsets.bottom,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 2,
                  child: SizedBox(
                    height: toolbarHeight,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextFieldTapRegion(
                        child: TextButton.icon(
                          key: const ValueKey('dismiss-keyboard'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(80, 48),
                          ),
                          onPressed: () =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          icon: const Icon(
                            Icons.keyboard_hide_outlined,
                            size: 20,
                          ),
                          label: const Text('Done'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
