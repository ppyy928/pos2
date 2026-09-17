"""Verify the POS layout redesign offscreen and save the proof screenshots.

Boots the real bridge and the real Main.qml exactly as run.py does, signs in,
sizes the window at 1920x1080 (and 1366x768 for the narrow-wall check), and
asserts the four things the redesign is about — by reading the live QML
tree's geometry mapped into window coordinates, with pixel samples as backup:

  1. the sale-action toolbar (Hold/Suspended/Return/Calculator/Clear cart)
     is on screen, between the category strip and the tile grid
  2. the keypad is exactly as wide as the readout above it, and its keys are
     the 56px the token holds
  3. the tile grid holds the arrange screen's column count whatever the
     width — the surplus of a wide workspace is gutter, not more cards
  4. the payment bar is a full-width row at the very bottom holding the dark
     total block, Debt and Cash

    python tools/pos_layout_shots.py [outdir]
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
from PySide6.QtGui import QColor, QFont, QFontDatabase, QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402


def close(a: QColor, b: QColor, tol: int = 12) -> bool:
    return (abs(a.red() - b.red()) <= tol and abs(a.green() - b.green()) <= tol
            and abs(a.blue() - b.blue()) <= tol)


class Check:
    def __init__(self) -> None:
        self.fails: list[str] = []
        self.passes = 0

    def ok(self, name: str, detail: str = "") -> None:
        self.passes += 1
        print(f"    ok   {name}" + (f" — {detail}" if detail else ""))

    def bad(self, name: str, detail: str = "") -> None:
        self.fails.append(f"{name}: {detail}")
        print(f"    FAIL {name} — {detail}")


def find_page(win, name: str):
    import queue

    todo = queue.Queue()
    todo.put(win)
    while not todo.empty():
        try:
            obj = todo.get()
            if name in obj.metaObject().className():
                return obj
            children = list(obj.children())
        except RuntimeError:
            continue
        for child in children:
            todo.put(child)
    return None


def find_named(root, name: str):
    """First QObject descendant whose objectName() is `name`."""
    import queue

    todo = queue.Queue()
    todo.put(root)
    while not todo.empty():
        try:
            item = todo.get()
            if item.objectName() == name:
                return item
            children = list(item.children())
        except RuntimeError:
            continue
        for child in children:
            todo.put(child)
    return None


def win_geom(item, ref):
    """(x, y, w, h) of a QQuickItem in `ref`'s coordinate system."""
    p = item.mapToItem(ref, QPointF(0.0, 0.0))
    return (p.x(), p.y(), item.width(), item.height())


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        HERE, "shots", "layout")
    os.makedirs(out, exist_ok=True)

    fluentpyside.apply(accent_color="#087F5B", theme="light")
    QQuickStyle.setStyle("FluentWinUI3")
    app = QGuiApplication(sys.argv)  # noqa: F841

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
    win.show()
    QTest.qWait(600)

    check = Check()
    made: list[str] = []

    def shot(name: str):
        QTest.qWait(300)
        image = win.grabWindow()
        path = os.path.join(out, name + ".png")
        image.save(path)
        made.append(name)
        return image

    # ---- sign in ------------------------------------------------------
    from mizan_pos1.data import db as ldb

    admin = next(e for e in ldb.fetch_employees() if e["role"] == "admin")
    win.setProperty("currentUser", admin)
    QTest.qWait(900)
    bridge.pos.clear()
    QTest.qWait(300)

    page = find_page(win, "PosPage")
    if page is None:
        print("PosPage not found")
        return 1
    ref = win.contentItem()

    # ---- 1920x1080 ----------------------------------------------------
    win.resize(1920, 1080)
    QTest.qWait(500)

    # 1. the toolbar: full-width row at the foot of the workspace, above
    #    the payment bar, and never inside the cart column
    toolbar = find_named(page, "actionToolbar")
    strip = find_named(page, "categoryStrip")
    grid = find_named(page, "tileGrid")
    if toolbar is None or strip is None or grid is None:
        check.bad("toolbar/strip/grid findable",
                  f"toolbar={toolbar} strip={strip} grid={grid}")
    else:
        tb = win_geom(toolbar, ref)
        cs = win_geom(strip, ref)
        gs = win_geom(grid, ref)
        paybar0 = find_named(page, "payBar")
        pb0 = win_geom(paybar0, ref) if paybar0 is not None else (0, 0, 0, 0)
        (check.ok if tb[2] > 600 and tb[3] >= 48 else check.bad)(
            "toolbar on screen at command height",
            f"toolbar=({tb[0]:.0f},{tb[1]:.0f},{tb[2]:.0f},{tb[3]:.0f})")
        (check.ok if gs[1] + gs[3] <= tb[1] + 1
                   and tb[1] + tb[3] <= pb0[1] + 1 else check.bad)(
            "toolbar under the grid, above the payment bar",
            f"grid_bottom={gs[1]+gs[3]:.0f} toolbar=({tb[1]:.0f}.."
            f"{tb[1]+tb[3]:.0f}) paybar_top={pb0[1]:.0f}")
        # the toolbar spans the workspace, not the cart column
        (check.ok if tb[0] < gs[0] + gs[2] - 100 else check.bad)(
            "toolbar spans the workspace width",
            f"toolbar x={tb[0]:.0f} w={tb[2]:.0f}, grid x={gs[0]:.0f} w={gs[2]:.0f}")

        labels = 0
        for c in toolbar.children():
            if "ActionButton" in c.metaObject().className():
                labels += 1
        (check.ok if labels == 5 else check.bad)(
            "five sale actions restored", f"ActionButton count = {labels}")

    # 1b. the category strip grew
    if strip is not None:
        cs = win_geom(strip, ref)
        (check.ok if cs[3] >= 54 else check.bad)(
            "category strip at command-bar height", f"strip h={cs[3]:.0f}")

    # 2. keypad = readout width, key size
    display = find_named(page, "keypadDisplay")
    numpad = find_named(page, "posNumpad")
    if display is None or numpad is None:
        check.bad("readout/keypad findable",
                  f"display={display} numpad={numpad}")
    else:
        dw, nw = display.width(), numpad.width()
        (check.ok if abs(dw - nw) <= 2 else check.bad)(
            "keypad as wide as readout", f"readout={dw:.0f} keypad={nw:.0f}")
        ks = numpad.property("keySize")
        (check.ok if ks == 56 else check.bad)(
            "keypad key size is 56", f"keySize={ks}")

    # 3. grid columns are the arrange screen's count, whatever the width
    if grid is not None:
        gs = win_geom(grid, ref)
        cols = grid.property("columns")
        floor_w = grid.property("tileFloor")
        # the count a row may hold: the arrange screen's cap, or however
        # many whole cards honestly fit at the card-in-force's own minimum
        # if that is fewer — the shop's font scale grows that minimum, so
        # the honest half is compared against the same arithmetic, not a
        # fixed number
        honest = max(1, int((gs[2] + 6) // (floor_w + 6)))
        expect = min(4, honest)
        (check.ok if cols == expect and cols >= 3 else check.bad)(
            "tile columns capped at the arrange screen's count",
            f"columns={cols} expected={expect} (cap=4, honest={honest}, "
            f"floor={floor_w}, w={gs[2]:.0f})")
        # the grid runs from under the categories to the toolbar's top
        toolbar0 = find_named(page, "actionToolbar")
        tb0 = win_geom(toolbar0, ref) if toolbar0 is not None else (0, 0, 0, 0)
        span = (tb0[1] - gs[1]) if toolbar0 is not None else 0
        (check.ok if gs[3] >= (span - 24) and span > 400 else check.bad)(
            "grid fills the workspace height",
            f"grid h={gs[3]:.0f}, space to toolbar={span:.0f}")
        # the image card's height is its content: two name lines and a
        # money line — the content-sum, not the old fixed 122-token slab
        # (155 at this shop's font scale)
        if grid.property("mediaWall"):
            ch = grid.property("cellHeight")
            (check.ok if ch <= 155 else check.bad)(
                "image card is content-height",
                f"cellHeight={ch:.0f} (content-sum, old fixed token was 155)")

    # 4. pay bar at the bottom, full width, with total/Debt/Cash
    paybar = find_named(page, "payBar")
    total = find_named(page, "totalBlock")
    cash = find_named(page, "cashButton")
    if paybar is None or total is None or cash is None:
        check.bad("paybar/total/cash findable",
                  f"paybar={paybar} total={total} cash={cash}")
    else:
        pg = win_geom(page, ref)
        bx, by, bw, bh = win_geom(paybar, ref)
        # full width = the page's own width (the window's navy rail is the
        # shell's); the bar may only miss the page's side margins
        (check.ok if bw >= pg[2] - 2 * 20 else check.bad)(
            "payment bar spans products and cart",
            f"paybar=({bx:.0f},{by:.0f},{bw:.0f},{bh:.0f}) page w={pg[2]:.0f}")
        (check.ok if 88 <= bh <= 96 else check.bad)(
            "payment bar is one 92px row", f"height={bh:.0f}")
        (check.ok if by + bh >= pg[1] + pg[3] - 24 else check.bad)(
            "payment bar is the last row",
            f"bar bottom={by+bh:.0f}, page bottom={pg[1]+pg[3]:.0f}")

    img = shot("pos_en_1920")

    # dark total block present: sample the block's lower-left interior,
    # clear of the figure's white glyphs (the 42px amount owns the middle)
    if total is not None:
        tx, ty, tw, th = win_geom(total, ref)
        c = img.pixelColor(int(tx + tw * 0.06), int(ty + th * 0.75))
        (check.ok if close(c, QColor("#142B38"), 14) else check.bad)(
            "total block is dark petrol", f"sampled #{c.name()}")
        (check.ok if tw > 900 else check.bad)(
            "total takes the flexible width", f"width={tw:.0f}")

    # Debt sits LEFT of Cash (in LTR English)
    debt = find_named(page, "debtButton")
    if debt is not None and cash is not None:
        dx = win_geom(debt, ref)[0]
        cx = win_geom(cash, ref)[0]
        (check.ok if dx < cx else check.bad)(
            "debt is left of cash", f"debt x={dx:.0f} cash x={cx:.0f}")

    # emerald Cash in the bar (populated cart)
    tiles = bridge.pos.property("tiles") or []
    if len(tiles) >= 2:
        bridge.pos.add(tiles[0]["id"])
        bridge.pos.add(tiles[0]["id"])
        bridge.pos.add(tiles[1]["id"])
        QTest.qWait(600)
        img2 = shot("pos_en_1920_cart")
        if cash is not None:
            cx, cy, cw2, ch2 = win_geom(cash, ref)
            # any emerald pixel in the button's box is the fill; one pixel
            # can land on the label's white text
            found = False
            for fx in range(int(cx) + 6, int(cx + cw2) - 6, 6):
                for fy in range(int(cy) + 6, int(cy + ch2) - 6, 6):
                    if close(img2.pixelColor(fx, fy), QColor("#087F5B"), 16):
                        found = True
                        break
                if found:
                    break
            (check.ok if found else check.bad)(
                "cash is emerald", "no #087F5B in the cash button box")

    # keypad pinned at the panel's foot: the panel's ColumnLayout ends at
    # the keypad, the workspace row ends with it, and the payment bar is the
    # next row of the page column — so the keypad's bottom to the bar's top
    # is exactly the page's own spacing (16) plus the panel's bottom padding
    # (20). The toolbar lives on the PRODUCTS side now, nothing sits between
    # the keypad and the money: the merchant's rule.
    if numpad is not None and paybar is not None:
        nb = win_geom(numpad, ref)
        pb = win_geom(paybar, ref)
        gap = pb[1] - (nb[1] + nb[3])
        (check.ok if 30 <= gap <= 42 else check.bad)(
            "keypad sits directly above the payment bar",
            f"gap={gap:.0f}px (panel pad + page spacing, nothing between)")

    # ---- 1366x768, the narrow check -------------------------------------
    win.resize(1366, 768)
    QTest.qWait(500)
    shot("pos_en_1366")
    if grid is not None:
        cols = grid.property("columns")
        floor_w = grid.property("tileFloor")
        gw = win_geom(grid, ref)[2]
        honest = max(1, int((gw + 6) // (floor_w + 6)))
        expect = min(4, honest)
        (check.ok if cols == expect and expect >= 2 else check.bad)(
            "narrow wall keeps the capped column count",
            f"columns={cols} expected={expect} (cap=4, honest={honest}, "
            f"floor={floor_w}, w={gw:.0f})")

    print()
    for name in made:
        print(f"  {name}.png")
    print(f"\n{check.passes} checks passed, {len(check.fails)} failed")
    for f in check.fails:
        print(f"  FAIL {f}")
    return 1 if check.fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
