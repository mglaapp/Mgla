import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks for the key a person copied from their account and turns it into a profile.
///
/// Nothing here asks for a URL: the address belongs to the app, the key belongs to the person.
Future<void> showAccessKeyDialog(BuildContext context, WidgetRef ref) async {
  final appLocalizations = context.appLocalizations;
  final value = await dialogs.showCommonDialog<String>(
    child: InputDialog(
      autovalidateMode: AutovalidateMode.onUnfocus,
      title: appLocalizations.accessKey,
      labelText: appLocalizations.accessKey,
      hintText: appLocalizations.accessKeyDesc,
      value: '',
      inputFormatters: TextInputLimits.limit(TextInputLimits.url),
      validator: (input) => subscriptionUrlOf(input) == null
          ? appLocalizations.accessKeyTip
          : null,
    ),
  );
  final url = subscriptionUrlOf(value);
  if (url == null) {
    return;
  }
  unawaited(ref.read(profilesActionProvider.notifier).addProfileFormURL(url));
}

class AccessKeyButton extends ConsumerWidget {
  const AccessKeyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: () => showAccessKeyDialog(context, ref),
      icon: const Icon(Icons.vpn_key_sharp),
      label: Text(context.appLocalizations.accessKey),
    );
  }
}

/// The whole first screen when there is no profile yet: one field, one action.
class AccessKeyCard extends StatelessWidget {
  const AccessKeyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonCard(
      type: CommonCardType.filled,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizations.accessKey,
              style: context.textTheme.titleMedium?.toBold,
            ),
            const SizedBox(height: 8),
            Text(
              appLocalizations.accessKeyDesc,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const AccessKeyButton(),
            const SizedBox(height: 4),
            // Приложение выложено публично, и его ставят, ещё не купив доступ. Пока отсюда
            // некуда было пойти, установка кончалась экраном, который просит то, чего у
            // человека нет. Wrap, а не Row: на узком экране строка переносится, а не режется.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  appLocalizations.noAccessKeyYet,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton(
                  onPressed: () => dialogs.openUrl(subscriptionSite),
                  child: Text(appLocalizations.getSubscription),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
