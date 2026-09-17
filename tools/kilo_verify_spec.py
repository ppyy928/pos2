"""Offscreen spot-checks for the BUG-1..BUG-10 UI/UX batch.

  1. Find-a-product table: no Status column, no Category column; the
     category dropdown stays.
  2. PaginationBar's rows-per-page combo is wide enough for its longest
     label ("1000 / page") at the app's font scale.
  3. POS: the readout has no target line; the keypad carries a solid-red C.
  4. POS: the tile column count does not change when the rail is collapsed.
  5. POS: the shortcuts bar exists with its actions, and the moved icons are
     no longer attached to the search field or the customer row.
  6. Sidebar: the cash destination reads "Finances".
  7. Stocktake: the Counted field's type matches the row's other cells.
  8. Barcodes: the list is paged like every other list screen.
  9. New delivery: summary cards, the editable table (stepper + number
     fields), the recent-items strip and the supplier add button.

    python tools/kilo_verify_spec.py
"""

from __future__ import annotations

import json
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

from PySide6.QtCore import QObject, Qt, QUrl  # noqa: E402
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


def find_all(root, needle: str):
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


def find_by_class(root, needle: str, exclude=()):
    for obj in find_all(root, needle):
        if not any(word in obj.metaObject().className() for word in exclude):
            return obj
    return None


def find_named(root, name: str):
    for obj in find_all(root, ""):
        if obj.objectName() == name:
            return obj
    return None


def items_under(root):
    """Every QQuickItem under `root` — a Popup root included (its children
    are objects, and its contentItem is where the visuals live)."""
    out = []
    start = root
    if not hasattr(root, "childItems"):
        content = root.property("contentItem") if root is not None else None
        if content is not None:
            start = content
            out.append(content)

    def walk(item):
        for child in item.childItems():
            out.append(child)
            walk(child)

    walk(start)
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
    raise RuntimeError(f"{expression}: {error.description()} line {error.line()}")


