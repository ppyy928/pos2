"""Product photos, in the two shapes the boundary needs.

    a stored name   ->  a `file:///…` URL an `Image` can load
    a picked URL    ->  a filesystem path the data layer can copy

Nothing else. The files themselves belong to the data layer —
`db.store_product_image` writes them, `db.discard_product_image` forgets them and
`db.product_image_file` is the only thing that knows where they live — so this
module holds no path of its own and cannot disagree with it about one.

WHY A URL AND NOT A PATH

`Image.source` is a URL. Handed a bare Windows path, QML reads `C:` as a scheme
it does not know, resolves the rest relative to the QML file and draws nothing —
silently, because an image that will not load is not an error anything reports.
`Path.as_uri()` is the conversion that gets the drive letter, the separators and
the percent-encoding right, and doing it here means no screen has to.

WHY "" IS THE ANSWER FOR A MISSING FILE

A product with no photo and a product whose photo file has been deleted from
under it are the same thing to a card: there is no picture to draw. Both come
back as an empty string, and the placeholder is what the operator sees.
"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QUrl

from .. import diagnostics
from . import legacy


def url_for(name: str) -> str:
    """The URL of one stored photo, or "" when there is nothing to draw."""
    if not name:
        return ""
    try:
        path = legacy.database().product_image_file(str(name))
    except Exception:  # noqa: BLE001 - a missing photo is never worth a failure
        diagnostics.log.debug("photo unavailable for %r", name, exc_info=True)
        return ""
    return path.as_uri() if path is not None else ""


def local_path(url: object) -> str:
    """A file the operator picked, as a path.

    Accepts either form: a QML FileDialog hands over `file:///C:/photos/cola.jpg`
    and a test or an import hands over `C:\\photos\\cola.jpg`.
    """
    raw = str(url or "").strip()
    if not raw:
        return ""
    if "://" in raw:
        return QUrl(raw).toLocalFile()
    return str(Path(raw))
