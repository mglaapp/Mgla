import 'dart:async';

import 'package:animations/animations.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether the dialog that holds [context] is still the top route.
///
/// A dialog button fires from the keyboard too (Enter, space), and a key press, unlike a tap,
/// is not swallowed while the dialog animates out. A store review robot presses Enter in a
/// row (crash report from 13-10, 0.9.6 on an emulator): the second press popped the screen
/// UNDER the dialog, and with nothing under it NavigatorState.pop threw «Bad state: No element».
bool isDialogOpen(BuildContext context) =>
    ModalRoute.of(context)?.isCurrent ?? true;

/// Closes the dialog that holds [context] — once; a repeated press while it closes is a no-op.
void popDialog<T extends Object?>(BuildContext context, [T? result]) {
  if (isDialogOpen(context)) {
    Navigator.of(context).pop<T>(result);
  }
}

class Dialogs {
  Dialogs._();

  BuildContext get _context => rootNavigatorKey.currentContext!;

  Future<T?> showCommonDialog<T>({
    required Widget child,
    BuildContext? context,
    bool? dismissible,
    bool filter = true,
  }) async {
    return showModal<T>(
      useRootNavigator: false,
      context: context ?? _context,
      configuration: FadeScaleTransitionConfiguration(
        barrierColor: Colors.black38,
        barrierDismissible: dismissible ?? true,
      ),
      builder: (_) => child,
      filter: filter ? commonFilter : null,
    );
  }

  Future<bool?> showMessage({
    required InlineSpan message,
    BuildContext? context,
    String? title,
    String? confirmText,
    String? cancelText,
    bool cancelable = true,
    bool? dismissible,
    // Высота текста до прокрутки. 200 хватает на строку-две; справке из нескольких абзацев
    // нужно больше — иначе последняя фраза срезана, а прокрутку в окне никто не ищет.
    double maxHeight = 200,
  }) async {
    return showCommonDialog<bool>(
      context: context,
      dismissible: dismissible,
      child: Builder(
        builder: (context) {
          final appLocalizations = context.appLocalizations;
          return CommonDialog(
            title: title ?? appLocalizations.tip,
            actions: [
              if (cancelable)
                TextButton(
                  onPressed: () {
                    popDialog(context, false);
                  },
                  child: Text(cancelText ?? appLocalizations.cancel),
                ),
              TextButton(
                onPressed: () {
                  popDialog(context, true);
                },
                child: Text(confirmText ?? appLocalizations.confirm),
              ),
            ],
            child: Container(
              width: 300,
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.labelLarge,
                    children: [message],
                  ),
                  style: const TextStyle(overflow: TextOverflow.visible),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Closed by whoever opened it. Not dismissible: tapping the backdrop would leave a
  /// half-written package behind, so cancelling is explicit and stops the transfer.
  Future<void> showUpdateProgress({
    required ValueListenable<double?> progress,
    required VoidCallback onCancel,
  }) async {
    return showCommonDialog<void>(
      dismissible: false,
      child: Builder(
        builder: (context) {
          final appLocalizations = context.appLocalizations;
          return CommonDialog(
            title: appLocalizations.downloadingUpdate,
            actions: [
              TextButton(
                onPressed: () {
                  if (!isDialogOpen(context)) {
                    return;
                  }
                  onCancel();
                  popDialog(context);
                },
                child: Text(appLocalizations.cancel),
              ),
            ],
            child: SizedBox(
              width: 300,
              child: ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (_, value, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: value),
                    const SizedBox(height: 12),
                    Text(
                      value == null ? '' : '${(value * 100).round()}%',
                      style: context.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool?> showAllUpdatingMessagesDialog(
    List<UpdatingMessage> messages,
  ) async {
    return showCommonDialog<bool>(
      child: Builder(
        builder: (context) {
          final appLocalizations = context.appLocalizations;
          return CommonDialog(
            backgroundColor: context.colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            title: appLocalizations.tip,
            actions: [
              TextButton(
                onPressed: () {
                  popDialog(context, true);
                },
                child: Text(appLocalizations.confirm),
              ),
            ],
            child: generateSectionV3(
              items: messages.map(
                (message) => _UpdatingMessageItem(message: message),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> showDisclaimer() async {
    return await showCommonDialog<bool>(
          dismissible: false,
          child: Builder(
            builder: (context) => CommonDialog(
              title: currentAppLocalizations.disclaimer,
              actions: [
                TextButton(
                  onPressed: () => popDialog<bool>(context, false),
                  child: Text(currentAppLocalizations.exit),
                ),
                TextButton(
                  onPressed: () => popDialog<bool>(context, true),
                  child: Text(currentAppLocalizations.agree),
                ),
              ],
              child: Text(currentAppLocalizations.disclaimerDesc),
            ),
          ),
        ) ??
        false;
  }

  void showNotifier(
    String text, {
    MessageLevel level = MessageLevel.info,
    MessageActionState? actionState,
  }) {
    rootNavigatorKey.currentContext?.showNotifier(
      text,
      level: level,
      actionState: actionState,
    );
  }

  Future<void> openUrl(String url) async {
    final res = await showMessage(
      message: TextSpan(text: url),
      title: currentAppLocalizations.externalLink,
      confirmText: currentAppLocalizations.go,
    );
    if (res != true) {
      return;
    }
    unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
  }
}

class _UpdatingMessageItem extends StatelessWidget {
  final UpdatingMessage message;

  const _UpdatingMessageItem({required this.message});

  @override
  Widget build(BuildContext context) {
    return DecorationListItem(
      minVerticalPadding: 12,
      title: TooltipText(
        text: Text(message.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      subtitle: TooltipText(
        text: Text(
          message.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

final dialogs = Dialogs._();
