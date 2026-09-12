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

    print(f"\nИТОГО: {_ok} PASS, {_fail} FAIL")
    return 1 if _fail else 0


if __name__ == "__main__":
    if not pathlib.Path("pubspec.yaml").is_file():
        print("запускать из корня репозитория")
        sys.exit(1)
    sys.exit(main())
