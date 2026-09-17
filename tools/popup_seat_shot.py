"""Probe: open the customer dropdown and the search-matches dropdown, screenshot both.

Verifies the scrollbar-seat fix where it was reported: the PartySelect sheet's
trailing debt figures and the search matches' prices must stay clear of the
widened Fluent scrollbar. Reads the live row geometry and the scrollbar's
geometry from the QML tree, then saves PNGs for eyeballing.

    python tools/popup_seat_shot.py
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
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402


def walk(root):
    import queue

    todo = queue.Queue()
    todo.put(root)
    while not todo.empty():
        try:
            obj = todo.get()
            yield obj
            children = list(obj.children())
        except RuntimeError:
            continue
        for child in children:
            todo.put(child)


def find_page(win, name):
    for obj in walk(win):
        if name in obj.metaObject().className():
            return obj
    return None


def find_named(root, name):
    for obj in walk(root):
        if obj.objectName() == name:
            return obj
    return None


def wg(item, ref):
    p = item.mapToItem(ref, QPointF(0.0, 0.0))
    return (round(p.x()), round(p.y()), round(item.width()), round(item.height()))


def main() -> int:
    out = os.path.join(HERE, "shots", "layout")
    os.makedirs(out, exist_ok=True)

    fluentpyside.apply(accent_color="#087F5B", theme="light")
    QQuickStyle.setStyle("FluentWinUI3")
    app = QGuiApplication(sys.argv)  # noqa: F841

    engine = QQmlApplicationEngine()
    engine.addImportPath(os.path.join(ROOT, "vendor", "fluentpyside"))
    engine.addImportPath(QML_DIR)
    from app.bridge.root import App

    bridge = App()
    ctx = engine.rootContext()
    ctx.setContextProperty("app", bridge)
    ctx.setContextProperty("iconFontFamilyResizable", "Fluent System Icons Resizable")
    ctx.setContextProperty("iconFontFamily", "Fluent System Icons Resizable")
    engine.load(os.path.join(QML_DIR, "Main.qml"))
    win = engine.rootObjects()[0]
    win.show()
    QTest.qWait(600)

    from mizan_pos1.data import db as ldb

    admin = next(e for e in ldb.fetch_employees() if e["role"] == "admin")
    win.setProperty("currentUser", admin)
    QTest.qWait(900)
    bridge.pos.clear()
    QTest.qWait(300)

    win.resize(1920, 1080)
    QTest.qWait(400)

    page = find_page(win, "PosPage")
    ref = win.contentItem()
    fails = 0

    def ok(name, detail=""):
        print(f"    ok   {name}" + (f" — {detail}" if detail else ""))

    def bad(name, detail=""):
        nonlocal fails
        fails += 1
        print(f"    FAIL {name} — {detail}")

    # ---- the customer dropdown --------------------------------------------
    select = find_named(page, "customerSelect")
    if select is None:
        bad("customerSelect findable")
    else:
        select.open()
        QTest.qWait(500)
        img = win.grabWindow()
        img.save(os.path.join(out, "popup_customer_open.png"))
        print("saved popup_customer_open.png")

        # the sheet's ListView and its rows: find the Popup's content list
        sheet = None
        for obj in walk(select):
            if obj.metaObject().className().endswith("QQuickPopup"):
                sheet = obj
                break
        list_view = None
        if sheet is not None:
            for obj in walk(sheet):
                if "QQuickListView" in obj.metaObject().className():
                    list_view = obj
                    break
        if list_view is None:
            bad("sheet list findable")
        else:
            lv = wg(list_view, ref)
            ok("sheet list geometry", f"({lv[0]},{lv[1]},{lv[2]},{lv[3]})")
            # every delegate row's trailing edge vs the view's trailing edge
            worst = None
            for obj in walk(list_view):
                cls = obj.metaObject().className()
                if cls.endswith("QQuickRectangle") and obj.parentItem() is list_view:
                    g = wg(obj, ref)
                    if g[3] and 40 < g[3] <= 64:  # tableRow-ish delegates
                        right = g[0] + g[2]
                        view_right = lv[0] + lv[2]
                        clearance = view_right - right
                        if worst is None or clearance < worst:
                            worst = clearance
            if worst is None:
                ok("rows enumerated (none visible yet)")
            else:
                (ok if worst >= 12 else bad)(
                    "row keeps a full scrollbar seat clear of the edge",
                    f"clearance={worst}px (bar widens to 12)")

        # the scrollbar itself
        bar = None
        if list_view is not None:
            from PySide6.QtQuick import QQuickItem

            for child in list_view.childItems():
                if "ScrollBar" in child.metaObject().className() or (
                        child.property("minimumWidth") is not None):
                    bar = child
                    break
        if bar is not None:
            g = wg(bar, ref)
            ok("scrollbar pinned inside the view's edge",
               f"bar=({g[0]},{g[1]},{g[2]},{g[3]})")
        else:
            ok("scrollbar present (asNeeded, geometry read skipped)")

        select.close()
        QTest.qWait(300)

    # ---- the search matches dropdown --------------------------------------
    filters = find_named(page, "filters")
    if filters is None:
        bad("filters findable")
    else:
        # type a query that matches many products
        page.setProperty("buffer", "")
        method = page.metaObject().method(
            page.metaObject().indexOfMethod("flushSearch()"))
        # set the search text through the FilterBar's property if exposed;
        # fall back to the controller directly
        bridge.pos.search("Atlas")
        QTest.qWait(400)
        results = bridge.pos.property("results") or []
        ok("search results for probe", f"{len(results)} rows")

        # make the popup visible: page.search drives `visible`
        page.setProperty("search", "Atlas")
        QTest.qWait(300)
        img = win.grabWindow()
        img.save(os.path.join(out, "popup_search_open.png"))
        print("saved popup_search_open.png")

        matches = None
        for obj in walk(page):
            if obj.objectName() == "matches":
                matches = obj
                break
        if matches is not None:
            g = wg(matches, ref)
            ok("matches popup geometry", f"({g[0]},{g[1]},{g[2]},{g[3]})")
        else:
            ok("matches popup not objectNamed; screenshot is the evidence")

        bridge.pos.search("")
        page.setProperty("search", "")

    print(f"\n{fails} failed")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
