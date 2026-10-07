import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';

class Request {
  late final Dio dio;
  late final Dio _clashDio;

  /// Update checks only. Bounded, unlike [dio]: the mirror is asked first, and a host that
  /// never answers must hand over to GitHub in seconds, not after the system's TCP timeout.
  late final Dio _updateDio;
  String? userAgent;

  ProviderReader? _read;

  void attach(ProviderReader read) {
    _read = read;
  }

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    _updateDio = Dio(
      BaseOptions(
        headers: {'User-Agent': browserUa},
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = globalState.ua;
          final read = _read;
          if (read == null) {
            return 'DIRECT';
          }
          return FlClashHttpOverrides.findProxyForReader(read, uri);
        };
        return client;
      },
    );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      return await _clashDio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
    } catch (e) {
      commonPrint.log(
        'getFileResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    try {
      return await _clashDio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
    } catch (e) {
      commonPrint.log(
        'getTextResponseForUrl error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      rethrow;
    }
  }

  /// Core-aware client on purpose: people reach GitHub through the tunnel as often as not.
  Future<void> downloadUpdate(
    String url,
    String savePath, {
    required void Function(double? progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    await _clashDio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      options: Options(headers: {'User-Agent': browserUa}),
      onReceiveProgress: (received, total) {
        onProgress(total > 0 ? received / total : null);
      },
    );
  }

  Future<String?> getUpdateText(String url, {CancelToken? cancelToken}) async {
    try {
      final response = await _clashDio.get<String>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': browserUa},
        ),
      );
      return response.data;
    } catch (e) {
      commonPrint.log(
        'getUpdateText error ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  /// A newer release, or null. Asks [updateSources] in order: our mirror, then GitHub.
  ///
  /// The next source is asked when one fails AND when one simply has nothing newer: a mirror
  /// that fell behind (its disk filled up, a sync failed) must not hide a release GitHub
  /// already has. Whichever answers first with a newer version wins, and its file links are
  /// the ones installUpdate downloads from.
  Future<Map<String, dynamic>?> checkForUpdate() async {
    final version = globalState.packageInfo.version;
    for (final url in updateSources()) {
      final data = await _latestRelease(url);
      if (isNewerRelease(data, version)) return data;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _latestRelease(String url) async {
    try {
      final response = await _updateDio.get(
        url,
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (response.statusCode != 200 || data is! Map<String, dynamic>) {
        return null;
      }
      return data;
    } catch (e) {
      commonPrint.log(
        'checkForUpdate failed at ${Uri.tryParse(url)?.host} ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    'https://ipwho.is': IpInfo.fromIpWhoIsJson,
    'https://api.myip.com': IpInfo.fromMyIpJson,
    'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
    'https://ident.me/json': IpInfo.fromIdentMeJson,
    'http://ip-api.com/json': IpInfo.fromIpAPIJson,
    'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
    'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final futures = _ipInfoSources.entries.map((source) async {
      final Completer<Result<IpInfo?>> completer = Completer();
      void handleFailRes() {
        if (!completer.isCompleted && failureCount == _ipInfoSources.length) {
          completer.complete(Result.success(null));
        }
      }

      final future = dio
          .get<Map<String, dynamic>>(
            source.key,
            cancelToken: token,
            options: Options(responseType: ResponseType.json),
          )
          .timeout(const Duration(seconds: 10));
      unawaited(
        future
            .then((res) {
              if (res.statusCode == HttpStatus.ok && res.data != null) {
                completer.complete(Result.success(source.value(res.data!)));
                return;
              }
              commonPrint.log('checkIp data empty', logLevel: LogLevel.info);
              failureCount++;
              handleFailRes();
            })
            .catchError((e) {
              failureCount++;
              if (e is DioException && e.type == DioExceptionType.cancel) {
                completer.complete(Result.error('cancelled'));
                return;
              }
              commonPrint.log('checkIp error $e', logLevel: LogLevel.warning);
              handleFailRes();
            }),
      );
      return completer.future;
    });
    final res = await Future.any(futures);
    token.cancel();
    return res;
  }

  // ---------------------------------------------------------------- наш API
  // Пять вызовов, которыми приложение обходится без браузера. Адрес собирается из константы
  // бренда: вписанный здесь второй раз, он переживёт первый при смене домена и уведёт
  // человека в никуда ровно в момент оплаты.
  //
  // Ошибка возвращается КОДОМ, а не готовым текстом: текст сервера один, а языков в
  // приложении четыре, и показывать русскую строку японцу — это не локализация.

  static const _apiBase = '$subscriptionSite/api/v1';

  /// Version and platform only: the account key already travels in the request.
  static String? appHeader() {
    try {
      final info = globalState.packageInfo;
      return '${info.version}+${info.buildNumber}; ${Platform.operatingSystem}';
    } on Error {
      return null;
    }
  }

  static Map<String, String> _appHeaders() {
    final value = appHeader();
    return value == null ? const {} : {'X-Mgla-App': value};
  }

  Future<Result<T>> _api<T>(
    String path, {
    Map<String, dynamic>? form,
    Map<String, dynamic>? query,
    required T? Function(Map<String, dynamic>) parse,
  }) async {
    // Отказы 4xx — это ОТВЕТ, а не сбой: в них лежит код, ради которого всё и затевалось.
    // Без этого Dio бросил бы исключение и «ключ не найден» стал бы неотличим от «нет сети».
    final options = Options(
      responseType: ResponseType.json,
      validateStatus: (code) => code != null && code < 500,
      contentType: form == null ? null : Headers.formUrlEncodedContentType,
      headers: _appHeaders(),
    );
    try {
      final response = form == null
          ? await dio.get(
              '$_apiBase$path',
              queryParameters: query,
              options: options,
            )
          : await dio.post('$_apiBase$path', data: form, options: options);
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Result.error('bad_response');
      }
      if (data['ok'] != true) {
        final code = data['error'];
        commonPrint.log(
          'api $path refused: ${data['error']} ${data['message']}',
          logLevel: LogLevel.warning,
        );
        return Result.error(code is String && code.isNotEmpty ? code : 'error');
      }
      final parsed = parse(data);
      return parsed == null
          ? Result.error('bad_response')
          : Result.success(parsed);
    } catch (e) {
      commonPrint.log(
        'api $path failed ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      return Result.error('network');
    }
  }

  Future<Result<NewAccount>> createAccount() =>
      _api('/account', form: const {}, parse: NewAccount.fromJson);

  Future<Result<AccountStatus>> accountStatus(String key) =>
      _api('/status', query: {'key': key}, parse: AccountStatus.fromJson);

  Future<Result<UsdtInvoice>> createUsdtInvoice(String key, String plan) =>
      _api(
        '/pay/usdt',
        form: {'key': key, 'plan': plan},
        parse: UsdtInvoice.fromJson,
      );

  /// Ссылка на оплату картой. Приложение её ОТКРЫВАЕТ: страница оплаты принадлежит платёжной
  /// системе, и показывать её внутри значило бы просить ввести карту в окне без адресной
  /// строки.
  Future<Result<String>> createCardPayment(String key, String plan) => _api(
    '/pay/card',
    form: {'key': key, 'plan': plan},
    parse: (data) {
      final url = data['url'];
      return url is String && url.isNotEmpty ? url : null;
    },
  );

  /// Ссылка на оплату скинами (OmniSkin): открывается в браузере, как карта.
  Future<Result<String>> createSkinsPayment(String key, String plan) => _api(
    '/pay/skins',
    form: {'key': key, 'plan': plan},
    parse: (data) {
      final url = data['url'];
      return url is String && url.isNotEmpty ? url : null;
    },
  );

  Future<Result<String>> createTrialPayment(String key) => _api(
    '/pay/trial',
    form: {'key': key},
    parse: (data) {
      final url = data['url'];
      return url is String && url.isNotEmpty ? url : null;
    },
  );

  /// Счёт на оплату монетой. Живой счёт на тот же тариф и монету сервер отдаёт повторно:
  /// обновлённый экран не должен показать новую сумму, когда старая уже отправлена.
  Future<Result<CryptoInvoice>> createCryptoInvoice(
    String key,
    String plan,
    String coin,
  ) => _api(
    '/pay/crypto',
    form: {'key': key, 'plan': plan, 'coin': coin},
    parse: CryptoInvoice.fromJson,
  );

  /// «Я оплатил» по монете: сервер сверяет сеть сейчас и отвечает, зачтён ли счёт.
  Future<Result<CryptoCheck>> checkCryptoPayment(String key, int id) => _api(
    '/pay/crypto/check',
    form: {'key': key, 'id': '$id'},
    parse: CryptoCheck.fromJson,
  );

  /// BNB: зачёт по хешу транзакции, который человек вставил сам.
  Future<Result<CryptoCheck>> claimCryptoHash(String key, int id, String tx) =>
      _api(
        '/pay/crypto/hash',
        form: {'key': key, 'id': '$id', 'tx': tx},
        parse: CryptoCheck.fromJson,
      );

  /// Привязать почту: сервер шлёт письмо, ссылка из письма привязывает аккаунт.
  Future<Result<int>> bindEmail(String key, String email) => _api(
    '/bind/email',
    form: {'key': key, 'email': email},
    parse: (data) => data['minutes'] is int ? data['minutes'] as int : 0,
  );

  /// Ссылка в бота, которая привяжет телеграм к этому аккаунту.
  Future<Result<String>> bindTelegram(String key) => _api(
    '/bind/telegram',
    form: {'key': key},
    parse: (data) {
      final link = data['link'];
      return link is String && link.isNotEmpty ? link : null;
    },
  );

  /// «Я оплатил»: просим сверить блокчейн немедленно. Безопасно при любом числе нажатий —
  /// зачёт идёт по хэшу перевода, повтор упирается в ограничение базы на стороне сервера.
  Future<Result<AccountStatus>> checkUsdtPayment(String key) => _api(
    '/pay/usdt/check',
    form: {'key': key},
    parse: AccountStatus.fromJson,
  );

  /// No account key on purpose: a crash report must not say whose app it came from.
  Future<CrashDelivery> sendCrashReport(Map<String, String> report) async {
    try {
      final response = await dio.post(
        '$_apiBase/crash',
        data: report,
        options: Options(
          contentType: Headers.jsonContentType,
          headers: _appHeaders(),
          validateStatus: (_) => true,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final code = response.statusCode ?? 0;
      return code == 429 || code >= 500
          ? CrashDelivery.retryLater
          : CrashDelivery.delivered;
    } catch (e) {
      commonPrint.log(
        'crash report not sent ${compactError(e)}',
        logLevel: LogLevel.warning,
      );
      return CrashDelivery.retryLater;
    }
  }
}

final request = Request();

String? getFileNameForDisposition(String? disposition) {
  if (disposition == null) return null;
  final parseValue = HeaderValue.parse(disposition);
  final parameters = parseValue.parameters;
  final fileNamePointKey = parameters.keys.firstWhere(
    (key) => key == 'filename*',
    orElse: () => '',
  );
  if (fileNamePointKey.isNotEmpty) {
    final res = parameters[fileNamePointKey]?.split("''") ?? [];
    if (res.length >= 2) {
      return Uri.decodeComponent(res[1]);
    }
  }
  final fileNameKey = parameters.keys.firstWhere(
    (key) => key == 'filename',
    orElse: () => '',
  );
  if (fileNameKey.isEmpty) return null;
  return parameters[fileNameKey];
}
