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
