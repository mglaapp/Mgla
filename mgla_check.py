#!/usr/bin/env python3
"""Сторож бренда Mgla. Запускать из корня репозитория ПЕРЕД каждой сборкой и ПОСЛЕ слияния
с апстримом: python tools_mgla_check.py

ЗАЧЕМ ИМЕННО ПОСЛЕ СЛИЯНИЯ. Апстрим (chen08209/FlClash) коммитит каждые пару дней. Слияние
может вернуть чужое имя в любой из перечисленных точек, и увидеть это глазами нельзя: заголовок
окна и свойства файла никто не перечитывает. Дефект всплыл бы у человека, скачавшего сборку.

ПОЧЕМУ СПИСОК ТОЧЕЧНЫЙ, А НЕ «ГРЕП ПО FlClash ВЕЗДЕ». Слово FlClash законно остаётся в
репозитории: лицензия, упоминание основы, внутреннее имя пакета fl_clash в 1549 импортах.
Проверка, которая ругается на них, будет отключена в первую же неделю. Здесь проверяются ровно
те места, которые ВИДИТ человек, и каждое названо.

КОНТРОЛЬ ВНУТРИ ПРОГОНА: заведомо ложное утверждение обязано провалиться. Без него «всё зелено»
неотличимо от «проверка ничего не читает» (грабля 09-06).
"""
import io
import pathlib
import re
import sys

_ok = 0
_fail = 0


def check(name: str, cond: bool, got=None) -> None:
    global _ok, _fail
    if cond:
        _ok += 1
        print(f"  PASS  {name}")
    else:
        _fail += 1
        print(f"  FAIL  {name}" + (f"   получено: {got!r}" if got is not None else ""))


def read(path: str) -> str:
    try:
        return io.open(path, encoding="utf-8", newline="").read()
    except OSError as e:
        return f"<НЕТ ФАЙЛА: {e}>"


