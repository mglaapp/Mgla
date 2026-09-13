# -*- coding: utf-8 -*-
"""Знак Mgla во все размеры, которые требует каждая платформа.

    python tool/mgla_icon.py            # перерисовать всё
    python tool/mgla_icon.py --check    # только сказать, что не на месте

ЗАЧЕМ ИНСТРУМЕНТ, А НЕ ОДИН РАЗ РУКАМИ. Иконка лежит в девяти местах в трёх форматах, и после
слияния с апстримом любое из них может вернуться к чужому знаку. Нарисованное скриптом
перерисовывается одной командой и сверяется другой.

ЗНАК. Четыре горизонтальные полосы убывающей плотности на тёмном скруглённом квадрате —
дизайн-код § 2. Оба прочтения верные и нужные: слои мглы и шкала сигнала. Пропорции те же, что
у фавикона сайта (viewBox 32): полосы начинаются с x=6, высота 3, радиус 1.5, длины 20/20/15/9,
прозрачность 1/.62/.34/.18.

ANDROID РИСУЕТСЯ ОТДЕЛЬНО. У адаптивной иконки система сама кладёт свою маску поверх, и всё,
что выходит за центральные 66%, обрезается на части устройств. Поэтому там знак без подложки и
вписан в безопасную зону, а фон задан цветом в ic_launcher_background.xml.
"""
from __future__ import annotations

import pathlib
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:                              # noqa: BLE001
    print("нужен Pillow: pip install pillow")
    raise SystemExit(2)

ROOT = pathlib.Path(__file__).resolve().parent.parent

BG = (0x12, 0x16, 0x1D, 255)
ICE = (0x7D, 0xD3, 0xFC)
# x, y, ширина, высота, прозрачность — в координатах viewBox 32, как в фавиконе сайта.
BARS = [(6, 8, 20, 3, 1.0), (6, 14, 20, 3, 0.62), (6, 20, 15, 3, 0.34), (6, 26, 9, 3, 0.18)]
VIEWBOX = 32
CORNER = 7                                       # радиус подложки в тех же координатах

PNG_TARGETS = {
    "assets/images/icon.png": 512,
    "android/app/src/main/ic_launcher-playstore.png": 512,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": 16,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": 32,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": 64,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": 128,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": 256,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": 512,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": 1024,
}
ICO_TARGETS = ["windows/runner/resources/app_icon.ico", "assets/images/icon.ico"]
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

SUPERSAMPLE = 8                                  # рисуем крупно и уменьшаем: края без лесенки

# Трей: три состояния, которые различает tray.dart — 1 выключено, 2 работает, 3 работает
# через TUN. Знак тот же, читается формой; состояние даёт ЦВЕТ и плотность полос. Слова в
# трее нет вовсе, поэтому здесь два признака из трёх, а третий — подсказка при наведении.
TRAY_DIM = (0x93, 0xA0, 0xB4)
TRAY_STATES = {1: (TRAY_DIM, False), 2: (ICE, False), 3: (ICE, True)}
TRAY_UNIX_SCALES = {"": 18, "2.0x": 36, "3.0x": 54, "4.0x": 72}
TRAY_ICO_SIZES = [16, 20, 24, 32, 40, 48, 64]
TRAY_FILL = 0.88                                 # доля квадрата под знак, остальное — поле


def draw(size: int, *, plate: bool = True, inset: float = 1.0) -> Image.Image:
    """Знак размером size. plate=False — только полосы (для адаптивной иконки Android)."""
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = big / VIEWBOX * inset
    pad = (big - VIEWBOX * k) / 2
    if plate:
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius=CORNER * big / VIEWBOX, fill=BG)
    for x, y, w, h, alpha in BARS:
        box = [pad + x * k, pad + y * k, pad + (x + w) * k, pad + (y + h) * k]
        # На подложке прозрачность СМЕШИВАЕТСЯ с ней заранее, а не остаётся в альфа-канале:
        # рисовалка заменяет пиксели, а не накладывает их, и полупрозрачная полоса пропускала
        # бы сквозь себя фон системы — в панели задач знак выглядел бы выцветшим.
        fill = (tuple(round(c * alpha + b * (1 - alpha)) for c, b in zip(ICE, BG[:3])) + (255,)
                if plate else ICE + (round(255 * alpha),))
        d.rounded_rectangle(box, radius=h * k / 2, fill=fill)
    return img.resize((size, size), Image.LANCZOS)


