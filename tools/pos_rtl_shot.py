"""RTL proof: run the POS page in Arabic and verify the layout mirrors —
the transaction panel swaps to the LEFT edge, the payment bar still spans
the full width at the bottom, and the toolbar still sits between the
category strip and the grid.

    python tools/pos_rtl_shot.py
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QML_DIR = os.path.join(ROOT, "qml")

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "vendor"))
os.chdir(ROOT)

import fluentpyside  # noqa: E402

from PySide6.QtCore import QPointF  # noqa: E402
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402


def walk_all(obj):
    import queue
    todo = queue.Queue(); todo.put(obj)
    while not todo.empty():
        try:
            o = todo.get(); yield o
            for k in o.children(): todo.put(k)
        except RuntimeError:
            continue


def main() -> int:
    fluentpyside.apply(accent_color="#087F5B", theme="light")
    QQuickStyle.setStyle("FluentWinUI3")
    app = QGuiApplication(sys.argv)
    base = QFont()
    base.setFamilies(["Segoe UI", "Tahoma"])
    base.setPixelSize(17)
    QGuiApplication.setFont(base)
    icon_id = QFontDatabase.addApplicationFont(
        os.path.join("vendor", "fluentpyside", "FluentControls",
                     "FluentSystemIcons-Resizable.ttf"))
    icon_family = (QFontDatabase.applicationFontFamilies(icon_id) or ["X"])[0]

    from app.bridge.root import App

    engine = QQmlApplicationEngine()
    engine.addImportPath(os.path.join("vendor", "fluentpyside"))
    engine.addImportPath("qml")
    bridge = App()
    ctx = engine.rootContext()
    ctx.setContextProperty("app", bridge)
    ctx.setContextProperty("iconFontFamilyResizable", icon_family)
    ctx.setContextProperty("iconFontFamily", icon_family)
    engine.load(os.path.join("qml", "Main.qml"))
    win = engine.rootObjects()[0]
    win.show()
    QTest.qWait(600)

    bridge.i18n.setLanguage("ar")
    QTest.qWait(600)

    from mizan_pos1.data import db as ldb
    admin = next(e for e in ldb.fetch_employees() if e["role"] == "admin")
    win.setProperty("currentUser", admin)
    QTest.qWait(900)
    bridge.pos.clear()
    QTest.qWait(300)
    win.resize(1920, 1080)
    QTest.qWait(500)

    page = next(o for o in walk_all(win) if "PosPage" in o.metaObject().className())
    ref = win.contentItem()

    def find_named(name):
        for o in walk_all(page):
            if o.objectName() == name:
                return o
        return None

    def wg(item):
        p = item.mapToItem(ref, QPointF(0.0, 0.0))
        return (round(p.x()), round(p.y()), round(item.width()), round(item.height()))

    fails = 0

    def ok(name, detail=""):
        print(f"    ok   {name}" + (f" — {detail}" if detail else ""))

    def bad(name, detail=""):
        nonlocal fails
        fails += 1
        print(f"    FAIL {name} — {detail}")

    grid = find_named("tileGrid")
    pad = find_named("posNumpad")
    bar = find_named("payBar")
    strip = find_named("categoryStrip")
    toolbar = find_named("actionToolbar")

    gs = wg(grid); ps = wg(pad); bs = wg(bar)
    ss = wg(strip); ts = wg(toolbar)

    # panel on the LEFT in RTL: keypad's x small
    if ps[0] < 500:
        ok("RTL: panel on the left", f"keypad x={ps[0]}")
    else:
        bad("RTL: panel on the left", f"keypad x={ps[0]}")
    # bar still full width at the bottom
    if bs[2] > 1600 and bs[1] + bs[3] >= 1040:
        ok("RTL: payment bar full width at the foot",
           f"bar=({bs[0]},{bs[1]},{bs[2]},{bs[3]})")
    else:
        bad("RTL: payment bar full width at the foot",
            f"bar=({bs[0]},{bs[1]},{bs[2]},{bs[3]})")
    # toolbar still spans the foot of the workspace, above the pay bar
    if gs[1] + gs[3] <= ts[1] + 1 and ts[1] + ts[3] <= bs[1] + 1:
        ok("RTL: toolbar under the grid, above the bar")
    else:
        bad("RTL: toolbar under the grid, above the bar",
            f"grid_b={gs[1]+gs[3]} toolbar=({ts[1]}..{ts[1]+ts[3]}) bar_t={bs[1]}")

    img = win.grabWindow()
    path = os.path.join(HERE, "shots", "layout", "final_pos_1920x1080_ar.png")
    img.save(path)
    print("saved", path)

    bridge.i18n.setLanguage("en")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
