import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OutboundMode extends ConsumerWidget {
  const OutboundMode({super.key});

  void _handleChangeMode(Mode mode, WidgetRef ref) {
    ref.read(setupActionProvider.notifier).changeMode(mode);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final height = getWidgetHeight(2);
    return SizedBox(
      height: height,
      child: Consumer(
        builder: (_, ref, _) {
          final mode = ref.watch(
            patchClashConfigProvider.select((state) => state.mode),
          );
          return Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
            child: CommonCard(
              radius: AppCorner.lg,
              onPressed: () {},
              skipTraversal: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _OutboundModeHeader(),
                  Flexible(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      child: RadioGroup<Mode>(
                        groupValue: mode,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          _handleChangeMode(value, ref);
                        },
                        child: _ModeRadioList(
                          onSelect: (item) {
                            _handleChangeMode(item, ref);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Заголовок плитки с маленькой справкой «что это такое» (просьба владельца 06-10): три слова
/// «Правило / Глобальный / Прямой» человеку без опыта ничего не говорят. Ряд собран как у
/// «Скорости сети», а не через CommonCard.info: заголовок карточки с кнопками ужимает отступы
/// на 8 и при нижнем 0 ушёл бы в минус.
class _OutboundModeHeader extends StatelessWidget {
  const _OutboundModeHeader();

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Padding(
      padding: baseInfoEdgeInsets.copyWith(bottom: 0),
      child: Row(
        children: [
          Flexible(
            child: InfoHeader(
              padding: EdgeInsets.zero,
              info: Info(
                label: appLocalizations.outboundMode,
                iconData: Icons.call_split_sharp,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Вне обхода клавиатурой: стрелки и Tab по плитке ходят по режимам, как и прежде
          // (outbound_mode_focus_test); справка — для мыши и пальца.
          ExcludeFocus(
            child: SizedBox.square(
              dimension: globalState.measure.titleSmallHeight,
              child: IconButton(
                key: const ValueKey('outbound_mode_help'),
                tooltip: appLocalizations.tip,
                padding: EdgeInsets.zero,
                onPressed: () {
                  dialogs.showMessage(
                    title: appLocalizations.outboundMode,
                    message: TextSpan(text: appLocalizations.outboundModeTip),
                    cancelable: false,
                    maxHeight: 320,
                  );
                },
                icon: Icon(
                  Icons.info_outline,
                  size: 16.ap,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeRadioList extends StatelessWidget {
  const _ModeRadioList({required this.onSelect});

  final void Function(Mode mode) onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final minTileHeight = min(
          constraints.maxHeight / 3,
          globalState.measure.bodyMediumHeight + 16,
        );
        return Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (final item in Mode.values)
              ListItem.radio(
                horizontalTitleGap: 8,
                tileTitleAlignment: ListTileTitleAlignment.center,
                minTileHeight: minTileHeight,
                minVerticalPadding: 0,
                padding: EdgeInsets.only(left: 12.ap, right: 16.ap),
                onTap: () {
                  onSelect(item);
                },
                value: item,
                title: Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodyMedium?.toSoftBold,
                ),
              ),
          ],
        );
      },
    );
  }
}

class OutboundModeV2 extends StatelessWidget {
  const OutboundModeV2({super.key});

  void _handleChangeMode(Mode mode, WidgetRef ref) {
    ref.read(setupActionProvider.notifier).changeMode(mode);
  }

  Color _getTextColor(BuildContext context, Mode mode) {
    return switch (mode) {
      Mode.rule => context.colorScheme.onSecondaryContainer,
      Mode.global => context.colorScheme.onPrimaryContainer,
      Mode.direct => context.colorScheme.onTertiaryContainer,
    };
  }

  @override
  Widget build(BuildContext context) {
    final height = getWidgetHeight(1);
    return SizedBox(
      height: height,
      child: CommonCard(
        radius: AppCorner.lg,
        child: Consumer(
          builder: (_, ref, _) {
            final mode = ref.watch(
              patchClashConfigProvider.select((state) => state.mode),
            );
            final thumbColor = switch (mode) {
              Mode.rule => context.colorScheme.secondaryContainer,
              Mode.global => globalState.theme.darken3PrimaryContainer,
              Mode.direct => context.colorScheme.tertiaryContainer,
            };
            return LayoutBuilder(
              builder: (_, constraints) {
                return Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints.expand(),
                        child: CommonTabBar<Mode>(
                          children: {
                            for (final item in Mode.values)
                              item: _ModeTab(
                                label: item.label,
                                height: height - 8.ap - 24,
                                color: item == mode
                                    ? _getTextColor(context, item)
                                    : null,
                              ),
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          groupValue: mode,
                          onValueChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            _handleChangeMode(value, ref);
                          },
                          thumbColor: thumbColor,
                        ),
                      ),
                    ),
                    Container(
                      color: thumbColor.opacity50,
                      height: 8.ap,
                      width: constraints.maxWidth,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.height,
    required this.color,
  });

  final String label;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(),
      height: height,
      padding: const EdgeInsets.all(4),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.adjustSize(1).copyWith(color: color),
      ),
    );
  }
}