def draw_tray(size: int, state: int) -> Image.Image:
    """Знак для трея: без подложки, чтобы лечь на панель любого цвета."""
    colour, full = TRAY_STATES[state]
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    left_edge = min(x for x, _, _, _, _ in BARS)
    right_edge = max(x + w for x, _, w, _, _ in BARS)
    top_edge = min(y for _, y, _, _, _ in BARS)
    bottom_edge = max(y + h for _, y, _, h, _ in BARS)
    # Поле по краям: в трее знак стоит впритык к соседям, и без него он слипается с ними.
    k = big * TRAY_FILL / max(right_edge - left_edge, bottom_edge - top_edge)
    pad_x = (big - (right_edge - left_edge) * k) / 2 - left_edge * k
    pad_y = (big - (bottom_edge - top_edge) * k) / 2 - top_edge * k
    for x, y, w, h, alpha in BARS:
        box = [pad_x + x * k, pad_y + y * k, pad_x + (x + w) * k, pad_y + (y + h) * k]
        value = 1.0 if full else alpha
        d.rounded_rectangle(box, radius=h * k / 2, fill=colour + (round(255 * value),))
    return img.resize((size, size), Image.LANCZOS)


def write_tray() -> None:
    for state in TRAY_STATES:
        for folder, size in TRAY_UNIX_SCALES.items():
            rel = "/".join(x for x in ("assets/images/tray/unix", folder,
                                       "status_%d.png" % state) if x)
            path = ROOT / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            draw_tray(size, state).save(path, format="PNG")
        rel = "assets/images/tray/windows/status_%d.ico" % state
        draw_tray(max(TRAY_ICO_SIZES), state).save(
            ROOT / rel, format="ICO", sizes=[(s, s) for s in TRAY_ICO_SIZES])
        print("  трей, состояние %d: png x%d + ico" % (state, len(TRAY_UNIX_SCALES)))


def tray_svg(state: int) -> str:
    """Исходник трей-иконки. Холст 108 — тот же, что у апстрима, чтобы генератор на rsvg
    отдавал прежние размеры."""
    colour, full = TRAY_STATES[state]
    view = 108.0
    left_edge = min(x for x, _, _, _, _ in BARS)
    right_edge = max(x + w for x, _, w, _, _ in BARS)
    top_edge = min(y for _, y, _, _, _ in BARS)
    bottom_edge = max(y + h for _, y, _, h, _ in BARS)
    k = view * TRAY_FILL / max(right_edge - left_edge, bottom_edge - top_edge)
    pad_x = (view - (right_edge - left_edge) * k) / 2 - left_edge * k
    pad_y = (view - (bottom_edge - top_edge) * k) / 2 - top_edge * k
    hex_colour = "#%02X%02X%02X" % colour
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<svg width="108" height="108" viewBox="0 0 108 108"'
           ' xmlns="http://www.w3.org/2000/svg">',
           '    <title>status_%d</title>' % state]
    for x, y, w, h, alpha in BARS:
        out.append('    <rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f"'
                   ' fill="%s" fill-opacity="%.2f"/>'
                   % (pad_x + x * k, pad_y + y * k, w * k, h * k, h * k / 2,
                      hex_colour, 1.0 if full else alpha))
    out.append('</svg>')
    return "\n".join(out) + "\n"


