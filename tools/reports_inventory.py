"""Extract the Reports section's exact structure from the code.

Reads app/bridge/admin.py, follows the `rv.table(...)` / `rv.col(...)` call
graph in each `_build_<tab>` method (including the two aliased column lists in
the P&L builder), and resolves every label/header through the real merged
catalogue, so the output is what the UI shows — not the English fallbacks in
the call sites.

    python tools/reports_inventory.py
"""

from __future__ import annotations

import ast
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "vendor"))
os.chdir(ROOT)

ADMIN = os.path.join(ROOT, "app", "bridge", "admin.py")

TAB_ORDER = [
    ("sales", "reports.tab.sales", "Sales"),
    ("inventory", "reports.tab.inventory", "Inventory"),
    ("purchases", "reports.tab.purchases", "Purchases"),
    ("customers", "reports.tab.customers", "Customers"),
    ("cash", "reports.tab.cash", "Cash"),
    ("pnl", "reports.tab.pnl", "Profit & loss"),
]


def const(node):
    if isinstance(node, ast.Constant):
        return node.value
    return None


def col_spec(node):
    """`rv.col(i18n, key, header_key, header_text, **extra)` -> (key, hkey, htext)."""
    if not isinstance(node, ast.Call):
        return None
    func = node.func
    if not (isinstance(func, ast.Attribute) and func.attr == "col"):
        return None
    args = node.args
    return {"key": const(args[1]), "header_key": const(args[2]),
            "header_text": const(args[3])}


def table_spec(node):
    """`rv.table(i18n, id, title_key, title_text, columns, rows)` -> dict."""
    if not isinstance(node, ast.Call):
        return None
    func = node.func
    if not (isinstance(func, ast.Attribute) and func.attr == "table"):
        return None
    args = node.args
    return {"id": const(args[1]), "title_key": const(args[2]),
            "title_text": const(args[3]), "columns_node": args[4]}


def resolve_columns(node, lists):
    if isinstance(node, ast.Name):
        return lists.get(node.id, [])
    if isinstance(node, ast.List):
        return [col_spec(e) for e in node.elts if col_spec(e) is not None]
    return []


def main() -> int:
    from app.bridge.i18n import I18n

    i18n = I18n()

    def text(key, fallback):
        return i18n.text(key, fallback) if key else fallback

    tree = ast.parse(open(ADMIN, encoding="utf-8").read())

    builders = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name.startswith("_build_"):
            builders[node.name[len("_build_"):]] = node

    print("REPORTS — exact structure as rendered (merged catalogue, en)\n")

    for tab, title_key, title_fallback in TAB_ORDER:
        builder = builders.get(tab)
        print(f"== {text(title_key, title_fallback)} ({tab}) ==")
        if builder is None:
            print("   (no builder!)")
            continue

        lists: dict = {}
        seen_tables = []
        for stmt in ast.walk(builder):
            # name = [ ...cols... ]
            if isinstance(stmt, ast.Assign) and isinstance(stmt.value, ast.List):
                for target in stmt.targets:
                    if isinstance(target, ast.Name):
                        lists[target.id] = [
                            col_spec(e) for e in stmt.value.elts
                            if col_spec(e) is not None]
            # name = list(other)
            if isinstance(stmt, ast.Assign) and isinstance(stmt.value, ast.Call) \
                    and getattr(stmt.value.func, "id", "") == "list" \
                    and getattr(stmt.value.args[0], "id", "") in lists:
                for target in stmt.targets:
                    if isinstance(target, ast.Name):
                        lists[target.id] = list(lists[stmt.value.args[0].id])
            # name[i] = rv.col(...)
            if isinstance(stmt, ast.Assign) and isinstance(stmt.targets[0], ast.Subscript):
                target = stmt.targets[0]
                if isinstance(target.value, ast.Name) and target.value.id in lists:
                    index = const(target.slice)
                    spec = col_spec(stmt.value)
                    if spec and isinstance(index, int):
                        lists[target.value.id][index] = spec

        for stmt in ast.walk(builder):
            spec = table_spec(stmt)
            if spec is not None:
                seen_tables.append(spec)

        for spec in seen_tables:
            title = text(spec["title_key"], spec["title_text"])
            cols = resolve_columns(spec["columns_node"], lists)
            headers = [text(c["header_key"], c["header_text"]) for c in cols]
            print(f'   - "{title}"  (id: {spec["id"]}, count badge: yes — rows shown)')
            print(f"       columns: {' | '.join(headers)}")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
