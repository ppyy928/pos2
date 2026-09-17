"""Offscreen spot-checks for the product picker rework.

  1. The table has no Status column.
  2. The category dropdown exists beside the search field, offers "All
     categories" plus the catalogue's own names, and narrows the rows.
  3. The pager pages the FILTERED rows: model is a page-sized slice, the
     page follows the filter, and the range text is the pages' own bar.
  4. The arrows carry the selection across a page boundary.
  5. A page-relative click maps back to the right filtered row.

    python tools/kilo_verify_picker.py
"""

from __future__ import annotations

import json
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

from PySide6.QtCore import Q_ARG, QMetaObject, QObject, Qt, QUrl  # noqa: E402
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlExpression  # noqa: E402
from PySide6.QtQuickControls2 import QQuickStyle  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

fails: list[str] = []


def ok(name: str, detail: str = "") -> None:
    print(f"    ok   {name}" + (f" — {detail}" if detail else ""))


def bad(name: str, detail: str = "") -> None:
    fails.append(name)
    print(f"    FAIL {name} — {detail}")


def find_all_by_class(root, needle: str):
    import queue

    out = []
    todo = queue.Queue()
    todo.put(root)
    while not todo.empty():
        try:
            obj = todo.get()
            if needle in obj.metaObject().className():
                out.append(obj)
            children = list(obj.children())
        except RuntimeError:
            continue
        for child in children:
            todo.put(child)
    return out


def js(ctx, scope, expression):
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


def as_list(value):
    """QML's `var` arrays arrive as QJSValue; hand back Python rows."""
    if value is None:
        return []
    try:
        if hasattr(value, "toVariant"):
            value = value.toVariant()
    except RuntimeError:
        return []
    return list(value) if value else []