def write_tray_sources() -> None:
    for state in TRAY_STATES:
        rel = "assets_source/images/icon/status_%d.svg" % state
        path = ROOT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(tray_svg(state), encoding="utf-8")
        print("  %s" % rel)


def write_png(rel: str, size: int) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    draw(size).save(path, format="PNG")
    print(f"  {rel}  {size}x{size}")


def write_ico(rel: str) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    base = draw(max(ICO_SIZES))
    base.save(path, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    print(f"  {rel}  {', '.join(str(s) for s in ICO_SIZES)}")


def android_vector() -> str:
    """Передний план адаптивной иконки: только полосы, вписанные в безопасную зону.

    viewportWidth 108 — контракт Android; безопасная зона там 72 из 108 по центру, поэтому
    знак рисуется в этих 72 и ни на пиксель шире.
    """
    safe, view = 72.0, 108.0
    # Считаем по ФАКТИЧЕСКИМ границам полос, а не по viewBox: в исходном знаке они занимают
    # не весь квадрат (сверху 8, снизу 3), и посадка по viewBox дала бы знак мелким и съехавшим
    # вниз — на телефоне это единственное, что человек видит.
    left_edge = min(x for x, _, _, _, _ in BARS)
    right_edge = max(x + w for x, _, w, _, _ in BARS)
    top_edge = min(y for _, y, _, _, _ in BARS)
    bottom_edge = max(y + h for _, y, _, h, _ in BARS)
    k = safe / max(right_edge - left_edge, bottom_edge - top_edge)
    pad_x = (view - (right_edge - left_edge) * k) / 2 - left_edge * k
    pad_y = (view - (bottom_edge - top_edge) * k) / 2 - top_edge * k
    lines = ['<vector xmlns:android="http://schemas.android.com/apk/res/android"',
             '        android:width="108dp"',
             '        android:height="108dp"',
             '        android:viewportWidth="108"',
             '        android:viewportHeight="108">']
    for x, y, w, h, alpha in BARS:
        left, top = pad_x + x * k, pad_y + y * k
        right, bottom = pad_x + (x + w) * k, pad_y + (y + h) * k
        radius = h * k / 2
        lines.append('    <path')
        lines.append('            android:pathData="M%.2f,%.2f h%.2f a%.2f,%.2f 0 0 1 0,%.2f '
                     'h-%.2f a%.2f,%.2f 0 0 1 0,-%.2f z"'
                     % (left + radius, top, right - left - 2 * radius, radius, radius,
                        bottom - top, right - left - 2 * radius, radius, radius, bottom - top))
        lines.append('            android:fillColor="#7DD3FC"')
        lines.append('            android:fillAlpha="%.2f"/>' % alpha)
    lines.append('</vector>')
    return "\n".join(lines) + "\n"


def main() -> int:
    check_only = "--check" in sys.argv
    if check_only:
        missing = [rel for rel in list(PNG_TARGETS) + ICO_TARGETS
                   if not (ROOT / rel).is_file()]
        print("нет файлов: %s" % (missing or "ни одного"))
        return 1 if missing else 0

    print("== PNG")
    for rel, size in PNG_TARGETS.items():
        write_png(rel, size)
    print("== ICO")
    for rel in ICO_TARGETS:
        write_ico(rel)
    print("== Трей")
    write_tray()
    print("== Исходники трея (из них генератор апстрима делает то же самое)")
    write_tray_sources()
    print("== Android")
    fg = ROOT / "android/app/src/main/res/drawable/ic_launcher_foreground.xml"
    fg.write_text(android_vector(), encoding="utf-8")
    print(f"  {fg.relative_to(ROOT)}")
    bg = ROOT / "android/app/src/main/res/values/ic_launcher_background.xml"
    bg.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                  '    <color name="ic_launcher_background">#12161D</color>\n</resources>\n',
                  encoding="utf-8")
    print(f"  {bg.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
