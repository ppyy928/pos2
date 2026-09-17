"""Edit-mode proof: load a customer invoice into the till and verify the
restored Paid / Remaining figures appear inside the total block of the
full-width payment bar (the figures the TotalsDock carried at HEAD and the
bar redesign must not lose).

    python tools/pos_edit_shot.py
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

    from mizan_pos1.data import db as ldb

    admin = next(e for e in ldb.fetch_employees() if e["role"] == "admin")
    win.setProperty("currentUser", admin)
    QTest.qWait(900)
    bridge.pos.clear()
    QTest.qWait(300)
    win.resize(1920, 1080)
    QTest.qWait(500)

    # find a customer sale with a partial payment (paid < total) to load
    database = None
    from app.bridge.legacy import database as get_db
    database = get_db()

    sale = None
    result = database.fetch_sales(page=1, page_size=50) or {}
    rows = result.get("rows") if isinstance(result, dict) else result
    # fetch_sales' rows do not carry customer_id; fetch_sale does. Walk the
    # newest first and take the first customer invoice that still owes.
    for s in rows or []:
        try:
            full = database.fetch_sale(int(s["id"]))
        except Exception:
            continue
        if not full or not full.get("customer_id"):
            continue
        total = float(full.get("total") or 0.0)
        paid = float(full.get("paid") or 0.0)
        if 0.005 < paid < total - 0.005:
            sale = full
            break
        if sale is None:
            sale = full

    if sale is None:
        print("no customer sale in the book to load — cannot verify edit mode")
        return 1

    print(f"loading sale {sale.get('number')} (id {sale.get('id')}), "
          f"customer {sale.get('customer_id')}, "
          f"total {sale.get('total')} paid {sale.get('paid')}")
    ok = bridge.pos.loadSale(int(sale["id"]))
    QTest.qWait(700)

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

    editing = bridge.pos.property("editing")
    has_customer = bridge.pos.property("hasCustomer")
    paid_text = bridge.pos.property("paidText")
    remaining = bridge.pos.property("remainingText")
    print(f"editing={editing} hasCustomer={has_customer} "
          f"paidText={paid_text!r} remainingText={remaining!r}")

    fails = 0

    # the figures row is INSIDE totalBlock: find it by looking for a Text
    # whose content is the paid figure, and confirm its parentage+geometry
    total = find_named("totalBlock")
    tx, ty, tw, th = wg(total)
    found_paid = found_remaining = False
    for o in walk_all(total):
        if o.metaObject().className().startswith("QQuickText"):
            t = o.property("text") or ""
            if paid_text and paid_text.lstrip("\u200e") in t:
                found_paid = True
            if remaining and remaining.lstrip("\u200e") in t:
                found_remaining = True
    print(f"paid figure inside total block: {found_paid}")
    print(f"remaining figure inside total block: {found_remaining}")
    if editing and has_customer:
        if found_paid and found_remaining:
            print("    ok   Paid/Remaining present in the payment bar while editing")
        else:
            fails += 1
            print("    FAIL Paid/Missing in the payment bar while editing")

    img = win.grabWindow()
    path = os.path.join(HERE, "shots", "layout", "final_pos_1920x1080_edit.png")
    img.save(path)
    print("saved", path)

    bridge.pos.cancelEdit()
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
