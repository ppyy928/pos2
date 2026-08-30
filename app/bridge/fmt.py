"""Formatting, in one place, borrowed from pos.

Every amount and quantity QML displays is a string built here. Three controllers
need the same three calls, and pos's `fmt_money` is the single source of truth
for the currency, the decimal count and the rounding rule — so this is a thin
front door to it rather than another implementation.

`currency=False` throughout: a screen prints the currency once, beside the
figure that matters, not on every row of a table.
"""

from __future__ import annotations

from . import legacy


def money(value: object) -> str:
    try:
        return legacy.formatters().fmt_money(value, currency=False)
    except Exception:  # noqa: BLE001
        return "—"


def compact(value: object) -> str:
    """538M for a KPI card. pos pairs it with the full figure in a tooltip."""
    try:
        return legacy.formatters().fmt_compact(value, currency=False)
    except Exception:  # noqa: BLE001
        return "—"


def qty(value: object) -> str:
    try:
        return legacy.formatters().fmt_qty(value)
    except Exception:  # noqa: BLE001
        return ""


def when(value: object) -> str:
    """'2026-08-27 14:05' -> '27/08/2026 14:05'."""
    try:
        return legacy.formatters().fmt_dt(value)
    except Exception:  # noqa: BLE001
        return str(value or "")
