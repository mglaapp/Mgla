# -*- coding: utf-8 -*-
"""Знак Mgla во все размеры, которые требует каждая платформа.

    python tool/mgla_icon.py            # перерисовать всё
    python tool/mgla_icon.py --check    # только сказать, что не на месте или чужое

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

СТАРЫЕ СИСТЕМЫ И ТЕЛЕВИЗОР (18-10). Адаптивную иконку читает Android 8+, а minSdk у Flutter — 21:
Android 5-7 и дешёвые ТВ-приставки берут растр webp, квадратный и круглый. Телевизор, кроме того,
показывает свой знак (mipmap-television, ic_launcher_foreground_tv) и баннер 320x180 в ряду
приложений. Всё это до 18-10 было знаком FlClash — скрипт эти файлы не знал.

СВЕРКА. Каждый растр, записанный скриптом, ложится в tool/mgla_icon.sha256 со своим хешем;
mgla_check.py и --check сверяют файлы с ним. Слияние, вернувшее любую картинку апстрима, краснеет.
"""
from __future__ import annotations

import hashlib
import pathlib
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
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

FG = (0xE6, 0xEA, 0xF2)                          # --fg сайта: имя на баннере ТВ
FONT = ROOT / "assets/fonts/IBMPlexSans.ttf"
RES = "android/app/src/main/res"
WEBP_PHONE = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
WEBP_TV = {"mdpi": 80, "hdpi": 120, "xhdpi": 160, "xxhdpi": 240, "xxxhdpi": 320}  # тест апстрима
BANNER = (RES + "/mipmap-xhdpi/ic_banner.png", 320, 180)
# Границы знака апстрима, которые стережёт test/android_tv_launcher_icon_test.dart: наш знак вписан
# ВНУТРЬ них, поэтому тест, не зная нашего знака, остаётся правдой и про него.
TV_LOGO_BOUNDS = (54.0, 33.0, 179.0, 206.5)
TV_VIEW, TV_SCALE = 240.0, 0.9
MANIFEST = "tool/mgla_icon.sha256"
WRITTEN: list[str] = []


def bars_box() -> tuple[float, float, float, float]:
    """Фактические границы полос в координатах viewBox: left, top, right, bottom."""
    return (min(x for x, _, _, _, _ in BARS), min(y for _, y, _, _, _ in BARS),
            max(x + w for x, _, w, _, _ in BARS), max(y + h for _, y, _, h, _ in BARS))


def draw(size: int, *, plate: bool = True, inset: float = 1.0, shape: str = "rounded") -> Image.Image:
    """Знак размером size. plate=False — только полосы (для адаптивной иконки Android);
    shape="circle" — круглая подложка (ic_launcher_round у Android 5-7)."""
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = big / VIEWBOX * inset
    pad = (big - VIEWBOX * k) / 2
    if plate and shape == "circle":
        d.ellipse([0, 0, big - 1, big - 1], fill=BG)
    elif plate:
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
            WRITTEN.append(rel)
        rel = "assets/images/tray/windows/status_%d.ico" % state
        draw_tray(max(TRAY_ICO_SIZES), state).save(
            ROOT / rel, format="ICO", sizes=[(s, s) for s in TRAY_ICO_SIZES])
        WRITTEN.append(rel)
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


# newline="\n" ВЕЗДЕ: на Windows write_text переводит \n в \r\n, и каждый прогон
# «менял» три файла, ничего в них не меняя.
def write_tray_sources() -> None:
    for state in TRAY_STATES:
        rel = "assets_source/images/icon/status_%d.svg" % state
        path = ROOT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(tray_svg(state), encoding="utf-8", newline="\n")
        print("  %s" % rel)


def write_png(rel: str, size: int) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    draw(size).save(path, format="PNG")
    WRITTEN.append(rel)
    print(f"  {rel}  {size}x{size}")


def write_ico(rel: str) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    base = draw(max(ICO_SIZES))
    base.save(path, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    WRITTEN.append(rel)
    print(f"  {rel}  {', '.join(str(s) for s in ICO_SIZES)}")


def write_webp(rel: str, size: int, shape: str = "rounded") -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    # круг: знак чуть меньше, чтобы углы верхней полосы не подходили к краю окружности
    draw(size, shape=shape, inset=0.9 if shape == "circle" else 1.0).save(path, format="WEBP", lossless=True)
    WRITTEN.append(rel)
    print(f"  {rel}  {size}x{size}")


def draw_banner(width: int, height: int) -> Image.Image:
    """Баннер Android TV: ночь, знак слева, имя справа. Непрозрачный — так требует Android TV."""
    s = SUPERSAMPLE
    img = Image.new("RGB", (width * s, height * s), BG[:3])
    d = ImageDraw.Draw(img)
    left, top, right, bottom = bars_box()
    k = height * s * 0.4 / (bottom - top)
    font = ImageFont.truetype(str(FONT), round(height * s * 0.34))
    font.set_variation_by_axes([600, 100])
    name = "Mgla"
    text_w = d.textlength(name, font=font)
    cap_top = font.getbbox("M", anchor="ls")[1]          # отрицательная высота заглавной от базовой
    gap = height * s * 0.12
    mark_w = (right - left) * k
    x0 = (width * s - (mark_w + gap + text_w)) / 2
    pad_x = x0 - left * k
    pad_y = (height * s - (bottom - top) * k) / 2 - top * k
    for x, y, w, h, alpha in BARS:
        fill = tuple(round(c * alpha + b * (1 - alpha)) for c, b in zip(ICE, BG[:3]))
        d.rounded_rectangle([pad_x + x * k, pad_y + y * k, pad_x + (x + w) * k, pad_y + (y + h) * k],
                            radius=h * k / 2, fill=fill)
    d.text((x0 + mark_w + gap, (height * s - cap_top) / 2), name, font=font, fill=FG, anchor="ls")
    return img.resize((width, height), Image.LANCZOS)


def write_banner() -> None:
    rel, width, height = BANNER
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    draw_banner(width, height).save(path, format="PNG")
    WRITTEN.append(rel)
    print(f"  {rel}  {width}x{height}")


def file_sha(rel: str) -> str:
    return hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()


def write_manifest() -> None:
    lines = ["%s  %s" % (file_sha(rel), rel) for rel in sorted(set(WRITTEN))]
    (ROOT / MANIFEST).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"  {MANIFEST}: {len(lines)} файлов")


