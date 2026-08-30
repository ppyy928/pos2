"""app.printing — everything that reaches a printer, and everything that shows the
operator what it will look like first.

    app.printing    preview, printerName, available, busy, error
                    previewSale(id) / printSale(id, copies, cashier)
                    previewPurchase(id) / printPurchase(id, copies)
                    previewLabel(item) / printLabels(items)

WHY ONE CONTROLLER AND NOT THREE

The purchase invoice would otherwise live in `Purchases` and the shelf label in
`Catalogue` — a copy of a thread pool in each, a copy of "the printer is missing",
and three ways to spell the same failure. What these jobs share is a device, a
renderer and the fact that both can fail slowly; what they do not share is the
record being printed, and that is already a parameter.

`Sales.printReceipt` stays where it is on purpose. It is the sale's own reprint,
already wired to the sales table, the sale dialog and the auto-print connection in
root.py, and it already runs on this same global pool — moving it here would be a
rewrite of a working path for the sake of a diagram. What was missing was never the
receipt: it was the preview, the purchase invoice and the label sheet.

WHY A PREVIEW EXISTS AT ALL

pos prints blind: the only way to find out what a receipt looks like is to spend a
receipt, and the only way to find out that the label's barcode is unreadable is to
print forty of them. Both renderers already return a PIL image and neither module
needed changing — `render_preview` and `render_label_image` are the same calls the
print path makes, one step earlier. The preview is written as a PNG into the
system temp directory and handed to QML as a file URL, because an Image with a
source is a hundredth of the code of a custom QQuickImageProvider and behaves
identically for something this size.

The URL carries a `?v=` counter. Qt caches images by URL, so re-rendering to the
same path would show the first receipt forever.

WHY PRINTING IS OFF THE GUI THREAD AND PREVIEWING IS NOT

A print is a conversation with a device: it can be missing, out of paper, or simply
slow, and none of that may freeze a till that has already taken the money. A
preview is Pillow drawing onto a bitmap — tens of milliseconds, no device, no
failure mode worth a callback. So one goes to the pool and the other does not, and
the operator is never waiting on a spinner for a picture.
"""

from __future__ import annotations

import os
import tempfile
from typing import Any

from PySide6.QtCore import (
    Property,
    QObject,
    QRunnable,
    QThreadPool,
    Signal,
    Slot,
)

from . import fmt, interop, legacy

#: Where previews are written. One directory, reused, with a stable name per kind —
#: a temp file per preview would leak one file per keystroke in the label sheet,
#: where the preview re-renders as the operator types a price.
_PREVIEW_DIR = os.path.join(tempfile.gettempdir(), "mizan-preview")


