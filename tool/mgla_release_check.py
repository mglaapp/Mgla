# -*- coding: utf-8 -*-
"""Сверка того, ЧТО ПРИЛОЖЕНИЕ ИЩЕТ, с тем, ЧТО МЫ ВЫЛОЖИЛИ.

    python tool/mgla_release_check.py                # последний выпуск
    python tool/mgla_release_check.py --tag v0.9.1   # конкретный

ЗАЧЕМ ОТДЕЛЬНЫЙ, СЕТЕВОЙ ИНСТРУМЕНТ. Обновление изнутри приложения держится на совпадении двух
списков, которые живут в РАЗНЫХ местах: суффиксы имён в lib/common/app_update.dart — у нас в
репозитории, а сами имена файлов даёт упаковщик (flutter_distributor) уже в облаке. Сверить их
статически нечем, поэтому сверяем по факту — по выложенному выпуску.

ЧТО ЛОВИТ. Переименование артефакта в упаковщике, недособранную платформу, пропавший
SHA256SUMS и строку в нём, не совпавшую с именем файла. Любое из этого превращает кнопку
«Обновить» в тишину или в отказ у человека на телефоне, и увидеть это по коду нельзя.

ВЫХОД: 0 — всё сходится, 1 — не сходится, 2 — не смог проверить (сеть, нет выпуска).
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

REPO = "mglaapp/Mgla"
ROOT = pathlib.Path(__file__).resolve().parent.parent

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


def suffixes() -> list[str]:
    """Суффиксы из app_update.dart — источник правды именно тот, по которому ходит приложение."""
    source = (ROOT / "lib/common/app_update.dart").read_text(encoding="utf-8")
    found = re.findall(r"=> '(-[^']+)'", source)
    if not found:
        print("не нашёл ни одного суффикса в lib/common/app_update.dart", file=sys.stderr)
        sys.exit(2)
    return found


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "mgla-release-check"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="метка выпуска; по умолчанию последний")
    args = parser.parse_args()

    url = (
        f"https://api.github.com/repos/{REPO}/releases/tags/{args.tag}"
        if args.tag
        else f"https://api.github.com/repos/{REPO}/releases/latest"
    )
    try:
        release = json.loads(fetch(url))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as error:
        print(f"выпуск не прочитан: {error}", file=sys.stderr)
        return 2

    tag = release.get("tag_name")
    assets = {a["name"]: a for a in release.get("assets", [])}
    print(f"выпуск {tag}, файлов {len(assets)}\n")

    print("— приложение найдёт свой файл —")
    for suffix in suffixes():
        matching = [name for name in assets if name.endswith(suffix)]
        check(f"ровно один файл на {suffix}", len(matching) == 1, matching)

    print("\n— контрольные суммы —")
    sums_asset = assets.get("SHA256SUMS")
    check("SHA256SUMS выложен", sums_asset is not None)
    if sums_asset is None:
        print(f"\nИТОГО: {_ok} PASS, {_fail} FAIL")
        return 1
    try:
        sums = fetch(sums_asset["browser_download_url"]).decode("utf-8")
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as error:
        print(f"SHA256SUMS не скачан: {error}", file=sys.stderr)
        return 2
    listed = {
        line.split()[-1].lstrip("./"): line.split()[0]
        for line in sums.splitlines()
        if len(line.split()) >= 2
    }
    for suffix in suffixes():
        for name in [n for n in assets if n.endswith(suffix)]:
            # Приложение отказывается ставить файл, суммы которого нет в списке. Расхождение
            # имён здесь означает не «нет проверки», а «обновление не пойдёт вовсе».
            check(f"сумма есть для {name}", name in listed)

    print("\n— КОНТРОЛЬ —")
    # Без этого набор доказывает только то, что сравнение что-то печатает: заведомо
    # отсутствующего файла быть не должно, а заведомо присутствующий обязан находиться.
    check("КОНТРОЛЬ: выдуманного файла в выпуске нет",
          not [n for n in assets if n.endswith("-plan9-riscv.tar.gz")])
    check("КОНТРОЛЬ: список файлов вообще прочитан", len(assets) > 1, len(assets))
    check("КОНТРОЛЬ: список сумм вообще прочитан", len(listed) > 1, len(listed))

    print(f"\nИТОГО: {_ok} PASS, {_fail} FAIL")
    return 1 if _fail else 0


if __name__ == "__main__":
    sys.exit(main())
