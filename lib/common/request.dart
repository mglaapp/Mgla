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
  String? userAgent;

  ProviderReader? _read;

  void attach(ProviderReader read) {
    _read = read;
  }

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
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

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await dio.get(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>;
      final remoteVersion = data['tag_name'];
      final version = globalState.packageInfo.version;
      final hasUpdate =
          compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
      if (!hasUpdate) return null;
      return data;
    } catch (e) {
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
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
      return parsed == null ? Result.error('bad_response') : Result.success(parsed);
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
      _api('/pay/usdt', form: {'key': key, 'plan': plan}, parse: UsdtInvoice.fromJson);

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
  Future<Result<AccountStatus>> checkUsdtPayment(String key) =>
      _api('/pay/usdt/check', form: {'key': key}, parse: AccountStatus.fromJson);
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
