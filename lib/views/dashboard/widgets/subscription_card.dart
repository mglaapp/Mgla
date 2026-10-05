import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/profiles/access_key.dart';
import 'package:fl_clash/views/subscription.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Сколько дней до конца срока блок подсвечивает как «пора продлевать».
const subscriptionWarnDays = 3;

/// Подписка на главном экране: до какого числа оплачено и кнопка «Продлить» (05-10).
///
/// ЗАЧЕМ НА ГЛАВНОМ. Экран подписки лежит в «Инструментах», и человек, у которого кончается
/// срок, узнавал об этом только по отключившемуся VPN. Решение владельца: срок и продление —
/// там, куда смотрят каждый день, рядом с кнопкой подключения.
///
/// «ПРОДЛИТЬ» ведёт сразу к оплате: выбор срока (если тарифов больше одного) -> тот же экран
/// выбора способа, что и на экране подписки ([openPayment]). Своей дороги к оплате у блока
/// нет — вторая разошлась бы с первой на следующем способе оплаты.
///
/// Без нашего ключа (профиль чужой) — «Создать аккаунт» и «Ключ доступа»: блок про подписку,
/// который при отсутствии подписки молчит, прячет единственное место, где её можно завести.
class SubscriptionCard extends ConsumerStatefulWidget {
  /// Откуда брать статус; по умолчанию — наш сервер. Подменяется в тестах: срок, кнопка и
  /// подсветка — это разметка, и без подмены её проверили бы только глазами.
  final Future<Result<AccountStatus>> Function(String key)? fetchStatus;

  const SubscriptionCard({super.key, this.fetchStatus});

  @override
  ConsumerState<SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends ConsumerState<SubscriptionCard> {
  AccountStatus? _status;
  String? _loadedKey;
  bool _loaded = false;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final key = ourAccessKey(ref.read(profilesStateProvider));
    _loadedKey = key;
    if (key == null) {
      if (mounted) {
        setState(() {
          _status = null;
          _loaded = true;
          _failed = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _busy = true);
    final fetch = widget.fetchStatus ?? request.accountStatus;
    final result = await fetch(key);
    // Ключ сменился, пока шёл запрос: этот ответ про чужой срок, его перезапишет новый.
    if (!mounted || _loadedKey != key) return;
    setState(() {
      _busy = false;
      _loaded = true;
      _failed = result.isError;
      // Сбой сети не стирает прошлый ответ: срок, виденный минуту назад, вернее пустоты.
      if (result.isSuccess) _status = result.data;
    });
  }

  /// Тариф: один — без вопроса, несколько — короткий выбор срока.
  Future<Plan?> _pickPlan(List<Plan> plans) async {
    if (plans.length == 1) return plans.first;
    final l = context.appLocalizations;
    return showDialog<Plan>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l.choosePlan),
        children: [
          for (final plan in plans)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(plan),
              child: Row(
                children: [
                  Expanded(child: Text(plan.title)),
                  Text(
                    '\$${plan.usd.toStringAsFixed(2)}',
                    style: dialogContext.textTheme.titleSmall?.toBold,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _renew(AccountStatus status) async {
    final key = _loadedKey;
    if (key == null) return;
    if (!canPayInApp(status)) {
      await dialogs.openUrl(accountUrl);
      return;
    }
    if (status.plans.isEmpty) return _openDetails();
    final plan = await _pickPlan(status.plans);
    if (plan == null || !mounted) return;
    setState(() => _busy = true);
    await openPayment(context, status, plan, key);
    if (!mounted) return;
    setState(() => _busy = false);
    // Перечитываем при любом возврате: карта подтверждается уведомлением платёжки, не здесь.
    await _load();
  }

  Future<void> _openDetails() async {
    await BaseNavigator.push(context, const SubscriptionView());
    if (mounted) await _load();
  }

  Future<void> _createAccount() async {
    setState(() => _busy = true);
    await createAccountFlow(context, ref);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Widget _title(String text) {
    return Row(
      children: [
        Icon(
          Icons.card_membership,
          size: 20,
          color: context.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: context.textTheme.titleMedium?.toBold),
        ),
        IconButton(
          tooltip: context.appLocalizations.sync,
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
    );
  }

  Widget _noAccount() {
    final l = context.appLocalizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(l.subscription),
        const SizedBox(height: 4),
        Text(
          l.accessKeyDesc,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _createAccount,
              icon: const Icon(Icons.person_add_alt),
              label: Text(l.createAccount),
            ),
            const AccessKeyButton(),
          ],
        ),
      ],
    );
  }

  Widget _withStatus(AccountStatus status) {
    final l = context.appLocalizations;
    final scheme = context.colorScheme;
    final expire = status.expiresAt;
    final days = status.daysLeft;
    final quota = status.quotaGb;
    final soon = status.active && days != null && days <= subscriptionWarnDays;
    final accent = !status.active
        ? scheme.error
        : soon
        ? MglaPalette.warn
        : scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(l.subscription),
        const SizedBox(height: 4),
        Text(
          status.active && expire != null
              ? '${l.accessPaidUntil} ${expire.show}'
              : l.accessNotPaid,
          style: context.textTheme.titleSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (status.active && days != null)
          Text(
            l.daysLeftCount(days),
            style: context.textTheme.bodyMedium?.copyWith(
              color: soon ? MglaPalette.warn : scheme.onSurfaceVariant,
            ),
          ),
        if (quota != null)
          Text(
            '${status.usedGb ?? 0} / $quota GB',
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        if (_failed)
          Text(
            l.errNetwork,
            style: context.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _renew(status),
              icon: const Icon(Icons.autorenew),
              label: Text(
                status.active ? l.renewSubscription : l.getSubscription,
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _openDetails,
              child: Text(l.subscriptionDetails),
            ),
          ],
        ),
      ],
    );
  }

  Widget _failedFirst() {
    final l = context.appLocalizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(l.subscription),
        Text(
          l.errNetwork,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.error,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Перечитываем только при смене КЛЮЧА: состояние профилей меняется и от обновления
    // трафика подписки, и запрос к серверу на каждое такое событие был бы шумом.
    ref.listen(profilesStateProvider, (_, next) {
      if (ourAccessKey(next) != _loadedKey) unawaited(_load());
    });
    final status = _status;
    final Widget body;
    if (_loadedKey == null && _loaded) {
      body = _noAccount();
    } else if (status != null) {
      body = _withStatus(status);
    } else if (_loaded && _failed) {
      body = _failedFirst();
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context.appLocalizations.subscription),
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
      );
    }
    return CommonCard(
      type: CommonCardType.filled,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy && status != null)
              const LinearProgressIndicator(minHeight: 2),
            body,
          ],
        ),
      ),
    );
  }
}
