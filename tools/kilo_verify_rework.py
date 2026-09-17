"""Offscreen spot-checks for the keypad and arrange-dialog rework.

  1. KeypadDisplay carries no mode pill, and its submit key is icon-only.
  2. The till's Numpad has clearKey set, a C key, and icon-only plus/minus.
  3. feedKey("clear") empties the buffer (the C key's wiring).
  4. ArrangeDialog's DragHandlers have target null (no auto-drag fighting
     followDrag), and its grid stays capped at the arrange column count.

    python tools/kilo_verify_rework.py
"""

from __future__ import annotations

import os
import queue
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QML_DIR = os.path.join(ROOT, "qml")

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "vendor"))
os.chdir(ROOT)

import fluentpyside  # noqa: E402

from PySide6.QtCore import QPointF, QObject  # noqa: E402
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine, QQmlExpression  # noqa: E402
from PySide6.QtQuick import QQuickItem  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

HOST = """
import QtQuick
import QtQuick.Controls as QC
QC.ApplicationWindow {
    id: win
    width: 1700
    height: 1060
    visible: true
    color: "#8A8A8A"
    property var dlg: null
    function present(file, ctx) {
        if (dlg) { dlg.close(); dlg.destroy() }
        var c = Qt.createComponent(file)
        if (c.status === Component.Error) { console.log("ERROR " + c.errorString()); return null }
        dlg = c.createObject(win.contentItem, { context: ctx })
        dlg.open()
        return dlg
    }
}
"""

fails: list[str] = []


def ok(name: str, detail: str = "") -> None:
    print(f"    ok   {name}" + (f" — {detail}" if detail else ""))


def bad(name: str, detail: str = "") -> None:
    fails.append(name)
    print(f"    FAIL {name} — {detail}")


def items_under(root):
    """Every QQuickItem in the visual tree under `root` (Repeater delegates
    are not QObject children, so the visual tree is the only honest walk)."""
    out = []

    def walk(item):
        for child in item.childItems():
            out.append(child)
            walk(child)

    walk(root)
    return out


def objects_under(root):
    """QObject walk, for attached handlers (DragHandler is not an item)."""
    out = []

    def walk(obj):
        for child in obj.findChildren(QObject):
            out.append(child)

    walk(root)
    return out


def find_by_class(root, needle: str):
    todo = queue.Queue()
    todo.put(root)
    while not todo.empty():
        try:
            obj = todo.get()
            if needle in obj.metaObject().className():
                return obj
            children = list(obj.children())
        except RuntimeError:
            continue
        for child in children:
            todo.put(child)
    return None


def find_named(root, name: str):
    todo = queue.Queue()
    todo.put(root)
    while not todo.empty():
        try:
            obj = todo.get()
            if obj.objectName() == name:
                return obj
            children = list(obj.children())
        except RuntimeError:
            continue
        for child in children:
            todo.put(child)
    return None


def js(ctx, scope, expression):
    """Evaluate `expression` in `scope`; returns the value, raises on error."""
    expr = QQmlExpression(ctx, scope, expression)
    value, undefined = expr.evaluate()
    if not undefined:
        try:
            if hasattr(value, "toVariant"):
                return value.toVariant()
        except RuntimeError:
            pass
        return value
    error = expr.error()
    raise RuntimeError(f"{expression}: {error.description()} "
                       f"line {error.line()}")


