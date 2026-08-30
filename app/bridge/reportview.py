"""Presentation helpers for the Reports screen.

Split out of admin.py because the six tab builders are the bulk of that file
otherwise, and because none of this touches Qt: it is the layer between raw query
output and the four lists QML draws.

WHERE THE LINE IS

`reportsql` returns numbers. `admin.Reports` decides what a tab shows. This module is
what turns one into the other — a figure into a KPI card, a series into a chart lane,
a list of dicts into a table spec — using `fmt` for money and the catalogue for
labels. Colours never appear: charts carry HUE NAMES and Tokens resolves them.
"""

from __future__ import annotations

from typing import Any

from . import fmt

#: A column's `kind` decides three things at once: how the value is printed, whether
#: the column is right-aligned, and what the CSV writes. Keeping them together is the
#: point — they disagreed in pos, where money was right-aligned in the table and
#: written as display text into the file.
NUMERIC_KINDS = ("money", "count", "qty", "percent", "signed")


def display(value: Any, kind: str) -> str:
    """One value, as the table draws it."""
    if value is None:
        # An absent figure is not a zero. A cash session still open has no variance,
        # and "0.00" would read as "balanced".
        return "—"
    if kind == "money" or kind == "signed":
        return fmt.money(value)
    if kind == "count":
        try:
            return str(int(value))
        except (TypeError, ValueError):
            return str(value)
    if kind == "qty":
        return fmt.qty(value)
    if kind == "percent":
        try:
            return f"{float(value):.1f}%"
        except (TypeError, ValueError):
            return str(value)
    if kind == "datetime":
        return fmt.when(value)
    return str(value)


def csv_value(value: Any, kind: str) -> Any:
    """One value, as the CSV writes it.

    Raw for anything numeric. A spreadsheet has to be able to add a column up, and
    `fmt.money` produces "1,234.50" — text to every spreadsheet there is, and text
    that a locale expecting `;` as its delimiter will also split in half.
    """
    if value is None:
        return ""
    if kind in NUMERIC_KINDS:
        try:
            return float(value)
        except (TypeError, ValueError):
            return value
    return str(value)


def sort_key(value: Any) -> Any:
    """A comparable key that never raises on mixed or missing values.

    Two-part, because Python 3 refuses to compare a float with a string: everything
    numeric sorts before everything textual, and `None` sorts before both. Without
    the tuple a single empty cell in a money column takes the whole sort down.
    """
    if value is None:
        return (0, 0.0, "")
    if isinstance(value, bool):
        return (1, float(value), "")
    if isinstance(value, (int, float)):
        return (1, float(value), "")
    text = str(value)
    return (2, 0.0, text.casefold())


def col(i18n, key: str, header_key: str, header_text: str, kind: str = "text",
        **extra: Any) -> dict:
    """One DataTable column spec, with its header already translated.

    `kind` is carried through rather than consumed here: `display`, `csv_value` and
    the sort all read it back off the spec, so a column's type is declared once.
    """
    spec: dict[str, Any] = {
        "key": key,
        "header": i18n.text(header_key, header_text),
        "kind": kind,
    }
    if kind in NUMERIC_KINDS:
        spec["numeric"] = True
    spec.update(extra)
    return spec


def table(i18n, table_id: str, title_key: str, title_text: str,
          columns: list[dict], rows: list[dict]) -> dict:
    """A table the screen can draw and this module can sort and export.

    `_raw` travels with it and is stripped by the controller into its own store: the
    rows QML sees are formatted strings, and sorting or exporting those would mean
    parsing the formatting back off.
    """
    return {
        "id": table_id,
        "title": i18n.text(title_key, title_text),
        "columns": columns,
        "rows": [],
        "sortColumn": -1,
        "sortDescending": False,
        "_raw": rows,
    }


def delta(value: float, previous: float | None, higher_is_better: bool = True
          ) -> tuple[str, str]:
    """(text, tone) for a change against the previous period.

    Percentage, not a difference: "+12.4%" answers "is this better" and "+412,300.00"
    only answers it for somebody who already knew the base. A base of zero has no
    percentage, so it says so instead of dividing.

    `higher_is_better` inverts the colour, and it has to exist: expenses up is not
    good news, and a green arrow on a rising cost line is worse than no arrow.
    """
    if previous is None:
        return "", ""
    if previous == 0:
        if value == 0:
            return "", ""
        good = value > 0 if higher_is_better else value < 0
        return "", "success" if good else "danger"
    change = (value - previous) / abs(previous) * 100.0
    if abs(change) < 0.05:
        return "0.0%", ""
    good = change > 0 if higher_is_better else change < 0
    return f"{change:+.1f}%", "success" if good else "danger"