def manifest_problems() -> list[str]:
    """Что не совпало с последней перерисовкой: файла нет, или он не тот, что рисовал скрипт."""
    path = ROOT / MANIFEST
    if not path.is_file():
        return [f"нет {MANIFEST} — перерисуйте: python tool/mgla_icon.py"]
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        sha, rel = line.split("  ", 1)
        if not (ROOT / rel).is_file():
            out.append(f"нет файла {rel}")
        elif file_sha(rel) != sha:
            out.append(f"чужая картинка {rel}")
    return out


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
    lines += bar_paths(k, pad_x, pad_y, "    ")
    lines.append('</vector>')
    return "\n".join(lines) + "\n"


def bar_paths(k: float, pad_x: float, pad_y: float, pre: str) -> list[str]:
    """Полосы знака путями VectorDrawable: масштаб k, сдвиг pad, отступ строк pre."""
    lines = []
    for x, y, w, h, alpha in BARS:
        left, top = pad_x + x * k, pad_y + y * k
        right, bottom = pad_x + (x + w) * k, pad_y + (y + h) * k
        radius = h * k / 2
        lines.append(pre + '<path')
        lines.append(pre + '        android:pathData="M%.2f,%.2f h%.2f a%.2f,%.2f 0 0 1 0,%.2f '
                     'h-%.2f a%.2f,%.2f 0 0 1 0,-%.2f z"'
                     % (left + radius, top, right - left - 2 * radius, radius, radius,
                        bottom - top, right - left - 2 * radius, radius, radius, bottom - top))
        lines.append(pre + '        android:fillColor="#7DD3FC"')
        lines.append(pre + '        android:fillAlpha="%.2f"/>' % alpha)
    return lines


def tv_vector() -> str:
    """Знак Android TV (mipmap-television-anydpi-v26): холст 240 и группа с масштабом и сдвигом —
    в этой форме его читает тест апстрима. Полосы вписаны в TV_LOGO_BOUNDS, группа ставит центр
    этих границ в центр холста."""
    bl, bt, br, bb = TV_LOGO_BOUNDS
    left, top, right, bottom = bars_box()
    k = min((br - bl) / (right - left), (bb - bt) / (bottom - top))
    cx, cy = (bl + br) / 2, (bt + bb) / 2
    pad_x = cx - (left + right) / 2 * k
    pad_y = cy - (top + bottom) / 2 * k
    lines = ['<vector xmlns:android="http://schemas.android.com/apk/res/android"',
             '        android:width="108dp"',
             '        android:height="108dp"',
             '        android:viewportWidth="%g"' % TV_VIEW,
             '        android:viewportHeight="%g">' % TV_VIEW,
             '    <group',
             '        android:scaleX="%g"' % TV_SCALE,
             '        android:scaleY="%g"' % TV_SCALE,
             '        android:translateX="%.3f"' % (TV_VIEW / 2 - cx * TV_SCALE),
             '        android:translateY="%.3f">' % (TV_VIEW / 2 - cy * TV_SCALE)]
    lines += bar_paths(k, pad_x, pad_y, "        ")
    lines += ['    </group>', '</vector>']
    return "\n".join(lines) + "\n"


def main() -> int:
    check_only = "--check" in sys.argv
    if check_only:
        missing = [rel for rel in list(PNG_TARGETS) + ICO_TARGETS
                   if not (ROOT / rel).is_file()]
        problems = manifest_problems()
        print("нет файлов: %s" % (missing or "ни одного"))
        print("не совпало с перерисовкой: %s" % (problems or "ничего"))
        return 1 if missing or problems else 0

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
    fg.write_text(android_vector(), encoding="utf-8", newline="\n")
    print(f"  {fg.relative_to(ROOT)}")
    bg = ROOT / "android/app/src/main/res/values/ic_launcher_background.xml"
    bg.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                  '    <color name="ic_launcher_background">#12161D</color>\n</resources>\n',
                  encoding="utf-8", newline="\n")
    print(f"  {bg.relative_to(ROOT)}")
    tv = ROOT / RES / "drawable/ic_launcher_foreground_tv.xml"
    tv.write_text(tv_vector(), encoding="utf-8", newline="\n")
    print(f"  {tv.relative_to(ROOT)}")
    print("== Android 5-7 и телевизор: растр и баннер")
    for dpi, size in WEBP_PHONE.items():
        write_webp(f"{RES}/mipmap-{dpi}/ic_launcher.webp", size)
        write_webp(f"{RES}/mipmap-{dpi}/ic_launcher_round.webp", size, shape="circle")
    for dpi, size in WEBP_TV.items():
        write_webp(f"{RES}/mipmap-television-{dpi}/ic_launcher.webp", size)
    write_banner()
    print("== Сверка")
    write_manifest()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
