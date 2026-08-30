"""Turning QML values into Python ones.

A JS object handed to a slot typed `QVariant` arrives as a QJSValue, not a dict —
iterating it raises. That is a fact about the boundary rather than about any one
controller, so the conversion lives here and every slot that takes a form payload
uses it.
"""

from __future__ import annotations


def as_dict(value: object) -> dict:
    if value is None:
        return {}
    to_variant = getattr(value, "toVariant", None)
    if callable(to_variant):
        value = to_variant()
    return dict(value) if isinstance(value, dict) else {}


def as_float(value: object, default: float = 0.0) -> float:
    """A number from a text field. "1,5" is one and a half on a French or Arabic
    keyboard, and float() stops at the comma."""
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip().replace(",", "."))
    except (TypeError, ValueError):
        return default