class Printing(QObject):
    """The device layer, for QML."""

    #: A job finished. `what` is "sale" | "purchase" | "labels", `count` is how
    #: many pieces of paper were sent.
    printed = Signal("QVariant")
    #: A job failed, with a sentence for the operator.
    printFailed = Signal(str)

    previewChanged = Signal()
    busyChanged = Signal()
    errorChanged = Signal()

    #: Internal, pool thread -> GUI thread: (what, count, error). A plain signal
    #: rather than a callback because a cross-thread signal is the one hand-off Qt
    #: guarantees; calling a method on the controller from the pool would touch
    #: Qt state from the wrong thread.
    _finished = Signal(str, int, str)

    def __init__(self, i18n, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._i18n = i18n
        self._preview = ""
        self._preview_size = [0, 0]
        self._version = 0
        self._busy = 0
        self._error = ""
        #: Held, not auto-deleted: a QRunnable the pool owns can be collected out
        #: from under the signal it is about to emit. Same pattern as _LoginTask.
        self._jobs: list[QRunnable] = []
        self._finished.connect(self._settle)

    # =====================================================================
    # STATE
    # =====================================================================
    @Property(str, notify=previewChanged)
    def preview(self) -> str:
        """A file URL for QML's Image.source, or "" when nothing is rendered."""
        return self._preview

    @Property("QVariantList", notify=previewChanged)
    def previewSize(self) -> list:
        """[width, height] in pixels of the rendered image, so QML can scale it to
        the panel without guessing the aspect ratio of an 80mm roll."""
        return list(self._preview_size)

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy > 0

    @Property(str, notify=errorChanged)
    def error(self) -> str:
        return self._error

    @Property(str, constant=True)
    def receiptPrinter(self) -> str:
        """The receipt printer's name, or "" when the platform will not say.

        Shown rather than assumed: "printed" with nothing coming out of a printer
        is the single most confusing outcome this feature has, and naming the
        destination up front is most of the cure.
        """
        return self._printer_name("receipt.printer")

    @Property(str, constant=True)
    def labelPrinter(self) -> str:
        return self._printer_name("barcode.printer")

    def _printer_name(self, setting: str) -> str:
        try:
            database = legacy.database()
            configured = (database.get_setting(setting, "") or "").strip()
            if configured:
                return configured
            return str(legacy.labels().default_printer_name() or "")
        except Exception:  # noqa: BLE001
            return ""

    @Property(bool, constant=True)
    def available(self) -> bool:
        """Whether the renderers import at all.

        Pillow, arabic_reshaper and python-escpos are real dependencies, and a
        packaged build that lost one of them should grey the print buttons out
        rather than answer every press with a traceback.
        """
        try:
            legacy.printing()
            legacy.labels()
        except Exception:  # noqa: BLE001
            return False
        return True

    # =====================================================================
    # PREVIEW
    # =====================================================================
    @Slot(int)
    def previewSale(self, sale_id: int) -> None:
        self._render("sale", int(sale_id))

    @Slot(int)
    def previewPurchase(self, invoice_id: int) -> None:
        self._render("purchase", int(invoice_id))

    @Slot("QVariant")
    def previewLabel(self, item: object) -> None:
        """One label, from the sheet's own row rather than from the database: the
        operator is editing the price and the name in front of them and the picture
        has to be of what they typed."""
        self._render("label", interop.as_dict(item) or {})

    @Slot()
    def clearPreview(self) -> None:
        self._set_preview("", 0, 0)

    # =====================================================================
    # WHAT CAN BE LABELLED
    # =====================================================================
    @Slot(str, int, result="QVariantList")
    def labelCandidates(self, search: str, category_id: int) -> list:
        """Products the label sheet can offer, with a RAW price.

        Its own query rather than `Products.rows`, for one reason: that row shape
        formats `sale_price` for a table cell, and "1,658.74" is a string a label
        renderer has to parse back into a number — through a thousands separator
        that changes with the language. The sheet needs the number, so it asks the
        database for the number.

        `has_barcode` travels with each row because a label without bars is a
        rectangle of paper: the sheet greys those out and says why, rather than
        printing forty blanks.
        """
        database = legacy.database()
        try:
            payload = database.fetch_products(
                str(search or ""), 1, 400, int(category_id) or None
            )
        except Exception as exc:  # noqa: BLE001
            self._set_error(str(exc))
            return []

        out = []
        no_code = self._i18n.text("barcode.none", "no barcode")
        for row in payload.get("rows", []):
            barcode = str(row.get("barcode") or "").strip()
            price = float(row.get("sale_price") or 0.0)
            out.append({
                "id": row["id"],
                "name": row.get("name") or "",
                "barcode": barcode,
                # What the cell shows. An empty barcode cell is indistinguishable
                # from a rendering fault, so the row says which it is; and
                # DataTable renders `column.key` verbatim, so the sentence is built
                # here rather than by a formatter it does not have.
                "barcode_text": barcode if barcode else no_code,
                "has_barcode": barcode != "",
                "price": price,
                "price_text": fmt.money(price),
                "category": row.get("category") or "",
            })
        return out

    def _render(self, kind: str, subject: object) -> None:
        self._set_error("")
        try:
            image = self._image(kind, subject)
        except Exception as exc:  # noqa: BLE001
            self._set_preview("", 0, 0)
            self._set_error(str(exc))
            return
        if image is None:
            self._set_preview("", 0, 0)
            self._set_error(self._i18n.text("print.nothing", "Nothing to print."))
            return

        os.makedirs(_PREVIEW_DIR, exist_ok=True)
        path = os.path.join(_PREVIEW_DIR, f"{kind}.png")
        try:
            image.save(path)
        except Exception as exc:  # noqa: BLE001
            self._set_preview("", 0, 0)
            self._set_error(str(exc))
            return

        self._version += 1
        url = "file:///" + path.replace("\\", "/") + f"?v={self._version}"
        self._set_preview(url, image.width, image.height)

    def _image(self, kind: str, subject: object):
        """The same call the print path makes, one step earlier."""
        database = legacy.database()
        if kind == "sale":
            receipts = legacy.printing()
            sale = database.fetch_sale(int(subject))
            if sale is None:
                return None
            printer = receipts.receipt_printer_from_settings()
            built = receipts.build_receipt_for_sale(
                sale, currency=printer.cfg.currency
            )
            return printer.render_preview(built)
        if kind == "purchase":
            receipts = legacy.printing()
            invoice = database.fetch_purchase_invoice(int(subject))
            if invoice is None:
                return None
            printer = receipts.receipt_printer_from_settings()
            built = receipts.build_receipt_for_purchase(
                invoice, currency=printer.cfg.currency
            )
            return printer.render_preview(built)
        if kind == "label":
            labels = legacy.labels()
            row = subject if isinstance(subject, dict) else {}
            if not str(row.get("name") or "") and not str(row.get("barcode") or ""):
                return None
            printer = labels.label_printer_from_settings()
            return labels.render_label_image(
                row, printer.cfg, labels.load_label_options()
            )
        return None

    # =====================================================================
    # PRINT
    # =====================================================================
    @Slot(int)
    @Slot(int, int)
    @Slot(int, int, str)
    def printSale(self, sale_id: int, copies: int = 0, cashier: str = "") -> None:
        if not sale_id:
            return
        self._start("sale", {"id": int(sale_id), "copies": int(copies or 0),
                             "cashier": str(cashier or "")})

    @Slot(int)
    @Slot(int, int)
    def printPurchase(self, invoice_id: int, copies: int = 0) -> None:
        if not invoice_id:
            return
        self._start("purchase", {"id": int(invoice_id),
                                 "copies": int(copies or 0)})

    @Slot("QVariant")
    def printLabels(self, items: object) -> None:
        """`items` is [{name, barcode, price, copies}] — the sheet's queue, in the
        order it is shown, because a roll of labels comes off in that order and an
        operator matching them to shelves depends on it."""
        rows = []
        raw = items
        to_variant = getattr(raw, "toVariant", None)
        if callable(to_variant):
            raw = to_variant()
        for entry in (raw or []):
            row = entry if isinstance(entry, dict) else interop.as_dict(entry)
            if not row:
                continue
            copies = max(1, int(interop.as_float(row.get("copies")) or 1))
            rows.append({
                "name": str(row.get("name") or ""),
                "barcode": str(row.get("barcode") or ""),
                "price": interop.as_float(row.get("price")),
                "copies": copies,
            })
        if not rows:
            self.printFailed.emit(
                self._i18n.text("print.nothing", "Nothing to print.")
            )
            return
        self._start("labels", {"items": rows})

    def _start(self, what: str, payload: dict[str, Any]) -> None:
        self._set_error("")
        self._busy += 1
        self.busyChanged.emit()
        job = _Job(self, what, payload)
        job.setAutoDelete(False)
        self._jobs.append(job)
        QThreadPool.globalInstance().start(job)

    def _settle(self, what: str, count: int, error: str) -> None:
        self._busy = max(0, self._busy - 1)
        self.busyChanged.emit()
        self._jobs = self._jobs[-4:]
        if error:
            self._set_error(error)
            self.printFailed.emit(error)
            return
        if count <= 0:
            message = self._i18n.text("toast.print_failed")
            self._set_error(message)
            self.printFailed.emit(message)
            return
        self.printed.emit({"what": what, "count": int(count)})

    # =====================================================================
    # INTERNALS
    # =====================================================================
    def _set_preview(self, url: str, width: int, height: int) -> None:
        if self._preview == url and self._preview_size == [width, height]:
            return
        self._preview = url
        self._preview_size = [int(width), int(height)]
        self.previewChanged.emit()

    def _set_error(self, message: str) -> None:
        if self._error == message:
            return
        self._error = message
        self.errorChanged.emit()


class _Job(QRunnable):
    """One print, on a pool thread. Never touches Qt state — it reports through
    the controller's private signal, which crosses back to the GUI thread."""

    def __init__(self, owner: Printing, what: str, payload: dict[str, Any]) -> None:
        super().__init__()
        self._owner = owner
        self._what = what
        self._payload = payload

    def run(self) -> None:
        try:
            count = self._send()
        except Exception as exc:  # noqa: BLE001
            # A missing printer, a missing font, a missing Pillow: all of them are
            # a sentence for the operator rather than a crashed thread.
            self._owner._finished.emit(self._what, 0, str(exc))
            return
        self._owner._finished.emit(self._what, int(count), "")

    def _send(self) -> int:
        if self._what == "sale":
            receipts = legacy.printing()
            copies = self._payload["copies"] or None
            ok = receipts.print_sale_by_id(
                self._payload["id"], copies=copies,
                cashier=self._payload["cashier"],
            )
            return int(copies or 1) if ok else 0
        if self._what == "purchase":
            receipts = legacy.printing()
            copies = self._payload["copies"] or None
            ok = receipts.print_purchase_by_id(self._payload["id"], copies=copies)
            return int(copies or 1) if ok else 0
        if self._what == "labels":
            labels = legacy.labels()
            return int(labels.print_labels(self._payload["items"]) or 0)
        return 0
