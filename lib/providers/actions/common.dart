part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final res = await request.checkForUpdate();
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final textTheme = context.textTheme;
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: textTheme.headlineSmall,
      children: version == null
          ? [
              TextSpan(text: '\n', style: textTheme.bodyMedium),
              for (final submit in parseReleaseBody(body))
                TextSpan(text: '- $submit \n', style: textTheme.bodyMedium),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    final textTheme = context.textTheme;
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: textTheme.labelLarge?.copyWith(
            color: group.type == ChangelogType.breaking
                ? context.colorScheme.error
                : context.colorScheme.primary,
          ),
        ),
        for (final entry in group.entries)
          TextSpan(text: '• ${entry.text}\n', style: textTheme.bodyMedium),
      ],
    ];
  }

  static const _releasesUrl = 'https://github.com/$repository/releases/latest';

  /// Downloads the release file this machine can install and hands it to the system. Order
  /// matters, and MGLA.md says why: permission before the download, published checksum before
  /// the installer, and a checksum that cannot be fetched stops the update.
  Future<void> installUpdate(Map<String, dynamic> data) async {
    final assets = data['assets'] is List
        ? data['assets'] as List<dynamic>
        : null;
    final UpdateAsset? asset = pickUpdateAsset(assets, updateAssetSuffix());
    if (asset == null) {
      unawaited(launchUrl(Uri.parse(_releasesUrl)));
      return;
    }
    if (Platform.isAndroid && !(await app!.canInstallPackages())) {
      final open = await dialogs.showMessage(
        title: currentAppLocalizations.installPermissionRequired,
        message: TextSpan(text: currentAppLocalizations.installPermissionDesc),
        confirmText: currentAppLocalizations.settings,
      );
      if (open == true) {
        unawaited(app!.requestInstallPackages());
      }
      return;
    }

    final progress = ValueNotifier<double?>(null);
    final cancelToken = CancelToken();
    var cancelled = false;
    unawaited(
      dialogs.showUpdateProgress(
        progress: progress,
        onCancel: () {
          cancelled = true;
          cancelToken.cancel();
        },
      ),
    );

    String? failure;
    File? file;
    var installing = false;
    try {
      final directory = Directory(
        join((await appPath.cacheDir.future).path, 'update'),
      );
      await directory.create(recursive: true);
      file = File(join(directory.path, asset.name));
      await request.downloadUpdate(
        asset.url,
        file.path,
        onProgress: (value) => progress.value = value,
        cancelToken: cancelToken,
      );
      final sumsAsset = pickUpdateAsset(assets, 'SHA256SUMS');
      final sums = sumsAsset == null
          ? null
          : await request.getUpdateText(
              sumsAsset.url,
              cancelToken: cancelToken,
            );
      final expected = sums == null ? null : sha256ForAsset(sums, asset.name);
      if (expected == null) {
        failure = currentAppLocalizations.updateVerifyFailed;
      } else {
        final actual = (await sha256.bind(file.openRead()).first).toString();
        if (actual != expected) {
          commonPrint.log(
            'update checksum mismatch for ${asset.name}',
            logLevel: LogLevel.error,
          );
          failure = currentAppLocalizations.updateVerifyFailed;
        }
      }
      if (failure == null) {
        installing = true;
        if (Platform.isAndroid) {
          if (!await app!.installPackage(file.path)) {
            installing = false;
            failure = currentAppLocalizations.updateInstallFailed;
          }
        } else {
          await Process.start(file.path, [], mode: ProcessStartMode.detached);
          // The installer cannot replace files of a running app, so we leave first.
          unawaited(ref.read(systemActionProvider.notifier).handleExit());
        }
      }
    } catch (error) {
      if (!(error is DioException && error.type == DioExceptionType.cancel)) {
        commonPrint.log(
          'installUpdate failed ${compactError(error)}',
          logLevel: LogLevel.error,
        );
        failure = currentAppLocalizations.updateDownloadFailed;
      }
    } finally {
      if (!installing) {
        await file?.safeDelete();
      }
      if (!cancelled) {
        rootNavigatorKey.currentState?.pop();
      }
      progress.dispose();
    }

    if (failure != null && !cancelled) {
      final download = await dialogs.showMessage(
        title: currentAppLocalizations.checkUpdate,
        message: TextSpan(text: failure),
        confirmText: currentAppLocalizations.goDownload,
      );
      if (download == true) {
        unawaited(launchUrl(Uri.parse(_releasesUrl)));
      }
    }
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final context = globalState.navigatorKey.currentContext!;
      // "Update" must not end in a browser with sixteen files to choose from.
      final assets = data['assets'];
      final installable =
          canInstallUpdateInApp &&
          pickUpdateAsset(
                assets is List ? assets : null,
                updateAssetSuffix(),
              ) !=
              null;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: _releaseSpan(
          context,
          data['tag_name'] as String,
          data['body'] as String?,
        ),
        confirmText: installable
            ? currentAppLocalizations.updateNow
            : currentAppLocalizations.goDownload,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        if (installable) {
          unawaited(installUpdate(data));
        } else {
          unawaited(launchUrl(Uri.parse(_releasesUrl)));
        }
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showMessage(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }
}
