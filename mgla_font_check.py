#!/usr/bin/env python3
"""Проверка, что шрифты действительно покрывают кириллицу. Из корня репозитория.

ЗАЧЕМ ОТДЕЛЬНАЯ ПРОВЕРКА. Аудитория Mgla русская. Шрифт без кириллицы не падает и не ругается —
система молча подставляет другой, и текст просто выглядит чужим. Увидели бы мы это только на
скриншоте у человека, а до тех пор считали бы, что дизайн-код применён.

ЧИТАЕМ САМ ФАЙЛ, а не название и не описание на сайте: «IBM Plex поддерживает кириллицу» —
утверждение о СЕМЕЙСТВЕ, а нам приезжает конкретный файл конкретной сборки.

Разбор минимальный: таблица cmap, форматы 4 и 12. Полноценный fontTools ради трёх файлов не
ставим.
"""
import io
import struct
import sys

PROBE = {
    "А": 0x0410, "я": 0x044F, "Ё": 0x0401, "ё": 0x0451,
    "A": 0x0041, "0": 0x0030, "—": 0x2014,
}

FILES = [
    "assets/fonts/IBMPlexSans.ttf",
    "assets/fonts/IBMPlexMono-Regular.ttf",
    "assets/fonts/IBMPlexMono-SemiBold.ttf",
]


def cmap_codepoints(path: str) -> set[int]:
    data = io.open(path, "rb").read()
    num_tables = struct.unpack(">H", data[4:6])[0]
    cmap_off = None
    for i in range(num_tables):
        rec = 12 + i * 16
        if data[rec:rec + 4] == b"cmap":
            cmap_off = struct.unpack(">I", data[rec + 8:rec + 12])[0]
            break
    if cmap_off is None:
        raise ValueError("в файле нет таблицы cmap")

    n = struct.unpack(">H", data[cmap_off + 2:cmap_off + 4])[0]
    codes: set[int] = set()
    for i in range(n):
        rec = cmap_off + 4 + i * 8
        sub = cmap_off + struct.unpack(">I", data[rec + 4:rec + 8])[0]
        fmt = struct.unpack(">H", data[sub:sub + 2])[0]
        if fmt == 4:
            seg_x2 = struct.unpack(">H", data[sub + 6:sub + 8])[0]
            seg = seg_x2 // 2
            ends = struct.unpack(f">{seg}H", data[sub + 14:sub + 14 + seg_x2])
            starts_off = sub + 16 + seg_x2
            starts = struct.unpack(f">{seg}H", data[starts_off:starts_off + seg_x2])
            for s, e in zip(starts, ends):
                if e == 0xFFFF:
                    continue
                codes.update(range(s, e + 1))
        elif fmt == 12:
            ngroups = struct.unpack(">I", data[sub + 12:sub + 16])[0]
            for g in range(ngroups):
                off = sub + 16 + g * 12
                s, e = struct.unpack(">II", data[off:off + 8])
                codes.update(range(s, min(e, s + 0x10000) + 1))
    return codes


def main() -> int:
    bad = 0
    for path in FILES:
        try:
            codes = cmap_codepoints(path)
        except (OSError, ValueError, struct.error) as e:
            print(f"FAIL  {path}: не разобрался ({e})")
            bad += 1
            continue
        missing = [ch for ch, cp in PROBE.items() if cp not in codes]
        cyr = sum(1 for cp in range(0x0400, 0x0500) if cp in codes)
        if missing:
            print(f"FAIL  {path}: нет знаков {missing}")
            bad += 1
        else:
            print(f"PASS  {path}: кириллица есть ({cyr} знаков блока U+0400..04FF), тире и цифры тоже")

    # КОНТРОЛЬ: знак, которого в шрифте заведомо нет. Если он «нашёлся», разбор врёт и все
    # зелёные строки выше ничего не стоят.
    codes = cmap_codepoints(FILES[0])
    absent = 0x1F600  # эмодзи-смайл: в текстовом шрифте его быть не должно
    print(f"КОНТРОЛЬ: заведомо отсутствующий знак U+1F600 "
          f"{'НАЙДЕН — разбор врёт' if absent in codes else 'не найден, как и ожидалось'}")
    if absent in codes:
        bad += 1

    print(f"\nИТОГО: {'ОК' if not bad else f'{bad} проблем'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
