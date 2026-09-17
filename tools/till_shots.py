"""Render the Login and POS screens offscreen, assert their surfaces, save PNGs.

Not a test suite: a way to LOOK at the two screens the redesign owns, plus a
handful of pixel assertions for the things a compile check cannot see — the
navy rail, the shelf-grey workspace, the white panel, the dark total block,
the emerald Cash button, the emerald sign-in. A colour that drifts back to
pale is exactly the regression this screen set out to fix, so the colours
are checked, not assumed.

    python tools/till_shots.py [outdir]

Boots the real bridge and the real Main.qml, exactly as run.py boots them,
then grabs the window at the two sizes the brief names (1920x1080, 1366x768)
in each language, with a populated cart as well as an empty one.
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

from PySide6.QtGui import QColor, QFont, QFontDatabase, QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402


def close(a: QColor, b: QColor, tol: int = 14) -> bool:
    return (abs(a.red() - b.red()) <= tol and abs(a.green() - b.green()) <= tol
            and abs(a.blue() - b.blue()) <= tol)


class Check:
    def __init__(self) -> None:
        self.fails: list[str] = []
        self.passes = 0

    def ok(self, name: str, detail: str = "") -> None:
        self.passes += 1
        print(f"    ok   {name}")

    def bad(self, name: str, detail: str = "") -> None:
        self.fails.append(f"{name}: {detail}")
        print(f"    FAIL {name} — {detail}")


def dominant(image, x0, y0, x1, y1) -> QColor:
    """The most common colour in a box, ignoring near-white/near-black dust."""
    counts: dict[tuple[int, int, int], int] = {}
    for y in range(y0, y1, 4):
        for x in range(x0, x1, 4):
            c = image.pixelColor(x, y)
            counts[(c.red(), c.green(), c.blue())] = counts.get(
                (c.red(), c.green(), c.blue()), 0) + 1
    best = max(counts, key=counts.get)  # type: ignore[arg-type]
    return QColor(*best)


def contains(image, want: QColor, x0, y0, x1, y1, tol: int = 10) -> bool:
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            c = image.pixelColor(x, y)
            if close(c, want, tol):
                return True
    return False


def find_page(win, name: str):
    """The QML page object by type name, e.g. PosPage_QMLTYPE.

    Walks children by hand: PageHost destroys replaced pages, and a stale
    wrapper in the tree raises RuntimeError the moment it is touched.
    """
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


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "shots", "till")
    os.makedirs(out, exist_ok=True)

    # run.py's own startup order: accent, style, font, icon font.
    fluentpyside.apply(accent_color="#087F5B", theme="light")
    QQuickStyle.setStyle("FluentWinUI3")
    app = QGuiApplication(sys.argv)  # noqa: F841

    ui_family = "Tahoma"
    for candidate in (r"C:\Windows\Fonts\segoeui.ttf",
                      r"C:\Windows\Fonts\tahoma.ttf",
                      r"C:\Windows\Fonts\arial.ttf"):
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
    # run.py shows the window through setup_windows; nothing here calls that,
    # so it has to be shown by hand or grabWindow returns the empty backdrop.
    win.show()
    QTest.qWait(600)

    # The languages the brief names, in the order the selector lists them.
    languages = ["en", "fr", "ar"]
    check = Check()
    made: list[str] = []

    def shot(name: str) -> None:
        QTest.qWait(250)
        image = win.grabWindow()
        path = os.path.join(out, name + ".png")
        image.save(path)
        made.append(name)
        return image  # type: ignore[return-value]

    def sign_in() -> None:
        from mizan_pos1.data import db as ldb

        admin = next(e for e in ldb.fetch_employees() if e["role"] == "admin")
        win.setProperty("currentUser", admin)
        QTest.qWait(700)

    def sign_out() -> None:
        # The real path: session.end() is what the idle lock uses, and Main.qml
        # clears currentUser from its signal. (Setting the var property to None
        # from Python leaves an invalid QVariant in it, which QML's !== null
        # treats as still signed in — the first run's French "login" shots were
        # pictures of the POS page behind for exactly that reason.)
        bridge.session.end()
        QTest.qWait(500)

    for code in languages:
        bridge.i18n.setLanguage(code)
        QTest.qWait(300)
        rtl = bridge.i18n.property("isRtl")

        # Region helpers that follow the layout direction: in Arabic the rail
        # and the panel swap sides, and the assertions must swap with them.
        # `rtl` is bound as a default so each iteration's helpers carry their
        # own copy of it.
        def rail_box(w, h, rtl=rtl):
            return (8, 120, 200, h - 120) if not rtl else (w - 200, 120, w - 8, h - 120)

        def shelf_point(w, h, rtl=rtl):
            x = (224 + (w - 16 - 420) + 8) // 2
            return (x, 120) if not rtl else (w - x, 120)

        def panel_point(w, h, rtl=rtl):
            # Inside the panel's own padding strip: pure panel white in either
            # arrangement, clear of every control. w-40 because the window's
            # own content inset puts the panel's edge closer than the page
            # margin suggests.
            return (w - 40, 300) if not rtl else (40, 300)

        def foot_box(w, h, rtl=rtl):
            # The payment bar is full-width at the foot of the page now, and
            # the dark total block is its LEADING side (the buttons took the
            # trailing side) — see PosPage's "THE PANEL AND THE PAYMENT BAR".
            # The box is the bar's band only: taller would reach into the
            # keypad above it, whose Apply key is emerald whenever a buffer
            # is sitting in it.
            return (20, h - 110, w // 2, h - 10) if not rtl \
                else (w // 2, h - 110, w - 20, h - 10)

        # ---- Login, both sizes -------------------------------------------
        for w, h in ((1920, 1080), (1366, 768)):
            win.resize(w, h)
            QTest.qWait(300)
            img = shot(f"login_{code}_{w}")
            if w == 1920:
                # The brand field: whichever side the language puts it on.
                brand = ((0, 200, w // 2 - 40, h - 100) if not rtl
                         else (w // 2 + 40, 200, w - 20, h - 100))
                form = ((w // 2 + 60, 200, w - 60, h - 100) if not rtl
                        else (20, 200, w // 2 - 60, h - 100))
                left = dominant(img, *brand)
                right = dominant(img, *form)
                navyish = (close(left, QColor("#101C2E"), 26)
                           or close(left, QColor("#12303B"), 26)
                           or close(left, QColor("#143B45"), 30))
                (check.ok if navyish else check.bad)(
                    f"login {code} brand field is navy/petrol",
                    f"dominant = #{left.name()}")
                (check.ok if close(right, QColor("#FFFFFF"), 10) else check.bad)(
                    f"login {code} form zone is white",
                    f"dominant = #{right.name()}")
                if not contains(img, QColor("#087F5B"), 20, 100, w - 20, h):
                    check.bad(f"login {code} emerald present", "no #087F5B anywhere")
                else:
                    check.ok(f"login {code} emerald present")

        # ---- Login error state (EN only; the sentence is what matters) ----
        if code == "en":
            bridge.auth.login("admin", "definitely-not-it")
            QTest.qWait(1200)
            shot("login_failed_en")
            check.ok("login error state captured")

        # ---- POS ----------------------------------------------------------
        sign_in()
        # A fresh session does not clear the till (a held sale can outlive a
        # lock), so the empty shots need an explicit clear — the previous
        # language's walkthrough cart would otherwise still be in it. The
        # keypad's buffer is page state and survives with the page; it goes
        # too, or its Apply key stays emerald through every later shot.
        bridge.pos.clear()
        page = find_page(win, "PosPage")
        if page is not None:
            page.setProperty("buffer", "")
            page.setProperty("keypadMode", "qty")
        QTest.qWait(300)
        for w, h in ((1920, 1080), (1366, 768)):
            win.resize(w, h)
            QTest.qWait(400)

            img = shot(f"pos_{code}_{w}_empty")

            # The rail: dark navy across its band.
            rail = dominant(img, *rail_box(w, h))
            (check.ok if close(rail, QColor("#142033"), 12) else check.bad)(
                f"pos {code} {w} rail is navy", f"dominant = #{rail.name()}")

            # The product workspace: cool light grey.
            sx, sy = shelf_point(w, h)
            shelf = img.pixelColor(sx, sy)
            (check.ok if close(shelf, QColor("#F2F4F7"), 8) else check.bad)(
                f"pos {code} {w} workspace is shelf grey",
                f"sampled #{shelf.name()}")

            # The transaction panel: white.
            px, py = panel_point(w, h)
            panel = img.pixelColor(px, py)
            (check.ok if close(panel, QColor("#FFFFFF"), 8) else check.bad)(
                f"pos {code} {w} panel is white", f"sampled #{panel.name()}")

            # The total block: dark petrol in the panel's foot, always.
            if contains(img, QColor("#142B38"), *foot_box(w, h)):
                check.ok(f"pos {code} {w} dark total block present")
            else:
                check.bad(f"pos {code} {w} dark total block present",
                          "no #142B38 in the panel foot")

            # An EMPTY cart means Cash is disabled — visibly so, which is the
            # point; the emerald is asserted on the populated shot below.
            if contains(img, QColor("#087F5B"), *foot_box(w, h)):
                check.bad(f"pos {code} {w} empty cart dims Cash",
                          "emerald where the disabled grey belongs")
            else:
                check.ok(f"pos {code} {w} empty cart dims Cash")

        # ---- POS with a cart, in every language ---------------------------
        win.resize(1920, 1080)
        QTest.qWait(300)
        bridge.pos.clear()
        QTest.qWait(200)
        tiles = bridge.pos.property("tiles") or []
        if len(tiles) >= 2:
            bridge.pos.add(tiles[0]["id"])
            bridge.pos.add(tiles[0]["id"])
            bridge.pos.add(tiles[1]["id"])
            QTest.qWait(500)
            lines = bridge.pos.property("lines") or []
            (check.ok if len(lines) == 2 else check.bad)(
                f"pos {code} cart holds merged lines",
                f"{len(lines)} lines, want 2")

            # Type into the keypad's buffer the way the pad does, so Apply
            # wakes up and the emerald confirmation is on screen.
            page = find_page(win, "PosPage")
            if page is not None:
                page.setProperty("buffer", "3")
                QTest.qWait(200)
            img = shot(f"pos_{code}_1920_cart")
            # Cash is the payment bar's TRAILING button — the total block
            # takes the leading half (see foot_box's own note).
            cash_box = ((w_trail := 1920) - 500, 1080 - 110, w_trail - 20, 1080 - 10) \
                if not rtl else (20, 1080 - 110, 500, 1080 - 10)
            if contains(img, QColor("#087F5B"), *cash_box):
                check.ok(f"pos {code} emerald Cash present")
            else:
                check.bad(f"pos {code} emerald Cash present",
                          "no #087F5B in the payment row")

            # The keypad region sits above the total block in the panel.
            keypad = ((1920 - 436, 1080 - 560, 1920 - 20, 1080 - 280) if not rtl
                      else (20, 1080 - 560, 436, 1080 - 280))
            if contains(img, QColor("#087F5B"), *keypad):
                check.ok(f"pos {code} keypad Apply emerald present")
            else:
                check.bad(f"pos {code} keypad Apply emerald present",
                          "no emerald in the keypad region")

            if code == "en":
                bridge.pos.addFreeAmount(-1, 250.0)
                QTest.qWait(300)
                shot("pos_en_1920_discount")
                disc = bridge.pos.property("discountText")
                (check.ok if disc not in ("", None) else check.bad)(
                    "cart discount recorded", f"discountText={disc!r}")
        else:
            check.bad("tiles loaded for the cart walkthrough", f"{len(tiles)} tiles")
        sign_out()

    print()
    for name in made:
        print(f"  {name}.png")
    print(f"\n{check.passes} checks passed, {len(check.fails)} failed")
    for f in check.fails:
        print(f"  FAIL {f}")
    return 1 if check.fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