def card(i18n, label_key: str, label_text: str, value: float, kind: str = "money",
         tone: str = "primary", glyph: str = "", previous: float | None = None,
         higher_is_better: bool = True, compare: bool = True) -> dict:
    """One KPI card.

    `value` is the compact string and `tooltip` the full-precision one, which is what
    KpiCard expects: a card 320px wide cannot hold "535,550,415.94" at 34px, and
    rounding it away without keeping it anywhere loses the figure.
    """
    amount = float(value or 0.0)
    # "signed" is money whose sign matters, not a separate format. Falling through to
    # the integer branch printed net profit as "2040566".
    if kind in ("money", "signed"):
        text = fmt.compact(amount)
        tooltip = fmt.money(amount)
    elif kind == "percent":
        text = f"{amount:.1f}%"
        tooltip = ""
    elif kind == "qty":
        text = fmt.qty(amount)
        tooltip = ""
    else:
        text = str(int(amount))
        tooltip = ""

    subtext = ""
    subtone = ""
    if compare and previous is not None:
        change, subtone = delta(amount, previous, higher_is_better)
        if change:
            subtext = change + " " + i18n.text("reports.vs_prev", "vs previous")

    return {
        "label": i18n.text(label_key, label_text),
        "value": text,
        "tooltip": tooltip,
        "subtext": subtext,
        "subtextTone": subtone,
        "tone": tone,
        "glyph": glyph,
        # Only where the sign carries meaning, so the screen can colour a loss red
        # without knowing which of thirty metrics are allowed to go negative.
        "raw": amount if kind == "signed" else 0.0,
    }


def lane(i18n, label_key: str, label_text: str, points: list[dict], hue: str,
         field: str = "value", muted: bool = False) -> dict:
    """One line on a chart: `{label, hue, muted, points}`.

    `hue` is a name from Tokens.hue, not a colour — see the module docstring.
    """
    return {
        "label": i18n.text(label_key, label_text) if label_key else label_text,
        "hue": hue,
        "muted": muted,
        "points": [
            {"label": str(p.get("label") or ""),
             "value": float(p.get(field) or 0.0),
             "valueText": fmt.money(p.get(field) or 0.0)}
            for p in points
        ],
    }


def line_chart(i18n, chart_id: str, title_key: str, title_text: str,
               lanes: list[dict], subtitle: str = "", area: bool = True) -> dict:
    return {
        "id": chart_id,
        "kind": "line",
        "title": i18n.text(title_key, title_text),
        "subtitle": subtitle,
        "series": lanes,
        "area": area,
    }


def bars_chart(i18n, chart_id: str, title_key: str, title_text: str,
               rows: list[dict], hue: str, field: str = "value",
               label: str = "label", subtitle: str = "", limit: int = 8) -> dict:
    return {
        "id": chart_id,
        "kind": "bars",
        "title": i18n.text(title_key, title_text),
        "subtitle": subtitle,
        "hue": hue,
        "rows": [
            {"label": str(r.get(label) or ""),
             "value": float(r.get(field) or 0.0),
             "valueText": fmt.money(r.get(field) or 0.0)}
            for r in rows[:limit]
        ],
    }


def donut_chart(i18n, chart_id: str, title_key: str, title_text: str,
                slices: list[dict], subtitle: str = "") -> dict:
    """A donut, and the only shape on this screen that claims its parts are the whole.

    Which is why every caller passes a CLOSED set — payment types, movement types.
    An unbounded breakdown capped at eight reports percentages that do not add up;
    those go to `bars_chart` instead.
    """
    total = sum(float(s.get("value") or 0.0) for s in slices)
    return {
        "id": chart_id,
        "kind": "donut",
        "title": i18n.text(title_key, title_text),
        "subtitle": subtitle,
        "total": fmt.money(total),
        "slices": [
            {"label": str(s.get("label") or ""),
             "value": float(s.get("value") or 0.0),
             "valueText": fmt.money(s.get("value") or 0.0),
             "tone": str(s.get("tone") or "")}
            for s in slices if float(s.get("value") or 0.0) > 0
        ],
    }