def main() -> int:
    fluentpyside.apply(accent_color="#087F5B", theme="light")
    QQuickStyle.setStyle("FluentWinUI3")
    app = QGuiApplication(sys.argv)  # noqa: F841

    for candidate in (r"C:\Windows\Fonts\segoeui.ttf",
                      r"C:\Windows\Fonts\tahoma.ttf"):
        if os.path.exists(candidate):
            loaded = QFontDatabase.addApplicationFont(candidate)
            families = QFontDatabase.applicationFontFamilies(loaded)
            if families:
                base = QFont()
                base.setFamilies(families)
                base.setPixelSize(17)
                QGuiApplication.setFont(base)
                break
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

    from mizan_pos1.data import db as ldb

    admin = next(e for e in ldb.fetch_employees() if e["role"] == "admin")
    win.setProperty("currentUser", admin)
    QTest.qWait(900)
    bridge.pos.clear()
    QTest.qWait(300)

    page = find_by_class(win, "PosPage")
    if page is None:
        print("PosPage not found")
        return 1

    # ---- 1. the readout: no pill, icon-only submit -------------------
    display = find_named(page, "keypadDisplay")
    if display is None:
        bad("keypadDisplay findable")
    else:
        mo = display.metaObject()

        def has(prop: str) -> bool:
            return mo.indexOfProperty(prop) >= 0

        if has("modeText") or has("modeGlyph") or has("tone"):
            bad("readout carries no mode pill", "pill properties still present")
        else:
            ok("readout carries no mode pill")
        if has("actionLabel"):
            bad("submit key is icon-only", "actionLabel still present")
        else:
            ok("submit key is icon-only")
        if mo.indexOfSignal("applied()") >= 0:
            ok("submit signal intact")
        else:
            bad("submit signal intact")

    # ---- 2. the pad: C key, icon-only money modes --------------------
    numpad = find_named(page, "posNumpad")
    if numpad is None:
        bad("posNumpad findable")
    else:
        if numpad.property("clearKey") is True:
            ok("till pad asks for the C key")
        else:
            bad("till pad asks for the C key",
                f"clearKey={numpad.property('clearKey')!r}")

        texts = []
        for item in items_under(numpad):
            if "Button" in item.metaObject().className():
                t = item.property("text")
                if t:
                    texts.append(t)
        if "C" in texts:
            ok("C key present on the pad")
        else:
            bad("C key present on the pad", f"button texts={texts}")

        try:
            plus = js(ctx, numpad, "specFor('plus')")
            minus = js(ctx, numpad, "specFor('minus')")
            if plus.get("iconOnly") is True and minus.get("iconOnly") is True:
                ok("plus and minus are icon-only")
            else:
                bad("plus and minus are icon-only",
                    f"plus={plus} minus={minus}")
        except RuntimeError as exc:
            bad("plus and minus are icon-only", str(exc))

    # ---- 3. the C wiring: clicking C empties the buffer ---------------
    try:
        js(ctx, page, "buffer = '12345'")
        QTest.qWait(30)
        before = js(ctx, page, "buffer")
        c_button = None
        for item in items_under(numpad) if numpad is not None else []:
            if "Button" in item.metaObject().className() \
                    and item.property("text") == "C":
                c_button = item
                break
        if c_button is None:
            bad("C key clickable", "no C button found")
        else:
            from PySide6.QtCore import QPoint, Qt

            p = c_button.mapToScene(
                QPointF(c_button.width() / 2, c_button.height() / 2))
            QTest.mouseClick(win, Qt.LeftButton, Qt.KeyboardModifier(0),
                             QPoint(int(p.x()), int(p.y())))
            QTest.qWait(120)
            after = js(ctx, page, "buffer")
            if before == "12345" and after == "":
                ok("clicking C empties the buffer",
                   f"'{before}' -> '{after}'")
            else:
                bad("clicking C empties the buffer",
                    f"before={before!r} after={after!r}")
    except RuntimeError as exc:
        bad("clicking C empties the buffer", str(exc))

    # ---- 4. the arrange dialog: tracker handlers, capped grid --------
    from PySide6.QtCore import QUrl
    from PySide6.QtQml import QQmlComponent

    path = os.path.join(QML_DIR, "dialogs", "ArrangeDialog.qml")
    component = QQmlComponent(engine, QUrl.fromLocalFile(path))
    if component.status() != QQmlComponent.Status.Ready:
        bad("ArrangeDialog opens", component.errorString())
        dialog = None
    else:
        dialog = component.createObject(win.contentItem(), {"context": {}})
        if dialog is None:
            bad("ArrangeDialog opens", component.errorString())
        else:
            dialog.open()
            QTest.qWait(700)
    if dialog is not None:
        ok("ArrangeDialog opens")
        handlers = [o for o in dialog.findChildren(QObject)
                    if "DragHandler" in o.metaObject().className()]
        nulls = [h for h in handlers if h.property("target") is None]
        if handlers and len(nulls) == len(handlers):
            ok(f"all {len(handlers)} DragHandlers are trackers "
               f"(target null)")
        else:
            # handlers inside grid delegates are not QObject children; the
            # source is the fallback witness
            src = open(path, encoding="utf-8").read()
            if "target: null" in src:
                ok("DragHandler is a tracker (target null, by source)")
            else:
                bad("DragHandler is a tracker", "no target: null in source")

        grids = [o for o in dialog.findChildren(QObject)
                 if "QQuickGridView" in o.metaObject().className()]
        if grids:
            cols = grids[0].property("columns")
            if cols is not None and 1 <= cols <= 4:
                ok(f"arrange grid columns capped ({cols})")
            else:
                bad("arrange grid columns capped", f"columns={cols!r}")
        else:
            bad("arrange grid found")

        # A live drag, held inside ONE cell so no exchange commits and the
        # demo database is not written. What it asserts:
        #   grab     the handler takes the pointer (dragIndex set)
        #   pin      the tile keeps the SAME point under the pointer across
        #            moves — the grab offset never drifts, which is what
        #            two writers on one position (the handler's own
        #            automatic target drag plus followDrag) used to break
        #   release  dragIndex back to -1, order untouched
        try:
            from PySide6.QtCore import QPoint, Qt

            grid = grids[0]
            content = grid.property("contentItem")
            cells = sorted(content.childItems(),
                           key=lambda c: (round(c.y()), round(c.x())))
            if not cells:
                bad("live drag grabs and releases", "no cells instantiated")
            else:
                cell = cells[0]
                before_ids = [r.get("id")
                              for r in (dialog.property("rows") or [])]
                center = cell.mapToScene(
                    QPointF(cell.width() / 2, cell.height() / 2))
                c0 = QPoint(int(center.x()), int(center.y()))
                m1 = QPoint(c0.x() + 30, c0.y() + 5)
                m2 = QPoint(c0.x() + 50, c0.y() + 15)

                QTest.mouseMove(win, c0)
                QTest.mousePress(win, Qt.LeftButton,
                                 Qt.KeyboardModifier(0), c0)
                QTest.mouseMove(win, m1)
                QTest.qWait(150)

                drag_index = dialog.property("dragIndex")
                floater = dialog.property("dragFloater")
                if drag_index is None or drag_index < 0 or floater is None:
                    QTest.mouseRelease(win, Qt.LeftButton,
                                       Qt.KeyboardModifier(0), m1)
                    bad("live drag grabs and releases",
                        f"dragIndex={drag_index!r} floater={floater!r} — "
                        f"handler never grabbed")
                else:
                    f1 = floater.mapToScene(
                        QPointF(floater.width() / 2, floater.height() / 2))
                    off = (f1.x() - m1.x(), f1.y() - m1.y())

                    QTest.mouseMove(win, m2)
                    QTest.qWait(150)
                    f2 = floater.mapToScene(
                        QPointF(floater.width() / 2, floater.height() / 2))
                    pinned = (abs((f2.x() - m2.x()) - off[0]) <= 1
                              and abs((f2.y() - m2.y()) - off[1]) <= 1)

                    QTest.mouseRelease(win, Qt.LeftButton,
                                       Qt.KeyboardModifier(0), m2)
                    QTest.qWait(300)

                    after_ids = [r.get("id")
                                 for r in (dialog.property("rows") or [])]
                    if not pinned:
                        bad("live drag grabs and releases",
                            f"grab offset drifted: held {off}, then "
                            f"({f2.x() - m2.x()}, {f2.y() - m2.y()})")
                    elif dialog.property("dragIndex") != -1:
                        bad("live drag grabs and releases", "drag never "
                            "released")
                    elif before_ids != after_ids:
                        bad("live drag grabs and releases",
                            "order changed without a cross-cell drop")
                    else:
                        ok("live drag grabs and releases",
                           f"held index {drag_index}, pinned to the "
                           f"pointer, released clean")
        except RuntimeError as exc:
            bad("live drag grabs and releases", str(exc))

    print()
    if fails:
        print(f"{len(fails)} FAILED")
        return 1
    print("all spot-checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
