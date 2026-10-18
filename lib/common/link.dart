import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'print.dart';
import 'protocol.dart';

typedef InstallConfigCallBack = void Function(String url);
typedef TvCodeCallBack = void Function(String code);

class LinkManager {
  static LinkManager? _instance;
  StreamSubscription? subscription;
  Uri? _pendingUri;

  LinkManager._internal();

  @visibleForTesting
  Stream<Uri> Function() uriLinkStream = () => AppLinks().uriLinkStream;

  /// Linux argv: the gtk plugin hooks GApplication too late to see it.
  void seedInitialLink(List<String> args) {
    for (final arg in args) {
      final uri = Uri.tryParse(arg);
      if (uri != null && protocolSchemes.contains(uri.scheme)) {
        _pendingUri = uri;
        return;
      }
    }
  }

  Future<void> initAppLinksListen(
    Function(String url) installConfigCallBack, {
    TvCodeCallBack? onTvCode,
  }) async {
    commonPrint.log('initAppLinksListen');
    destroy();
    subscription = uriLinkStream().listen((uri) {
      _handle(uri, installConfigCallBack, onTvCode);
    });
    final pending = _pendingUri;
    _pendingUri = null;
    if (pending != null) {
      _handle(pending, installConfigCallBack, onTvCode);
    }
  }

  void _handle(
    Uri uri,
    Function(String url) installConfigCallBack,
    TvCodeCallBack? onTvCode,
  ) {
    commonPrint.log('onAppLink: $uri');
    if (uri.host == 'install-config') {
      final parameters = uri.queryParameters;
      final url = parameters['url'];
      if (url != null) {
        installConfigCallBack(url);
      }
      return;
    }
    // mgla.app/tv hands a TV sign-in code to the phone app, which confirms it with its own key.
    final code = uri.queryParameters['c'];
    if (uri.scheme == 'mgla' && uri.host == 'tv' && code != null) {
      onTvCode?.call(code);
    }
  }

  void destroy() {
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();