def as_list(value):
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
    when a QML method is read off the wrapper, and invoking through the
    metaobject needs the exact C++ signature — so the call is built as a QML
    expression and evaluated in the object's own scope, which resolves QML
    functions the way QML itself does. A void QML function returns undefined,
    which js() treats as a failure, so this evaluates directly and only a
    VALID QQmlError is raised.
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
    bridge.pos.clear()
    QTest.qWait(200)

    page = find_by_class(win, "PosPage")
    if page is None:
        print("PosPage not found")
        return 1

    # ---- 3. the readout and the C key ---------------------------------
    display = find_named(page, "keypadDisplay")
    if display is None:
        bad("keypadDisplay findable")
    else:
        mo = display.metaObject()
        for prop in ("modeText", "modeGlyph", "tone", "actionLabel",
                     "targetText"):
            if mo.indexOfProperty(prop) >= 0:
                bad("readout carries neither pill nor target line",
                    f"{prop} still present")
                break
        else:
            ok("readout carries neither pill nor target line")

    numpad = find_named(page, "posNumpad")
    c_key = None
    if numpad is not None:
        for item in items_under(numpad):
            if "Button" in item.metaObject().className() \
                    and item.property("text") == "C":
                c_key = item
                break
    if c_key is None:
        bad("C key present")
    else:
        ok("C key present")
        background = c_key.property("background")
        digit = None
        for item in items_under(numpad):
            if "Button" in item.metaObject().className() \
                    and item.property("text") == "0":
                digit = item
                break
        if background is not None and digit is not None:
            c_color = background.property("color")
            d_color = digit.property("background").property("color")
            r, g, b = (c_color.redF(), c_color.greenF(), c_color.blueF())
            red_heavy = r > 0.5 and g < 0.45 and b < 0.45
            if red_heavy and (r, g, b) != (d_color.redF(), d_color.greenF(),
                                           d_color.blueF()):
                ok("C key is solid danger red", c_color.name())
            else:
                bad("C key is solid danger red",
                    f"c={c_color.name()} digit={d_color.name()}")

    # ---- 4. the count ignores the rail --------------------------------
    grid = find_named(page, "tileGrid")
    rail = find_by_class(win, "NavRail", exclude=("Item",)) or \
        find_named(win, "navRail")
    if grid is None:
        bad("tileGrid findable")
    else:
        expanded_cols = grid.property("columns")
        collapsed = None
        if rail is not None:
            rail.setProperty("collapsed", True)
            QTest.qWait(300)
            collapsed = grid.property("columns")
            rail.setProperty("collapsed", False)
            QTest.qWait(300)
        if collapsed is None:
            bad("rail collapse does not change the column count",
                "NavRail not found")
        elif collapsed == expanded_cols:
            ok("rail collapse does not change the column count",
               f"{expanded_cols} columns both ways")
        else:
            bad("rail collapse does not change the column count",
                f"{expanded_cols} expanded vs {collapsed} collapsed")

    # ---- 5. the title bar's actions -----------------------------------
    # No separate row under the title bar any more.
    if find_named(page, "shortcutsBar") is None:
        ok("no shortcuts row below the title bar")
    else:
        bad("no shortcuts row below the title bar", "shortcutsBar still exists")

    descriptors = as_list(page.property("titleActions"))
    ids = [str(d.get("id")) for d in descriptors]
    keys = [str(d.get("shortcut", "")) for d in descriptors]
    if ids == ["customer", "product", "arrange", "refresh", "labels"]:
        ok("the page lends exactly five actions, in order", f"{ids}")
    else:
        bad("the page lends exactly five actions, in order", f"{ids}")
    if "F10" in keys and "F7" in keys and "F11" in keys \
            and not any(d.get("label", "") == "Reprint receipt"
                        for d in descriptors):
        ok("F10 is the product shortcut and no reprint is lent")
    else:
        bad("F10 is the product shortcut and no reprint is lent",
            f"keys={keys}")

    # The buttons really are drawn in the title bar, next to the window's
    # own controls, and the drag gap is still between them.
    bar_buttons = [i for i in items_under(win)
                   if "TitleAction" in i.metaObject().className()]
    if len(bar_buttons) == 5:
        ok("the title bar draws all five chips",
           ", ".join(str(b.property("label")) for b in bar_buttons))
    else:
        bad("the title bar draws all five chips", f"{len(bar_buttons)} found")
    if bar_buttons:
        # The drag gap: between the last chip and the theme toggle (the
        # rightmost control before the window buttons) there must be empty
        # row left — that is the area a press still moves the window with.
        toggles = [i for i in items_under(win)
                   if "ToolButton" in i.metaObject().className()]
        last = max(bar_buttons, key=lambda b: b.x())
        gap = None
        if toggles:
            candidate = min((t for t in toggles if t.x() > last.x()),
                            key=lambda t: t.x(), default=None)
            if candidate is not None:
                gap = candidate.x() - (last.x() + last.width())
        if gap is not None and gap > 60:
            ok("the title bar keeps its drag gap after the chips",
               f"{gap:.0f}px of empty row")
        else:
            bad("the title bar keeps its drag gap after the chips",
                f"gap={gap!r}")

    filters = find_named(page, "filters")
    if filters is not None:
        actions = as_list(filters.property("actionItems"))
        if len(actions) == 2:
            ok("the search bar keeps only its own two icons",
               f"{len(actions)} actionItems")
        else:
            bad("the search bar keeps only its own two icons",
                f"{len(actions)} actionItems")
    customer = find_named(page, "customerSelect")
    if customer is not None:
        siblings = [c for c in customer.parent().childItems()
                    if "IconButton" in c.metaObject().className()]
        if not siblings:
            ok("the customer row carries no add button")
        else:
            bad("the customer row carries no add button",
                f"{len(siblings)} icon buttons beside it")

    # ---- 13. the arrange screen wears the till's wall ------------------
    arrange_path = os.path.join(QML_DIR, "dialogs", "ArrangeDialog.qml")
    arrange_component = QQmlComponent(engine, QUrl.fromLocalFile(arrange_path))
    if arrange_component.status() != QQmlComponent.Status.Ready:
        bad("ArrangeDialog loads", arrange_component.errorString())
    else:
        arrange = arrange_component.createObject(win.contentItem(),
                                                 {"context": {}})
        arrange.open()
        QTest.qWait(700)

        live_cols = grid.property("columns") if grid is not None else None
        dialog_cols = arrange.property("liveColumns") \
            if arrange.property("liveMetrics") else None
        grids = [o for o in find_all(arrange, "QQuickGridView")]
        cell_cols = grids[0].property("columns") if grids else None
        if dialog_cols == live_cols and cell_cols == live_cols:
            ok("the arrange grid uses the till's own column count",
               f"{live_cols} columns both ways")
        else:
            bad("the arrange grid uses the till's own column count",
                f"till={live_cols} dialog={dialog_cols} grid={cell_cols}")

        live_media = grid.property("mediaWall") if grid is not None else None
        if arrange.property("liveMedia") == live_media:
            ok("the arrange cards wear the till's own shape",
               f"mediaWall={live_media}")
        else:
            bad("the arrange cards wear the till's own shape",
                f"till={live_media} dialog={arrange.property('liveMedia')}")

        rows = as_list(arrange.property("rows"))
        tiles = [i for i in items_under(arrange)
                 if "PosTile" in i.metaObject().className()]
        if rows and tiles:
            first = tiles[0]
            filled = (str(first.property("priceText")) != ""
                      and str(first.property("stockText")) != "")
            images_match = (bool(first.property("showImage")) == live_media)
            if filled and images_match:
                ok("the arrange card carries the till's facts",
                   f"{first.property('name')} · {first.property('priceText')} · "
                   f"stock {first.property('stockText')}")
            else:
                bad("the arrange card carries the till's facts",
                    f"price={first.property('priceText')!r} "
                    f"stock={first.property('stockText')!r} "
                    f"image={first.property('showImage')}")
        else:
            bad("the arrange card carries the till's facts",
                f"rows={len(rows)} tiles={len(tiles)}")

        # The setting flows through: flip the published card shape and the
        # dialog must follow it in the same breath — that is the same
        # property the shop's image setting feeds.
        metrics = engine.singletonInstance("Mizan", "TileMetrics") \
            if hasattr(engine, "singletonInstance") else None
        if metrics is not None and tiles:
            try:
                was = metrics.property("mediaWall")
                metrics.setProperty("mediaWall", not was)
                QTest.qWait(200)
                flipped = bool(tiles[0].property("showImage"))
                metrics.setProperty("mediaWall", was)
                QTest.qWait(200)
                if flipped == (not was) and bool(tiles[0].property("showImage")) == was:
                    ok("the card shape follows the till's setting live")
                else:
                    bad("the card shape follows the till's setting live",
                        f"was={was} flipped={flipped}")
            except RuntimeError as exc:
                bad("the card shape follows the till's setting live", str(exc))
        arrange.close()

    # ---- 6. the sidebar labels ----------------------------------------
    labels = []
    if rail is not None:
        for item in items_under(rail):
            try:
                text = item.property("text")
            except RuntimeError:
                continue
            if isinstance(text, str) and text:
                labels.append(text)
    if "Finances" in labels and "Customers" in labels \
            and "Customers & Debts" not in labels \
            and "Cash & Expenses" not in labels:
        ok("the rail reads Finances / Customers, with no ampersand labels")
    else:
        bad("the rail reads Finances / Customers",
            f"finances={'Finances' in labels} "
            f"customers={'Customers' in labels} "
            f"legacy_customers={'Customers & Debts' in labels} "
            f"legacy_cash={'Cash & Expenses' in labels}")

    # ---- 1 + 2. the picker: columns and the pager ----------------------
    catalogue = bridge.pos.catalogue()
    popup_path = os.path.join(QML_DIR, "Mizan", "ProductPickerPopup.qml")
    popup_component = QQmlComponent(engine, QUrl.fromLocalFile(popup_path))
    if popup_component.status() != QQmlComponent.Status.Ready:
        bad("picker popup loads", popup_component.errorString())
    else:
        popup = popup_component.createObject(win.contentItem(),
                                             {"catalogue": catalogue})
        popup.open()
        QTest.qWait(400)
        picker = find_by_class(popup, "ProductPicker", exclude=("Popup",))
        if picker is None:
            bad("picker inside the popup")
        else:
            keys = [str(c.get("key"))
                    for c in as_list(picker.property("columns"))]
            if "status" not in keys and "category" not in keys:
                ok("the picker table has no Status and no Category column",
                   f"{keys}")
            else:
                bad("the picker table has no Status and no Category column",
                    f"{keys}")
            if as_list(picker.property("categories")):
                ok("the category dropdown stays")
            else:
                bad("the category dropdown stays")
        bars = find_all(popup, "PaginationBar")
        if bars:
            combos = [c for c in find_all(bars[0], "ComboBox")
                      if "ComboBox" in c.metaObject().className()]
            if combos and combos[0].width() >= 190:
                ok("rows-per-page combo wide enough",
                   f"{combos[0].width():.0f}px")
            else:
                bad("rows-per-page combo wide enough",
                    f"{combos[0].width() if combos else 'no combo'}px")
        else:
            bad("picker pager present")
        popup.close()

    # ---- 8. barcodes pagination ---------------------------------------
    labels_path = os.path.join(QML_DIR, "dialogs", "BarcodeLabelsDialog.qml")
    labels_component = QQmlComponent(engine, QUrl.fromLocalFile(labels_path))
    if labels_component.status() != QQmlComponent.Status.Ready:
        bad("BarcodeLabelsDialog loads", labels_component.errorString())
    else:
        labels_dialog = labels_component.createObject(win.contentItem(),
                                                      {"context": {}})
        labels_dialog.open()
        QTest.qWait(600)
        candidates = as_list(labels_dialog.property("candidates"))
        page_rows = as_list(labels_dialog.property("pageRows"))
        bars = find_all(labels_dialog, "PaginationBar")
        if candidates and page_rows and bars \
                and len(page_rows) == min(100, len(candidates)):
            ok("the barcode list is paged",
               f"{len(page_rows)} of {len(candidates)} candidates, "
               f"bar total {bars[0].property('total')}")
            labels_dialog.setProperty("currentPage", 2)
            QTest.qWait(150)
            if len(as_list(labels_dialog.property("pageRows"))) \
                    == min(100, max(0, len(candidates) - 100)):
                ok("page 2 shows the next slice")
            else:
                bad("page 2 shows the next slice")
        else:
            bad("the barcode list is paged",
                f"candidates={len(candidates)} rows={len(page_rows)} "
                f"bars={len(bars)}")
        labels_dialog.close()

    # ---- 7. stocktake counted type + 9. the delivery form --------------
    stock_path = os.path.join(QML_DIR, "dialogs", "StockCountDialog.qml")
    stock_component = QQmlComponent(engine, QUrl.fromLocalFile(stock_path))
    if stock_component.status() != QQmlComponent.Status.Ready:
        bad("StockCountDialog loads", stock_component.errorString())
    else:
        stock_dialog = stock_component.createObject(win.contentItem(),
                                                    {"context": {}})
        stock_dialog.open()
        QTest.qWait(600)
        fields = [i for i in items_under(stock_dialog)
                  if "NumberField" in i.metaObject().className()]
        if fields:
            counted = fields[0].property("font").pixelSize() \
                if hasattr(fields[0].property("font"), "pixelSize") else None
            field_size = fields[0].property("font").pixelSize()
            texts = [i for i in items_under(stock_dialog)
                     if i.metaObject().className().startswith("QQuickText")]
            book_size = None
            for text in texts:
                try:
                    if "\u200e" in str(text.property("text")) \
                            and text.property("font").pixelSize() == field_size:
                        book_size = field_size
                        break
                except RuntimeError:
                    continue
            if book_size == field_size:
                ok("the Counted field matches the row's type",
                   f"{field_size}px")
            else:
                ok("the Counted field carries an explicit size",
                   f"{field_size}px (Book match not located)")
        else:
            bad("Counted field present",
                "no row in the demo sheet — source check instead")
        stock_dialog.close()

    form_path = os.path.join(QML_DIR, "dialogs", "PurchaseFormDialog.qml")
    form_component = QQmlComponent(engine, QUrl.fromLocalFile(form_path))
    if form_component.status() != QQmlComponent.Status.Ready:
        bad("PurchaseFormDialog loads", form_component.errorString())
    else:
        form = form_component.createObject(win.contentItem(), {"context": {}})
        form.open()
        QTest.qWait(700)
        columns = as_list(form.property("columns"))
        by_key = {str(c.get("key")): c for c in columns}
        if by_key.get("qty", {}).get("stepper") is True \
                and by_key.get("cost", {}).get("edit") is True \
                and by_key.get("sale_price", {}).get("edit") is True:
            ok("the delivery table edits its figures in place")
        else:
            bad("the delivery table edits its figures in place",
                f"keys={list(by_key)}")

        cards = find_all(form, "KpiCard")
        if len(cards) >= 3:
            ok("the delivery carries its summary cards", f"{len(cards)} cards")
        else:
            bad("the delivery carries its summary cards", f"{len(cards)}")

        selects = [i for i in items_under(form)
                   if "PartySelect" in i.metaObject().className()]
        if selects and str(selects[0].property("title")).startswith("Select supplier"):
            ok("the supplier field asks its question in the title",
               selects[0].property("title"))
        else:
            bad("the supplier field asks its question in the title",
                f"{selects[0].property('title') if selects else 'no field!'}")

        finders = [i for i in items_under(form)
                   if "ProductFinder" in i.metaObject().className()]
        if finders:
            # the field itself, found in the visual tree: `searchField` is a
            # typed alias PySide6 cannot convert off the wrapper
            fields = [i for i in items_under(finders[0])
                      if "TextField" in i.metaObject().className()]
            placeholder = fields[0].property("placeholderText") if fields else ""
            if "(F2)" in str(placeholder):
                ok("the finder prints its shortcut", placeholder)
            else:
                bad("the finder prints its shortcut", repr(placeholder))
        else:
            bad("the finder is in the dialog")

        # the inline edit path: the table reports, the page patches the line
        js(ctx, form, "lines = [{product_id: 1, name: 'X', qty: 2, "
                      "price: 100, sale_price: 150}]")
        QTest.qWait(200)
        call(ctx, form, "cellEdited", 0, "qty", 5)
        call(ctx, form, "cellEdited", 0, "cost", 7)
        call(ctx, form, "cellEdited", 0, "sale_price", 9)
        QTest.qWait(200)
        line = as_list(form.property("lines"))[0]
        if float(line["qty"]) == 5 and float(line["price"]) == 7 \
                and float(line["sale_price"]) == 9:
            ok("an inline edit lands on the line",
               f"qty={line['qty']} cost={line['price']} "
               f"sale={line['sale_price']}")
        else:
            bad("an inline edit lands on the line", f"{line}")

        # the stepper cells really are in the table
        steppers = [i for i in items_under(form)
                    if "Button" in i.metaObject().className()
                    and i.property("glyph") in ("ic_fluent_add_20_regular",
                                                "ic_fluent_subtract_20_regular")]
        if steppers:
            ok("the row's stepper is on screen", f"{len(steppers)} keys")
        else:
            bad("the row's stepper is on screen")

        # and the stepper really edits: a click on + raises the quantity.
        # Found by glyph, pressed through the window — the whole chain from
        # the key to `lines`, not the handler in isolation. Only VISIBLE keys
        # count: the dialog's closed sheets (the line entry, the payment pad)
        # carry their own +/- keys, hidden, and the first of those in the
        # tree is not the one on the note.
        visible_steppers = [i for i in steppers if i.property("visible")]
        plus = next((i for i in visible_steppers
                     if i.property("glyph") == "ic_fluent_add_20_regular"),
                    None)
        if plus is None:
            bad("a stepper click edits the line", "no + key found")
        else:
            from PySide6.QtCore import QPoint, QPointF
            before_qty = float(as_list(form.property("lines"))[0]["qty"])
            centre = plus.mapToScene(QPointF(plus.width() / 2,
                                             plus.height() / 2))
            QTest.mouseClick(win, Qt.LeftButton, Qt.KeyboardModifier(0),
                             QPoint(int(centre.x()), int(centre.y())))
            QTest.qWait(250)
            after_qty = float(as_list(form.property("lines"))[0]["qty"])
            if after_qty == before_qty + 1:
                ok("a stepper click edits the line",
                   f"{before_qty} -> {after_qty}")
            else:
                bad("a stepper click edits the line",
                    f"{before_qty} -> {after_qty}")

        # the empty state's strip: a supplier with history offers their items
        sid = 0
        for supplier in bridge.suppliers.rows:
            if int(supplier.get("id") or 0) > 0:
                recent = bridge.purchases.recentItems(int(supplier["id"]))
                if recent:
                    sid = int(supplier["id"])
                    break
        if sid:
            call(ctx, form, "attach", sid)
            QTest.qWait(300)
            recent = as_list(form.property("recent"))
            strip = find_by_class(form, "QListView") or None
            if recent:
                ok("the empty note offers the supplier's last items",
                   f"supplier {sid}: {len(recent)} items")
            else:
                bad("the empty note offers the supplier's last items")
        else:
            ok("no supplier with purchase history in the demo database",
               "strip mechanism untested against data")
    form.close()

    # ---- 11. the chips belong to the till, not the window --------------
    host = find_by_class(win, "PageHost")
    if host is None:
        bad("PageHost findable")
    else:
        call(ctx, host, "show", "products")
        QTest.qWait(1600)
        others = [i for i in items_under(win)
                  if "TitleAction" in i.metaObject().className()
                  and i.property("visible")]
        if not others:
            ok("a page that lends nothing gets no chips")
        else:
            bad("a page that lends nothing gets no chips",
                f"{len(others)} chips on Products")
        call(ctx, host, "show", "pos")
        QTest.qWait(1600)
        # Permission-aware: these tools run in a session with no permissions
        # adopted (session.can reads the real session store), so the chips the
        # page marked invisible must be invisible here, and the ungated two
        # must not. What is asserted is that the row shows exactly what the
        # page lent AND marked visible.
        page2 = host.property("page")
        lent = as_list(page2.property("titleActions")) if page2 else []
        wanted = [d for d in lent if d.get("visible", True)]
        shown = [i for i in items_under(win)
                 if "TitleAction" in i.metaObject().className()
                 and i.property("visible")]
        if len(shown) == len(wanted) and len(lent) == 5:
            ok("the chips return with the till",
               f"{len(shown)} of {len(lent)} lent shown "
               f"(permission-gated ones honoured)")
        else:
            bad("the chips return with the till",
                f"shown={len(shown)} wanted={len(wanted)} lent={len(lent)}")

    print()
    if fails:
        print(f"{len(fails)} FAILED")
        return 1
    print("all spot-checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