def main() -> int:
    print("— имя, которое видит человек —")
    c = read("lib/common/constant.dart")
    check("имя приложения = Mgla (заголовок окна, трей, имена бэкапов)",
          "const appName = 'Mgla';" in c)
    check("обновления ищутся в НАШЕМ репозитории, а не в чужом",
          "const repository = 'mglaapp/Mgla';" in c)
    check("акцент системы — лёд #7DD3FC, не пыльно-розовый апстрима",
          "const defaultPrimaryColor = 0xFF7DD3FC;" in c, )

    print("\n— Windows: файл и окно —")
    cm = read("windows/CMakeLists.txt")
    check("имя исполняемого файла Mgla.exe", 'set(BINARY_NAME "Mgla")' in cm)
    check("имя проекта CMake", "project(Mgla LANGUAGES CXX)" in cm)
    check("заголовок окна", 'window.Create(L"Mgla"' in read("windows/runner/main.cpp"))
    rc = read("windows/runner/Runner.rc")
    for field in ("CompanyName", "FileDescription", "ProductName", "InternalName"):
        check(f"свойство файла {field}", f'VALUE "{field}", "Mgla"' in rc)
    check("имя файла в свойствах", 'VALUE "OriginalFilename", "Mgla.exe"' in rc)
    # Производное от GPL-3.0 не может быть «all rights reserved» — это неправда о правах.
    check("в правах не осталось 'All rights reserved'", "All rights reserved" not in rc)

    print("\n— схема ссылок (встроенная подписка) —")
    p = read("lib/common/protocol.dart")
    check("mgla:// зарегистрирована", "'mgla'" in p)
    # Чужие схемы оставлены НАМЕРЕННО: ссылка, выданная человеку раньше, обязана работать.
    check("чужие схемы не выброшены (старые ссылки продолжают работать)",
          "'clash'" in p and "'clashmeta'" in p)
    check("android знает mgla://", 'android:scheme="mgla"' in read("android/app/src/main/AndroidManifest.xml"))
    check("macos знает mgla://", "<string>mgla</string>" in read("macos/Runner/Info.plist"))
    lx = read("linux/packaging/appimage/make_config.yaml")
    check("linux знает mgla://", "x-scheme-handler/mgla" in lx)
    check("подпись в меню приложений Linux", "display_name: Mgla" in lx)

    print("\n— шрифт дизайн-кода —")
    pub = read("pubspec.yaml")
    check("IBM Plex Sans подключён", "family: IBMPlexSans" in pub)
    check("IBM Plex Mono подключён", "family: IBMPlexMono" in pub)
    for f in ("IBMPlexSans.ttf", "IBMPlexMono-Regular.ttf", "IBMPlexMono-SemiBold.ttf"):
        check(f"файл {f} на месте", pathlib.Path("assets/fonts", f).is_file())
    app = read("lib/application.dart")
    # ОБЕИМ темам: разный шрифт в светлой и тёмной читался бы как поломка, а не как выбор.
    check("шрифт задан обеим темам", app.count("fontFamily: FontFamily.sans.value") == 2,
          app.count("fontFamily: FontFamily.sans.value"))

    print("\n— движение «рез» —")
    # Дизайн-код запрещает отскок дословно. Апстрим им пользуется, и слияние вернёт его МОЛЧА:
    # пружинящую кнопку видно только глазами и только в движении, а этого никто не делает нарочно.
    bouncy = []
    for path in pathlib.Path("lib").rglob("*.dart"):
        if "generated" in str(path) or path.name == "motion.dart":
            continue
        t = io.open(path, encoding="utf-8", newline="").read()
        for bad in ("easeOutBack", "easeInBack", "elasticOut", "elasticIn",
                    "bounceOut", "bounceIn"):
            if bad in t:
                bouncy.append(f"{path}: {bad}")
    check("пружинящих кривых не осталось ни одной", not bouncy, bouncy[:5])
    mo = read("lib/common/motion.dart")
    check("кривая та же, что на сайте: cubic-bezier(.16,.84,.28,1)",
          "Cubic(0.16, 0.84, 0.28, 1.0)" in mo)
    check("длительности дизайн-кода 110/240/420 на месте",
          all(f"milliseconds: {ms}" in mo for ms in (110, 240, 420)))

    print("\n— своё место в системе —")
    # applicationId — ЕДИНСТВЕННОЕ, чем наша установка отличается от апстримовской. Совпали —
    # для Android это одна и та же программа: рядом они не встанут, а магазин вторую не примет.
    g = read("android/app/build.gradle.kts")
    check("android: свой applicationId", 'applicationId = "app.mgla"' in g)
    # namespace НЕ меняем НАМЕРЕННО: это пакет Kotlin, он же префикс имени класса. Человек его
    # не видит, а переименование задело бы каждый файл модуля и все слияния с апстримом.
    check("android: namespace оставлен апстримовским (имена классов не трогаем)",
          'namespace = "com.follow.clash"' in g)
    # Манифест обязан брать id ПОДСТАНОВКОЙ. Вписанный руками, он разъедется с applicationId, и
    # разрешение, экшен и authority провайдера перестанут совпадать с тем, что зовёт код.
    mf = read("android/app/src/main/AndroidManifest.xml")
    check("android: экшены и права берут id подстановкой, а не вписаны руками",
          "${applicationId}.action.START" in mf and "${applicationId}.permission" in mf)
    check("android: id нигде не вписан в манифест буквами",
          "com.follow.clash" not in mf and "app.mgla" not in mf)
    check("android: имя в списке приложений = Mgla",
          '<string name="app_name">Mgla</string>' in read(
              "android/common/src/main/res/values/strings.xml"))
    check("android: отладочная сборка подписана нашим именем",
          "Mgla Debug" in read("android/app/src/debug/AndroidManifest.xml"))

    # ИНВАРИАНТ, КОТОРЫЙ РУШИТСЯ МОЛЧА. Одна строка служит ДВУМ вещам сразу: префиксом имени
    # класса (com.follow.clash.MainActivity) и именем канала между Kotlin и Dart. Сменить её на
    # одной стороне — приложение соберётся и запустится, но на Android разом отвалятся список
    # приложений, служба и плитка, и ни одной ошибки в логе: канал с другим именем никто не
    # слушает. Поэтому проверяется не значение, а РАВЕНСТВО двух концов.
    dart = re.search(r"const packageName = '([^']+)'", read("lib/common/constant.dart"))
    kt = re.search(r'const val PACKAGE_NAME = "([^"]+)"',
                   read("android/common/src/main/java/com/follow/clash/common/Components.kt"))
    check("канал Kotlin↔Dart назван одинаково с обеих сторон",
          bool(dart and kt) and dart.group(1) == kt.group(1),
          (dart.group(1) if dart else None, kt.group(1) if kt else None))

    print("\n— macOS и Linux: как нас видит система —")
    xc = read("macos/Runner/Configs/AppInfo.xcconfig")
    check("macos: свой bundle id", "PRODUCT_BUNDLE_IDENTIFIER = app.mgla" in xc)
    check("macos: имя приложения Mgla.app", "PRODUCT_NAME = Mgla" in xc)
    check("macos: в правах не осталось 'All rights reserved'", "All rights reserved" not in xc)
    pbx = read("macos/Runner.xcodeproj/project.pbxproj")
    check("macos: чужого id не осталось нигде в проекте", "com.follow" not in pbx)
    check("macos: подпись под значком = Mgla",
          "INFOPLIST_KEY_CFBundleDisplayName = Mgla;" in pbx)
    # Текст запроса доступа человек читает в системном окне — чужому имени там не место.
    check("macos: в запросе доступа к геопозиции наше имя",
          "Mgla needs location access" in read("macos/Runner/Info.plist"))
    check("имя файла, который скачивает человек, = Mgla-*",
          "app_name: 'Mgla'" in read("distribute_options.yaml"))
    for kind in ("appimage", "deb", "rpm"):
        lp = read("linux/packaging/%s/make_config.yaml" % kind)
        check("linux/%s: подпись в меню приложений = Mgla" % kind, "display_name: Mgla" in lp)
        # Без своей схемы кнопка «Подключить в Mgla» на этой упаковке не откроет ничего —
        # ссылку некому перехватить. В deb и rpm её и не было: нашлось этой проверкой.
        check("linux/%s: mgla:// зарегистрирована" % kind, "x-scheme-handler/mgla" in lp)
        check("linux/%s: чужой адрес сопровождающего убран" % kind, "chen08209" not in lp)

    print("\n— имя там, где человек его читает каждый день —")
    # Постоянное уведомление — самая заметная поверхность VPN на телефоне: оно висит всё время,
    # пока включён туннель. Заголовок берётся из имени профиля, а до его загрузки — из этих
    # трёх умолчаний. Ветка десктопного бренда их не задела, и человек читал бы чужое имя.
    check("android: заголовок уведомления по умолчанию = Mgla",
          'setContentTitle("Mgla")' in read(
              "android/service/src/main/java/com/follow/clash/service/modules/"
              "NotificationModule.kt"))
    check("android: умолчание параметров уведомления = Mgla",
          'val title: String = "Mgla"' in read(
              "android/service/src/main/java/com/follow/clash/service/models/"
              "NotificationParams.kt"))
    check("android: имя профиля до загрузки = Mgla",
          'val currentProfileName: String = "Mgla"' in read(
              "android/app/src/main/kotlin/com/follow/clash/models/State.kt"))
    # Запись .desktop регистрирует схему ссылок в Linux; её имя видно в окне «Открыть с помощью».
    check("linux: запись .desktop подписана нашим именем",
          "'Name=Mgla'" in read("lib/common/protocol.dart"))

    # ДВУСТОРОННЯЯ проверка текстов ошибок. Слева — что чужого имени ПРОГРАММЫ не осталось;
    # справа — что имена ФАЙЛОВ уцелели. Сплошная замена «FlClash -> Mgla» прошла бы и по
    # FlClashCore.exe, и текст «Windows отказалась запускать ...» стал бы враньём про файл,
    # которого нет. Одна половина без другой пропускает ровно ту ошибку, которой боишься.
    own, files = 0, 0
    for path in list(pathlib.Path("arb").glob("*.arb")) + [
        pathlib.Path("lib/l10n/l10n.dart"),
    ] + sorted(pathlib.Path("lib/l10n/intl").glob("messages_*.dart")):
        txt = read(str(path))
        own += len(re.findall(r"FlClash(?!Core|Helper)", txt))
        files += txt.count("FlClashCore") + txt.count("FlClashHelper")
    check("в текстах ошибок не осталось чужого имени программы", own == 0, own)
    check("имена файлов FlClashCore/Helper в текстах целы (они так и называются)",
          files >= 16, files)

    print("\n— упаковщики: что они ищут и чем подписываются —")
    # ЭТОТ КЛАСС ДЕФЕКТА СТОИЛ ЦЕЛОГО ПРОГОНА ОБЛАКА (09-13): сборка выдаёт Mgla.app, а
    # упаковщик dmg искал FlClash.app — «не найдено» пришло с макоси через шесть минут после
    # того, как всё остальное уже собралось. Имя в сборке и имя в упаковщике — ДВА КОНЦА
    # одной строки, и проверять надо их равенство, а не каждое по отдельности.
    dmg = read("macos/packaging/dmg/make_config.yaml")
    check("macos: dmg ищет Mgla.app, а не чужое имя", "path: Mgla.app" in dmg)
    check("macos: заголовок окна dmg = Mgla", "title: Mgla" in dmg)
    wx = read("windows/packaging/exe/make_config.yaml")
    cmw = read("windows/CMakeLists.txt")
    binary = None
    m = re.search(r'set\(BINARY_NAME "([^"]+)"\)', cmw)
    if m:
        binary = m.group(1)
    exe = re.search(r"executable_name: (\S+)", wx)
    check("windows: установщик ищет ровно тот файл, который собирается",
          bool(binary and exe) and exe.group(1) == binary + ".exe",
          (binary, exe.group(1) if exe else None))
    # AppId = личность программы для Windows. Общий с апстримом означает установку ПОВЕРХ
    # чужой программы и общий деинсталлятор; человек увидит это уже после установки.
    check("windows: у установщика СВОЙ AppId, не апстримовский",
          "728B3532-C74B-4870-9068-BE70FE12A3E6" not in wx)
    check("windows: издатель в списке программ и в окне UAC — наш",
          "publisher: mglaapp" in wx and "chen08209" not in wx)
    check("windows: имя в установщике = Mgla",
          "app_name: Mgla" in wx and "display_name: Mgla" in wx)

    print("\n— состояние подключения: три признака, а не один цвет —")
    # Дизайн-код § 4: «Подключено» больше не зелёное, и состояние НИКОГДА не передаётся одним
    # цветом — рядом обязаны стоять слово и форма точки. Проверяется статически: глазами это
    # ловится только в одном из трёх состояний и только человеком, различающим цвет.
    pill = read("lib/views/dashboard/widgets/connection_state_pill.dart")
    dot = read("lib/widgets/state_dot.dart")
    check("признак 1 — СЛОВО: подпись берётся из локализации, а не из цвета",
          "appLocalizations.connected" in pill and "appLocalizations.disconnected" in pill)
    check("признак 2 — ФОРМА: точка залита только у работающего",
          "filled: state != _TunnelState.disconnected" in pill)
    check("форма читается сама: полая точка — прозрачная заливка при живой обводке",
          "filled ? color : Colors.transparent" in dot and "Border.all" in dot)
    check("признак 3 — ЦВЕТ: акцент темы у работающего, приглушённый у выключенного",
          "scheme.primary" in pill and "scheme.onSurfaceVariant" in pill)
    check("состояние объявлено экранному диктору (Semantics + liveRegion)",
          "Semantics(" in pill and "liveRegion: true" in pill)
    dash = read("lib/views/dashboard/dashboard.dart")
    check("плашка стоит на экране подключения, а не лежит мёртвым файлом",
          "connection_state_pill.dart" in dash and "ConnectionStatePill()" in dash)
    # Зелёный отменён дизайн-кодом (акцент один — лёд). Литерал Colors.green жил в статусе ядра
    # и красил «подключено» чужим цветом, мимо темы.
    green = []
    for f in sorted(pathlib.Path("lib").rglob("*.dart")):
        if "/generated/" in f.as_posix() or f.name.endswith(".g.dart"):
            continue
        if re.search(r"Colors\.green", read(str(f))):
            green.append(f.as_posix())
    check("зелёного литерала в интерфейсе нет (акцент один — лёд)", not green, green[:3])
    check("КОНТРОЛЬ: сам поиск зелёного работает",
          bool(re.search(r"Colors\.green", "backgroundColor: Colors.greenAccent,")))

    print("\n— ключ доступа: подписка без хождения за ссылкой —")
    # Смысл фичи в том, что человек НЕ носит адрес. Значит адрес обязан быть в приложении, и
    # обязан быть НАШИМ: чужой сайт здесь означает, что ключи наших людей уходят к кому-то ещё.
    ck = read("lib/common/access_key.dart")
    check("адрес подписки берётся из константы бренда, а не из литерала в коде",
          "subscriptionSite" in ck and "https://" not in ck)
    check("сайт подписки — наш", "const subscriptionSite = 'https://mgla.app';" in c)
    check("ключ превращается в адрес только по строгому образцу",
          "_keyPattern" in ck and "{16,64}" in ck)
    # Ссылка из буфера может оказаться какой угодно: file://, javascript: и прочее уехало бы
    # прямо в загрузчик профиля.
    check("чужие схемы ссылок отбиваются (в профиль идёт только http/https)",
          "uri.scheme != 'http'" in ck and "uri.scheme != 'https'" in ck)
    add = read("lib/views/profiles/add.dart")
    check("в меню добавления ключ стоит ПЕРВЫМ пунктом",
          add.index("appLocalizations.accessKey") < add.index("appLocalizations.qrcode"))
    prof = read("lib/views/profiles/profiles.dart")
    check("пустой список профилей предлагает действие, а не только подпись",
          "action: const AccessKeyButton()" in prof)
    dash2 = read("lib/views/dashboard/dashboard.dart")
    check("нет профиля -> первый экран просит ключ; есть -> показывает состояние",
          "hasProfile" in dash2 and "AccessKeyCard()" in dash2
          and "ConnectionStatePill()" in dash2)
    for lang in ("en", "ru", "ja", "zh_CN"):
        arb = read("arb/intl_%s.arb" % lang)
        check("подписи ключа переведены: %s" % lang,
              '"accessKey"' in arb and '"accessKeyDesc"' in arb and '"accessKeyTip"' in arb)

    print("\n— знак приложения: то, что человек видит на телефоне и в панели задач —")
    # 0.9.0 уехал публично с ЧУЖИМ знаком: имена проверялись, картинки — нет. Иконка лежит в
    # девяти местах, и достаточно одному вернуться при слиянии, чтобы у части людей на экране
    # снова оказался FlClash. Перерисовывает всё tool/mgla_icon.py.
    fg = read("android/app/src/main/res/drawable/ic_launcher_foreground.xml")
    check("android: знак нарисован льдом", 'android:fillColor="#7DD3FC"' in fg)
    for alien in ("#6666FB", "#336AB6", "#5CA8E9"):
        check("android: чужого цвета %s в знаке нет" % alien, alien not in fg)
    check("android: фон адаптивной иконки — наша ночь, а не белый апстрима",
          "#12161D" in read("android/app/src/main/res/values/ic_launcher_background.xml"))
    # Безопасная зона адаптивной иконки — центральные 72 из 108. Всё, что шире, обрезается
    # маской на части устройств, и «знак с обрезанными краями» увидит только владелец такого
    # телефона, то есть не мы.
    coords = [float(v) for v in re.findall(r"M(\d+\.\d+),", fg)]
    check("android: знак вписан в безопасную зону (не обрежется маской)",
          bool(coords) and min(coords) >= 18.0, coords[:2])

    def png_size(path: str) -> tuple[int, int] | None:
        try:
            raw = io.open(path, "rb").read(24)
        except OSError:
            return None
        if len(raw) < 24 or raw[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        return (int.from_bytes(raw[16:20], "big"), int.from_bytes(raw[20:24], "big"))

    for path, want in (
        ("assets/images/icon.png", 512),
        ("android/app/src/main/ic_launcher-playstore.png", 512),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png", 1024),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png", 16),
    ):
        check("картинка на месте и нужного размера: %s" % path.split("/")[-1],
              png_size(path) == (want, want), png_size(path))
    # У трея ДВА пути к одной картинке: наш скрипт и генератор апстрима на rsvg из
    # assets_source/*.svg. Пока исходник чужой, любой прогон генератора возвращает чужой знак.
    for state in (1, 2, 3):
        svg = read("assets_source/images/icon/status_%d.svg" % state)
        check("исходник трея %d нарисован нашим знаком" % state,
              "#7DD3FC" in svg or "#93A0B4" in svg, svg[:60])
    for path in ("windows/runner/resources/app_icon.ico", "assets/images/icon.ico"):
        try:
            head = io.open(path, "rb").read(6)
        except OSError:
            head = b""
        # Первые байты .ico: 0,0 (резерв), 1,0 (тип «иконка»), дальше число картинок внутри.
        check("windows/linux: %s собран и несёт несколько размеров" % path.split("/")[-1],
              head[:4] == b"\x00\x00\x01\x00" and int.from_bytes(head[4:6], "little") >= 5,
              head)

    print("\n— обновление изнутри приложения —")
    # Установщик закрывает процессы ПО ИМЕНИ, и имя нашего окна он не знал: список достался от
    # апстрима и перечислял FlClash.exe. Пока обновлялись руками, это почти не мешало; с
    # обновлением изнутри установка поверх РАБОТАЮЩЕГО приложения стала обычным делом, а файл
    # запущенной программы заменить нельзя. Имя берётся из CMakeLists, а не вписано сюда:
    # переименование сборки обязано ронять эту проверку, а не тихо разъезжаться с ней.
    iss = read("windows/packaging/exe/inno_setup.iss")
    binary = re.search(r'set\(BINARY_NAME "([^"]+)"\)', cm).group(1)
    check("установщик закрывает НАШЕ приложение перед заменой файлов",
          ("'%s.exe'" % binary) in iss, binary)
    check("установщик по-прежнему закрывает ядро и службу-помощник",
          "FlClashCore.exe" in iss and "FlClashHelperService.exe" in iss)

    am = read("android/app/src/main/AndroidManifest.xml")
    check("android: право ставить пакеты запрошено",
          "android.permission.REQUEST_INSTALL_PACKAGES" in am)
    # Установщику отдаётся content://-адрес: file:// система отвергает с Android 7. Authority
    # обязан нести ${applicationId} — иначе наша сборка и апстримовский FlClash рядом заявили бы
    # один и тот же адрес, и вторая установка упала бы при установке.
    check("android: FileProvider объявлен",
          "androidx.core.content.FileProvider" in am)
    check("android: authority провайдера привязан к нашему id",
          'android:authorities="${applicationId}.fileprovider"' in am)
    check("android: провайдер не вынесен наружу",
          re.search(r'<provider[^>]*android:exported="false"', am, re.S) is not None)
    check("android: провайдер отдаёт разрешение на свой адрес",
          'android:grantUriPermissions="true"' in am)

    # Папка, которую провайдер разрешает отдать, и папка, куда приложение кладёт файл, — это
    # ОДНО место, выраженное дважды. Разъедутся — установка упадёт на «нет доступа к файлу», и
    # причина будет не видна ни в коде Dart, ни в коде Kotlin по отдельности.
    fp = read("android/app/src/main/res/xml/file_paths.xml")
    check("android: провайдер отдаёт ровно одну папку кэша",
          fp.count("<cache-path") == 1 and 'path="update/"' in fp)
    flow = read("lib/providers/actions/common.dart")
    check("приложение кладёт обновление в ту же папку",
          "join((await appPath.cacheDir.future).path, 'update')" in flow)
    check("kotlin просит у провайдера тот же authority",
          '"${GlobalState.application.packageName}.fileprovider"' in read(
              "android/app/src/main/kotlin/com/follow/clash/plugins/AppPlugin.kt"))

    # Сумма проверяется ПЕРЕД установкой, и отсутствие суммы обязано ОСТАНАВЛИВАТЬ установку.
    # Проверка, которую пропускают при неудобстве, не проверка: ею закрыт ровно тот случай,
    # когда человеку ставится пакет, которого мы не публиковали.
    check("без контрольной суммы обновление не ставится",
          "expected == null" in flow and "updateVerifyFailed" in flow)
    check("скачанный файл удаляется, если он не идёт в установку",
          "if (!installing) {" in flow and "file?.safeDelete()" in flow)

    print("\n— КОНТРОЛЬ —")
    # Контроль обязан доказывать, что сравнение РАБОТАЕТ, и потому проверяется в ОБЕ стороны.
    # Один лишь пункт «чепухи в файле нет» проходит сам собой даже на пустой строке и контролем
    # не является вовсе — я написал его так с первого раза и переписал.
    check("КОНТРОЛЬ: заведомо ПРИСУТСТВУЮЩЕЕ найдено (сравнение живое)",
          "const appName" in c and "BINARY_NAME" in cm, (len(c), len(cm)))
    check("КОНТРОЛЬ: заведомо ОТСУТСТВУЮЩЕЕ не найдено",
          "const appName = 'ЗаведомоНеТо';" not in c)
    check("КОНТРОЛЬ: файлы действительно прочитаны, а не пусты",
          len(c) > 1000 and len(rc) > 500, (len(c), len(rc)))

    print("\n— пути к покупке и продлению: приложение не должно быть тупиком —")
    # Приложение выложено публично, и его ставят, ещё не купив доступ. Пока из него некуда
    # было пойти за подпиской, установка кончалась пустым экраном, а продление искали в
    # браузере по памяти. Адрес кабинета при этом обязан быть ОДИН: вписанный второй раз, он
    # переживёт первый при смене домена и уведёт человека в никуда в момент оплаты.
    check("кабинет собирается из адреса сайта, а не вписан второй раз",
          "const accountUrl = '$subscriptionSite/cab';" in c)
    ak = read("lib/views/profiles/access_key.dart")
    check("первый экран предлагает оформить подписку, а не только ввести ключ",
          "appLocalizations.getSubscription" in ak and "subscriptionSite" in ak)
    sv = read("lib/widgets/subscription_info_view.dart")
    check("продление стоит там, где показан срок",
          "appLocalizations.renewSubscription" in sv and "accountUrl" in sv)
    ab = read("lib/views/about.dart")
    check("в «О программе» есть наш сайт", "appLocalizations.website" in ab)
    # Кнопка «Telegram» вела в канал апстрима: человек, купивший подписку у нас, уходил из
    # нашего экрана к чужим людям. Своего канала нет, поэтому пока это бот входа.
    check("телеграм ведёт к нам, а не в канал апстрима",
          "telegramContact" in ab and "t.me/FlClash" not in ab)
    check("чужих участников в «О программе» не осталось",
          "Contributor" not in ab
          and not pathlib.Path("assets/images/avatar").exists()
          and "assets/images/avatar/" not in read("pubspec.yaml"))
    check("описание говорит о нас, а не об абстрактном клиенте",
          "mgla.app" in read("arb/intl_ru.arb").split('"desc":')[1].split("\n")[0])
    check("КОНТРОЛЬ: чужой канал опознался бы, будь он на месте",
          "t.me/FlClash" in "dialogs.openUrl('https://t.me/FlClash');")

    print("\n— подписка в приложении: аккаунт, статус, оплата без браузера —")
    sub = read("lib/views/subscription.dart")
    # Ключ не хранится вторым местом НАМЕРЕННО: он уже лежит в адресе профиля. Две копии
    # одного секрета расходятся молча, и расходятся ровно тогда, когда человек платит.
    check("ключ берётся из адреса профиля, а не хранится второй раз",
          "accessKeyOf(profile.url)" in sub)
    ak2 = read("lib/common/access_key.dart")
    check("разбор ключа отбивает ЧУЖОЙ адрес подписки",
          "value.startsWith(prefix)" in ak2 and "subscriptionSite" in ak2)
    req = read("lib/common/request.dart")
    check("адрес API собирается из константы бренда",
          "_apiBase = '$subscriptionSite/api/v1'" in req)
    # Отказ сервера приходит КОДОМ: текст на сервере один, а языков в приложении четыре.
    check("отказ показывается по коду, а не русской строкой сервера",
          "'unknown_key' =>" in sub and "data['error']" in req)
    # 4xx для нас ОТВЕТ, а не сбой: в нём лежит код. Без этого «ключ не найден» неотличим
    # от «нет сети», и человек идёт в поддержку с неверной жалобой.
    check("отказы 4xx читаются как ответ, а не как сбой сети",
          "validateStatus" in req)
    check("оплата USDT показывается, только когда сервер её подтвердил",
          "status.usdtEnabled" in sub)
    check("для карты кнопка честно уводит на сайт, а не притворяется оплатой",
          "payOnSite" in sub and "accountUrl" in sub)
    tools = read("lib/views/tools.dart")
    check("подписка стоит ПЕРВЫМ разделом инструментов, а не в «Другом»",
          "_getSubscriptionList()" in tools
          and tools.index("_getSubscriptionList()") < tools.index("_getOtherList("))
    for code in ("subscription", "createAccount", "payUsdt", "errUnknownKey"):
        check(f"надпись {code} переведена на все четыре языка",
              all(f'"{code}"' in read(f"arb/intl_{lang}.arb")
                  for lang in ("en", "ru", "ja", "zh_CN")))
    print("\n— возврат доступа: порядок способов и таймер на подтверждении —")
    # Решение владельца 16-09, то же, что на сайте 13-09: почта и телеграм вперёд, ссылка
    # последней. Пока ссылка стояла первой, она читалась как основной способ — а она равна
    # паролю и теряется вместе с устройством.
    check("почта идёт раньше телеграма, телеграм раньше ссылки входа",
          sub.index("l.bindEmail") < sub.index("l.bindTelegram") < sub.index("l.loginLinkTitle"))
    # Кнопка, доступная сразу, нажимается ДО чтения: человек подтверждает, что понял про
    # пароль, не прочитав про пароль. Отсчёт — цена одного прочтения.
    check("подтверждение недоступно, пока идёт отсчёт",
          "_countdown > 0" in sub and "onPressed: _countdown > 0" in sub)
    check("отсчёт не меньше трёх секунд",
          "_readSeconds = 4" in sub or "_readSeconds = 3" in sub)
    check("ссылка входа приложением НЕ хранится (её нет ни в одном хранилище)",
          "loginUrl" in sub and "SharedPreferences" not in sub and "setString" not in sub)
    check("экран возврата открывается и позже, но уже без ссылки",
          "RecoveryView(accessKey: status.key)" in sub)
    check("QR рисуется, только когда картинка пришла с сервера",
          "invoice.qrSvg.isNotEmpty" in sub and "SvgPicture.string" in sub)
    api_dart = read("lib/models/account.dart")
    check("пустой QR — рабочий случай, а не поломка", "qrSvg: json['qr_svg'] is String" in api_dart)
    for code in ("recoverAccess", "loginLinkWarning", "savedIt", "bindTelegram"):
        check(f"надпись {code} переведена на все четыре языка",
              all(f'"{code}"' in read(f"arb/intl_{lang}.arb")
                  for lang in ("en", "ru", "ja", "zh_CN")))

    print("\n— оплата картой: кнопка только под подтверждение сервера —")
    # Кнопка, ведущая в никуда, стоит дороже отсутствующей: человек уходит, решив, что сервис
    # сломан. Поэтому оба способа показываются, только когда сервер сказал, что они настроены.
    check("карта показывается по ответу сервера, а не всегда",
          "status.cardEnabled" in sub and "methods['card'] == true" in api_dart)
    check("оплата картой уходит в браузер, а не рисуется внутри",
          "_payCard" in sub and "dialogs.openUrl(result.data!)" in sub)
    # Лишний экран между человеком и оплатой — это люди, которые не доходят.
    check("выбор способа спрашивается ТОЛЬКО когда способов два",
          "if (status.usdtEnabled && !status.cardEnabled) return _pay(plan);" in sub
          and "if (status.cardEnabled && !status.usdtEnabled) return _payCard(plan);" in sub)
    check("когда не настроено ничего — честная ссылка на сайт, а не мёртвая кнопка",
          "l.payOnSite" in sub and "dialogs.openUrl(accountUrl)" in sub)
    for code in ("payCard", "choosePayment", "errCardOff"):
        check(f"надпись {code} переведена на все четыре языка",
              all(f'"{code}"' in read(f"arb/intl_{lang}.arb")
                  for lang in ("en", "ru", "ja", "zh_CN")))

    check("КОНТРОЛЬ: заведомо отсутствующая надпись НЕ находится во всех четырёх",
          not all('"ЗаведомоНетТакогоКлюча"' in read(f"arb/intl_{lang}.arb")
                  for lang in ("en", "ru", "ja", "zh_CN")))

    print(f"\nИТОГО: {_ok} PASS, {_fail} FAIL")
    return 1 if _fail else 0


if __name__ == "__main__":
    if not pathlib.Path("pubspec.yaml").is_file():
        print("запускать из корня репозитория")
        sys.exit(1)
    sys.exit(main())
