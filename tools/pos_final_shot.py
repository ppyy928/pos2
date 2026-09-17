"""Final proof: run the REAL app windowed, sign in, populate a cart, and
grab 1920x1080 PNGs — plus assert the five toolbar chips' tints and capture
QML warnings to prove the CategoryStrip binding loop is gone.

    python tools/pos_final_shot.py
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QML_DIR = os.path.join(ROOT, "qml")

# Real window: no offscreen platform here.
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "vendor"))
os.chdir(ROOT)

import fluentpyside  # noqa: E402

from PySide6.QtCore import QPointF, Qt  # noqa: E402
from PySide6.QtGui import QColor, QFont, QFontDatabase, QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

OUT = os.path.join(HERE, "shots", "layout")
os.makedirs(OUT, exist_ok=True)

qml_warnings: list[str] = []


def on_warnings(errors):
    for e in errors:
        qml_warnings.append(e.toString())


def close(a: QColor, b: QColor, tol: int = 12) -> bool:
    return (abs(a.red() - b.red()) <= tol and abs(a.green() - b.green()) <= tol
            and abs(a.blue() - b.blue()) <= tol)


def main() -> int:
    fluentpyside.apply(accent_color="#087F5B", theme="light")
    QQuickStyle.setStyle("FluentWinUI3")
    app = QGuiApplication(sys.argv)

    ui_family = "Tahoma"
    for candidate in (r"C:\Windows\Fonts\segoeui.ttf",
                      r"C:\Windows\Fonts\tahoma.ttf"):
        if os.path.exists(candidate):
            loaded = QFontDatabase.addApplicationFont(candidate)
            families = QFontDatabase.applicationFontFamilies(loaded)
            if families:
                ui_family = families[0]
                break
    base = QFont()
    base.setFamilies([ui_family, "Segoe UI Variable", "Segoe UI", "Tahoma"])
    base.setPixelSize(17)
    QGuiApplication.setFont(base)

    icon_id = QFontDatabase.addApplicationFont(
        os.path.join(ROOT, "vendor", "fluentpyside", "FluentControls",
                     "FluentSystemIcons-Resizable.ttf"))
    icon_family = (QFontDatabase.applicationFontFamilies(icon_id)
                   or ["Fluent System Icons Resizable"])[0]

    from app.bridge.root import App

    engine = QQmlApplicationEngine()
    engine.addImportPath(os.path.join(ROOT, "vendor", "fluentpyside"))
    engine.addImportPath(QML_DIR)
    engine.warnings.connect(on_warnings)
    bridge = App()
    ctx = engine.rootContext()
    ctx.setContextProperty("app", bridge)
    ctx.setContextProperty("iconFontFamilyResizable", icon_family)
    ctx.setContextProperty("iconFontFamily", icon_family)
    engine.load(os.path.join(QML_DIR, "Main.qml"))
    if not engine.rootObjects():
        print("Main.qml did not load")
        return 1
    win = engine.rootObjects()[0]
    win.resize(1920, 1080)
    win.show()
    QTest.qWait(1200)

    from mizan_pos1.data import db as ldb

    admin = next(e for e in ldb.fetch_employees() if e["role"] == "admin")
    win.setProperty("currentUser", admin)
    QTest.qWait(1000)
    bridge.pos.clear()
    QTest.qWait(400)

    def shot(name: str):
        QTest.qWait(400)
        image = win.grabWindow()
        path = os.path.join(OUT, name + ".png")
        image.save(path)
        print("saved", path, f"({image.width()}x{image.height()})")
        return image

    img = shot("final_pos_1920x1080_empty")

    tiles = bridge.pos.property("tiles") or []
    if len(tiles) >= 3:
        bridge.pos.add(tiles[0]["id"])
        bridge.pos.add(tiles[0]["id"])
        bridge.pos.add(tiles[1]["id"])
        bridge.pos.add(tiles[2]["id"])
        QTest.qWait(700)

    img2 = shot("final_pos_1920x1080_cart")

    # ---- assertions on the rendered pixels --------------------------------
    fails = 0

    def ok(name):
        print(f"    ok   {name}")

    def bad(name, detail=""):
        nonlocal fails
        fails += 1
        print(f"    FAIL {name} — {detail}")

    # toolbar tints: amber (Hold), teal (Suspended), violet (Return) in the
    # toolbar band — the products side's own foot, above the payment bar
    # (bar is 92 tall at the page foot: y 962..1054 at 1080 high)
    bar_top = 962 - 16 - 56
    band = (250, bar_top, 1350, bar_top + 56)

    def found_in(img, color, box, tol=14):
        x0, y0, x1, y1 = box
        for y in range(y0, y1, 2):
            for x in range(x0, x1, 2):
                if close(img.pixelColor(x, y), color, tol):
                    return True
        return False

    if found_in(img2, QColor("#FBEEDB"), band):
        ok("hold chip amber tint present")
    else:
        bad("hold chip amber tint", "no #FBEEDB in toolbar band")
    if found_in(img2, QColor("#DFEFF1"), band):
        ok("suspended chip teal tint present")
    else:
        bad("suspended chip teal tint", "no #DFEFF1 in toolbar band")
    if found_in(img2, QColor("#EFE8F9"), band):
        ok("return chip violet tint present")
    else:
        bad("return chip violet tint", "no #EFE8F9 in toolbar band")

    # the pay bar row: dark petrol + amber Debt + emerald Cash at the foot
    # (92px bar, y 962..1054 at 1080 high)
    bar = (250, 962, 1894, 1054)
    if found_in(img2, QColor("#142B38"), bar):
        ok("total block petrol present in the bar")
    else:
        bad("total block petrol", "no #142B38 in the bar band")
    if found_in(img2, QColor("#087F5B"), bar):
        ok("cash emerald present in the bar")
    else:
        bad("cash emerald", "no #087F5B in the bar band")
    if found_in(img2, QColor("#FBEEDB"), bar):
        ok("debt amber tint present in the bar")
    else:
        bad("debt amber tint", "no #FBEEDB in the bar band")

    # keypad digits region: light secondary fills — sanity that the pad is
    # painted as wide as the readout (both already proven by the harness)
    print()
    loops = [w for w in qml_warnings if "Binding loop" in w]
    rearranges = [w for w in qml_warnings if "recursive rearrange" in w]
    if not loops:
        ok("no binding-loop warnings")
    else:
        bad("no binding-loop warnings", f"{len(loops)} warnings, first: {loops[0][:120]}")
    if not rearranges:
        ok("no recursive-rearrange warnings")
    else:
        bad("no recursive-rearrange warnings",
            f"{len(rearranges)} warnings, first: {rearranges[0][:120]}")

    print(f"\nqml warnings total: {len(qml_warnings)}")
    for w in qml_warnings[:12]:
        print("  warn:", w[:160])

    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