def call(ctx, obj, name, *args):
    """Call a QML function on `obj`.

    PySide6 sometimes hands back a MetaFunction object instead of a callable
    when a QML method is read off the wrapper, so the call is built as a QML
    expression and evaluated in the object's own scope. A void QML function
    returns undefined, which js() treats as a failure — so the expression is
    evaluated here directly and only a VALID QQmlError is raised.
    """
    parts = []
    for value in args:
        if isinstance(value, str):
            parts.append(json.dumps(value))
        elif isinstance(value, bool):
            parts.append("true" if value else "false")
        else:
            parts.append(repr(value))
    expr = QQmlExpression(ctx, obj, f"{name}({', '.join(parts)})")
    expr.evaluate()
    error = expr.error()
    if error.isValid():
        raise RuntimeError(f"{name}: {error.description()} "
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

    catalogue = bridge.pos.catalogue()
    if len(catalogue) < 12:
        print(f"catalogue too small for the paging checks ({len(catalogue)})")
        return 1

    path = os.path.join(QML_DIR, "Mizan", "ProductPickerPopup.qml")
    component = QQmlComponent(engine, QUrl.fromLocalFile(path))
    if component.status() != QQmlComponent.Status.Ready:
        bad("popup loads", component.errorString())
        return 1
    popup = component.createObject(win.contentItem(),
                                   {"catalogue": catalogue})
    if popup is None:
        bad("popup loads", component.errorString())
        return 1
    popup.open()
    QTest.qWait(500)

    pickers = [obj for obj in find_all_by_class(popup, "ProductPicker")
               if "Popup" not in obj.metaObject().className()]
    if not pickers:
        bad("ProductPicker inside the popup")
        return 1
    picker = pickers[0]

    # ---- 1. no Status column -----------------------------------------
    columns = as_list(picker.property("columns"))
    keys = [str(c.get("key")) for c in columns]
    if "status" in keys:
        bad("no status column", f"columns have {keys}")
    else:
        ok("no status column", f"{len(columns)} columns: {keys}")

    # ---- 2. the category dropdown -------------------------------------
    combos = [obj for obj in find_all_by_class(popup, "ComboBox")
              if obj.property("textRole") == "name"]
    if not combos:
        bad("category dropdown exists")
    else:
        ok("category dropdown exists")
    cats = as_list(picker.property("categories"))
    if len(cats) >= 2 and cats[0].get("key") == "":
        ok("options lead with All categories",
           f"{len(cats)} options")
    else:
        bad("options lead with All categories", f"{cats[:3]}")

    total_all = len(as_list(picker.property("rows")))
    if total_all == len(catalogue):
        ok("unfiltered rows are the whole catalogue",
           f"{total_all}")
    else:
        bad("unfiltered rows are the whole catalogue",
            f"{total_all} vs {len(catalogue)}")

    if len(cats) >= 2:
        name = cats[1]["key"]
        call(ctx, picker, "setCategory", name)
        QTest.qWait(80)
        filtered = as_list(picker.property("rows"))
        expected = sum(1 for r in catalogue
                       if str(r.get("category") or "") == name)
        if len(filtered) == expected and all(
                str(r.get("category") or "") == name for r in filtered):
            ok("category narrows the rows", f"{name}: {len(filtered)}")
        else:
            bad("category narrows the rows",
                f"{len(filtered)} vs {expected}")
        page_now = picker.property("currentPage")
        if page_now == 1:
            ok("category resets the page")
        else:
            bad("category resets the page", f"page={page_now}")
        call(ctx, picker, "setCategory", "")
        QTest.qWait(80)

    # ---- 3. the pager pages the filtered rows -------------------------
    picker.setProperty("pageSize", 10)
    QTest.qWait(120)
    page_rows = as_list(picker.property("pageRows"))
    if len(page_rows) == 10 and picker.property("maxPage") == \
            (len(catalogue) + 9) // 10:
        ok("the model is one page-sized slice",
           f"{len(page_rows)} of {len(catalogue)}, "
           f"{picker.property('maxPage')} pages")
    else:
        bad("the model is one page-sized slice",
            f"{len(page_rows)} rows, maxPage={picker.property('maxPage')}")

    call(ctx, picker, "select", 12)
    QTest.qWait(150)
    if picker.property("currentPage") == 2 and \
            picker.property("current") == 12:
        ok("select crosses into page 2")
    else:
        bad("select crosses into page 2",
            f"page={picker.property('currentPage')} "
            f"current={picker.property('current')}")

    grids = find_all_by_class(picker, "DataTable")
    current_row = grids[0].property("currentRow") if grids else None
    if current_row == 2:
        ok("the table's cursor follows the selection", f"row {current_row}")
    else:
        bad("the table's cursor follows the selection",
            f"currentRow={current_row!r}")

    # ---- 4. arrows walk across the boundary ---------------------------
    call(ctx, picker, "select", 9)
    QTest.qWait(80)
    call(ctx, picker, "step", 1)
    QTest.qWait(150)
    if picker.property("currentPage") == 2 and \
            picker.property("current") == 10:
        ok("an arrow carries the selection to the next page")
    else:
        bad("an arrow carries the selection to the next page",
            f"page={picker.property('currentPage')} "
            f"current={picker.property('current')}")
    call(ctx, picker, "step", -1)
    QTest.qWait(150)
    if picker.property("currentPage") == 1 and \
            picker.property("current") == 9:
        ok("an arrow carries it back")
    else:
        bad("an arrow carries it back",
            f"page={picker.property('currentPage')} "
            f"current={picker.property('current')}")

    # ---- 5. a page-relative click maps to the filtered row ------------
    got: list = []
    try:
        picker.picked.connect(lambda product: got.append(product))
    except Exception as exc:  # noqa: BLE001
        print(f"    note: could not connect picked ({exc})")
    try:
        call(ctx, picker, "take", 5)
        QTest.qWait(80)
        if got and picker.property("current") == 5:
            expected_row = (as_list(picker.property("rows")))[5]
            if got[0].get("id") == expected_row.get("id"):
                ok("take maps the page row to the filtered row",
                   got[0].get("name"))
            else:
                bad("take maps the page row to the filtered row",
                    f"{got[0].get('id')} vs {expected_row.get('id')}")
        else:
            bad("take maps the page row to the filtered row",
                f"picked={len(got)} current={picker.property('current')}")
    except RuntimeError as exc:
        bad("take maps the page row to the filtered row", str(exc))

    # ---- 6. the search still narrows and resets the page --------------
    js(ctx, picker, "query = 'zzzznope'")
    QTest.qWait(80)
    if (as_list(picker.property("rows"))) == [] and \
            picker.property("currentPage") == 1:
        ok("a query narrows the rows and resets the page")
    else:
        bad("a query narrows the rows and resets the page",
            f"rows={len(picker.property('rows') or [])} "
            f"page={picker.property('currentPage')}")
    js(ctx, picker, "query = ''")
    QTest.qWait(80)
    if len(as_list(picker.property("rows"))) == len(catalogue):
        ok("clearing the query restores the whole catalogue")
    else:
        bad("clearing the query restores the whole catalogue")

    # ---- 7. reopening starts clean ------------------------------------
    if len(cats) >= 2:
        call(ctx, picker, "setCategory", cats[1]["key"])
    js(ctx, picker, "query = 'yog'")
    QTest.qWait(80)
    popup.close()
    QTest.qWait(200)
    popup.open()
    QTest.qWait(300)
    combo_index = combos[0].property("currentIndex") if combos else None
    if (picker.property("category") == "" and picker.property("query") == ""
            and picker.property("currentPage") == 1 and combo_index == 0):
        ok("reopening starts clean — filter, query, page and the dropdown")
    else:
        bad("reopening starts clean",
            f"category={picker.property('category')!r} "
            f"query={picker.property('query')!r} "
            f"page={picker.property('currentPage')!r} "
            f"combo={combo_index!r}")
    popup.close()

    # ---- 8. the till's routed dialog loads over the same picker -------
    dialog_path = os.path.join(QML_DIR, "dialogs", "ProductPickerDialog.qml")
    dcomp = QQmlComponent(engine, QUrl.fromLocalFile(dialog_path))
    if dcomp.status() != QQmlComponent.Status.Ready:
        bad("ProductPickerDialog loads", dcomp.errorString())
    else:
        dlg = dcomp.createObject(win.contentItem(), {"context": {}})
        if dlg is None:
            bad("ProductPickerDialog loads", dcomp.errorString())
        else:
            ok("ProductPickerDialog loads")
            dlg.open()
            QTest.qWait(400)
            dpickers = [obj for obj in find_all_by_class(dlg, "ProductPicker")
                        if "Popup" not in obj.metaObject().className()
                        and "Dialog" not in obj.metaObject().className()]
            if not dpickers:
                bad("the dialog seats the picker")
            else:
                dp = dpickers[0]
                ok("the dialog seats the picker",
                   f"{len(as_list(dp.property('rows')))} rows, "
                   f"{len(as_list(dp.property('columns')))} columns")
                if dp.property("requireStock") is True:
                    ok("the till's empty-shelf rule is still on")
                else:
                    bad("the till's empty-shelf rule is still on")
            dlg.close()

    print()
    if fails:
        print(f"{len(fails)} FAILED")
        return 1
    print("all spot-checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())



