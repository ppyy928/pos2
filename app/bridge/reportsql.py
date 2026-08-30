"""SQL for the Reports screen — all six tabs, owned by this front end.

WHY THIS FILE EXISTS INSTEAD OF MORE CALLS INTO pos

pos already has `report_*_detail` in `db_analytics.py`, and the first version of this
screen used them. Three things made that untenable once the screen grew to six tabs:

  1. `report_profit_detail` RAISES for any range with more than 45 selling days.
     `_daily_profit` emits `{key, label, revenue, cost, profit}` and pipes it into
     `_bucket_series`, which does `bucket["value"] += point["value"]` — so the whole
     call dies with `KeyError: 'value'`. The P&L tab is built on that function.

  2. The same function computes `SUM(Sale.total)` on a statement joined to
     `sale_items`, so a day's revenue is multiplied by the number of lines per
     invoice. `_sales_rows_with_cost` avoids this by grouping on `Sale.id` first;
     `_daily_profit` does not.

  3. `report_expenses_detail.by_day` filters on the date only — there is no
     `type == "expense"` clause — so the "expenses per day" series sums sales and
     cash-ins too.

Fixing those means editing `pos/`, which the old QtWidgets app still runs on. So the
queries live here, and pos stays the authority for everything the till and the other
screens already ask it.

WHAT THIS MODULE IS AND IS NOT

It is SQL and arithmetic. It returns raw floats and ints, gap-filled series, and
plain dicts keyed by short identifiers. It does no formatting, no translation and no
presentation: `admin.Reports` attaches labels through the catalogue and money through
`fmt`, exactly as it does for every other payload that crosses to QML.

It reaches the ORM the way `till._thresholds` does — through the module object
`legacy.database()` returns, which carries `SessionFactory`, `select`, `func` and
every model in its namespace. `case` is deliberately not used: `db` does not import
it, so it is not reachable that way.

GROSS, NOT NET OF RETURNS

pos's detail functions subtract returns from revenue and quietly leave the invoice
table gross, so its summary and its rows disagree. Here every figure is gross and
returns are their own KPI and their own series on the Sales tab. A reader who wants
net can subtract two numbers that are both on the screen; a reader looking at a total
that silently had something taken out of it cannot put it back.

THE COST OF GOODS IS TODAY'S COST

`SaleItem` stores `qty`, `price`, `discount` and `total` — and no cost. Every cost and
profit figure here is `SaleItem.qty * Product.purchase_price`, the product's price
*now*. Change a purchase price and the profit on every past sale of that product
changes with it. `PurchaseItem.price` is the only historical cost in the schema and
is not linked to a sale. Recording the cost on the line at the moment of sale is a
schema change to a database the other application also runs on, so it is not made
here; `COST_IS_CURRENT` below exists so the screen can say so out loud.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

#: Read by the Reports controller, printed by the screen. See the module docstring.
COST_IS_CURRENT = True

#: Rows in a ranking chart, and in the tables that back one.
TOP_N = 12

#: Rows in a detail table. Generous — the table is the point of this screen, and the
#: CSV export writes whatever the table holds. Past this a range wants narrowing.
TABLE_MAX = 2000

#: Day counts at which the time axis stops being daily. A 90-day range drawn daily is
#: 90 labels on an axis 900px wide; weekly it is 13.
DAY_LIMIT = 45
WEEK_LIMIT = 400


# =====================================================================
# RANGE AND GRANULARITY
# =====================================================================
def _parse(value: str, fallback: date) -> date:
    try:
        return date.fromisoformat((value or "")[:10])
    except (TypeError, ValueError):
        return fallback


def span_days(since: str, until: str) -> int:
    """Inclusive day count, floored at 1."""
    a = _parse(since, date.today())
    b = _parse(until, date.today())
    return max(1, (b - a).days + 1)


def previous_window(since: str, until: str) -> tuple[str, str]:
    """The window of equal length immediately before this one.

    Immediately before, not "the same dates last month": a 9-day range compared with
    a calendar month is not a comparison. pos's own `_period.previous_window` makes
    the same choice.
    """
    a = _parse(since, date.today())
    b = _parse(until, date.today())
    days = max(1, (b - a).days + 1)
    end = a - timedelta(days=1)
    start = end - timedelta(days=days - 1)
    return start.isoformat(), end.isoformat()


def granularity_for(since: str, until: str) -> str:
    days = span_days(since, until)
    if days <= DAY_LIMIT:
        return "day"
    if days <= WEEK_LIMIT:
        return "week"
    return "month"


def _bucket_of(day: str, granularity: str) -> tuple[str, str]:
    """(sort key, printed label) for one ISO day at one granularity."""
    if granularity == "month":
        return day[:7], day[:7]
    if granularity == "week":
        year, week, _dow = datetime.strptime(day, "%Y-%m-%d").isocalendar()
        key = f"{year}-W{week:02d}"
        return key, f"W{week:02d}"
    return day, day[5:]


def _fill(daily: dict[str, dict[str, float]], since: str, until: str,
          granularity: str, fields: tuple[str, ...]) -> list[dict[str, Any]]:
    """Gap-fill a day-keyed map into an ordered series, then bucket it.

    EVERY DAY IN THE RANGE GETS A POINT, including the ones with nothing in them.

    Not one series in pos's data layer does this — a day with no sales is simply
    absent — which means the x axis of every chart it draws is non-uniform: three
    labels in a row can be Monday, Wednesday, Saturday, and the curve between them
    slopes as though nothing happened in between rather than showing the zero it
    actually was. On a shop that closes on Fridays that is not a detail.
    """
    a = _parse(since, date.today())
    b = _parse(until, date.today())
    if b < a:
        a, b = b, a

    order: list[str] = []
    buckets: dict[str, dict[str, Any]] = {}
    for offset in range((b - a).days + 1):
        day = (a + timedelta(days=offset)).isoformat()
        key, label = _bucket_of(day, granularity)
        bucket = buckets.get(key)
        if bucket is None:
            bucket = {"key": key, "label": label}
            for field in fields:
                bucket[field] = 0.0
            buckets[key] = bucket
            order.append(key)
        row = daily.get(day)
        if row:
            for field in fields:
                bucket[field] += float(row.get(field) or 0.0)

    return [buckets[key] for key in order]


def _series(rows, fields: tuple[str, ...]) -> dict[str, dict[str, float]]:
    """`.mappings()` rows carrying a `key` day into a day-keyed map."""
    out: dict[str, dict[str, float]] = {}
    for row in rows:
        day = str(row["key"])[:10]
        slot = out.setdefault(day, {})
        for field in fields:
            slot[field] = float(row[field] or 0.0)
    return out


def _where(db, column, since: str, until: str):
    """The house range predicate: bare date on the left, end-of-day on the right.

    Every timestamp in this schema is `String(32)` holding `"%Y-%m-%d %H:%M:%S"`, so
    a range filter is a lexicographic string comparison and the upper bound has to
    carry a time or it excludes everything that happened on the last day.
    """
    return (column >= since, column <= until + " 23:59:59")


def _num(value: Any) -> float:
    try:
        return float(value or 0.0)
    except (TypeError, ValueError):
        return 0.0


# =====================================================================
# 1. SALES
# =====================================================================
def sales(db, since: str, until: str) -> dict[str, Any]:
    """Sale + SaleItem. Invoices, what was sold, when, and how it was paid for."""
    grain = granularity_for(since, until)
    psince, puntil = previous_window(since, until)

    with db.SessionFactory() as session:
        def totals(a: str, b: str) -> dict[str, float]:
            row = session.execute(
                db.select(
                    db.func.count(db.Sale.id).label("count"),
                    db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("total"),
                    db.func.coalesce(db.func.sum(db.Sale.paid), 0.0).label("paid"),
                ).where(*_where(db, db.Sale.created_at, a, b))
            ).mappings().first()
            count = int(row["count"] or 0)
            total = _num(row["total"])
            paid = _num(row["paid"])
            return {
                "count": count,
                "total": total,
                "paid": paid,
                "outstanding": total - paid,
                "avg_basket": total / count if count else 0.0,
            }

        kpi = totals(since, until)
        prev = totals(psince, puntil)

        # Line-level figures, joined through sales so the range still applies. A
        # separate query from the invoice totals above: joining sale_items to sales
        # and summing Sale.total in one statement multiplies revenue by the line
        # count, which is the bug this module exists to avoid.
        line = session.execute(
            db.select(
                db.func.coalesce(db.func.sum(db.SaleItem.qty), 0.0).label("qty"),
                db.func.coalesce(db.func.sum(db.SaleItem.discount), 0.0).label("discount"),
            )
            .join(db.Sale, db.SaleItem.sale_id == db.Sale.id)
            .where(*_where(db, db.Sale.created_at, since, until))
        ).mappings().first()
        kpi["items"] = _num(line["qty"])
        kpi["discount"] = _num(line["discount"])

        returns = session.execute(
            db.select(
                db.func.count(db.Return.id).label("count"),
                db.func.coalesce(db.func.sum(db.Return.total), 0.0).label("total"),
            ).where(*_where(db, db.Return.created_at, since, until))
        ).mappings().first()
        kpi["returns"] = _num(returns["total"])
        kpi["returns_count"] = int(returns["count"] or 0)

        def daily(a: str, b: str) -> dict[str, dict[str, float]]:
            return _series(
                session.execute(
                    db.select(
                        db.func.substr(db.Sale.created_at, 1, 10).label("key"),
                        db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("value"),
                    )
                    .where(*_where(db, db.Sale.created_at, a, b))
                    .group_by("key")
                ).mappings().all(),
                ("value",),
            )

        trend = _fill(daily(since, until), since, until, grain, ("value",))
        # Bucketed at the CURRENT window's granularity and aligned by index, so
        # point 3 of the reference sits under point 3 of the subject. The labels come
        # from the current window; the previous one's dates are not printed, because
        # two date axes on one chart is two charts.
        prev_trend = _fill(daily(psince, puntil), psince, puntil, grain, ("value",))
        for i, point in enumerate(prev_trend):
            point["label"] = trend[i]["label"] if i < len(trend) else point["label"]

        by_hour_rows = session.execute(
            db.select(
                db.func.substr(db.Sale.created_at, 12, 2).label("key"),
                db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("value"),
                db.func.count(db.Sale.id).label("count"),
            )
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by("key")
        ).mappings().all()
        hours = {str(r["key"]): r for r in by_hour_rows}
        # All 24, always. A shop's quiet hours are the finding, and an axis that
        # skips them cannot show one.
        by_hour = [
            {
                "key": f"{h:02d}",
                "label": f"{h:02d}",
                "value": _num(hours[f"{h:02d}"]["value"]) if f"{h:02d}" in hours else 0.0,
                "count": int(hours[f"{h:02d}"]["count"]) if f"{h:02d}" in hours else 0,
            }
            for h in range(24)
        ]

        # SQLite's %w: 0 = Sunday. Kept in that order rather than rotated to Monday,
        # because the week starts on Sunday where this product is sold.
        dow_rows = session.execute(
            db.select(
                db.func.strftime("%w", db.Sale.created_at).label("key"),
                db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("value"),
                db.func.count(db.Sale.id).label("count"),
            )
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by("key")
        ).mappings().all()
        dows = {str(r["key"]): r for r in dow_rows}
        by_dow = [
            {
                "key": str(d),
                "value": _num(dows[str(d)]["value"]) if str(d) in dows else 0.0,
                "count": int(dows[str(d)]["count"]) if str(d) in dows else 0,
            }
            for d in range(7)
        ]

        mix_rows = session.execute(
            db.select(
                db.Sale.payment_type.label("key"),
                db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("value"),
                db.func.count(db.Sale.id).label("count"),
            )
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by(db.Sale.payment_type)
        ).mappings().all()
        payment_mix = [
            {"key": str(r["key"] or ""), "value": _num(r["value"]),
             "count": int(r["count"] or 0)}
            for r in mix_rows if _num(r["value"]) > 0
        ]
        payment_mix.sort(key=lambda p: p["value"], reverse=True)

        cat_rows = session.execute(
            db.select(
                db.func.coalesce(db.Category.name, "").label("label"),
                db.func.coalesce(db.func.sum(db.SaleItem.total), 0.0).label("value"),
                db.func.coalesce(db.func.sum(db.SaleItem.qty), 0.0).label("qty"),
            )
            .join(db.Sale, db.SaleItem.sale_id == db.Sale.id)
            .outerjoin(db.Product, db.SaleItem.product_id == db.Product.id)
            .outerjoin(db.Category, db.Product.category_id == db.Category.id)
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by(db.Category.id)
            .order_by(db.func.sum(db.SaleItem.total).desc())
        ).mappings().all()
        by_category = [
            {"label": str(r["label"] or ""), "value": _num(r["value"]),
             "qty": _num(r["qty"])}
            for r in cat_rows
        ]

        prod_rows = session.execute(
            db.select(
                db.SaleItem.product_id.label("id"),
                db.func.min(db.SaleItem.name).label("label"),
                db.func.coalesce(db.func.sum(db.SaleItem.total), 0.0).label("value"),
                db.func.coalesce(db.func.sum(db.SaleItem.qty), 0.0).label("qty"),
            )
            .join(db.Sale, db.SaleItem.sale_id == db.Sale.id)
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by(db.SaleItem.product_id)
        ).mappings().all()
        products = [
            {"label": str(r["label"] or ""), "value": _num(r["value"]),
             "qty": _num(r["qty"])}
            for r in prod_rows
        ]
        top_value = sorted(products, key=lambda p: p["value"], reverse=True)[:TOP_N]
        top_qty = sorted(products, key=lambda p: p["qty"], reverse=True)[:TOP_N]

        invoice_rows = session.execute(
            db.select(
                db.Sale.number,
                db.Sale.created_at,
                db.Sale.payment_type,
                db.Sale.total,
                db.Sale.paid,
                db.func.coalesce(db.Customer.name, "").label("customer"),
            )
            .outerjoin(db.Customer, db.Sale.customer_id == db.Customer.id)
            .where(*_where(db, db.Sale.created_at, since, until))
            .order_by(db.Sale.id.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        invoices = [
            {
                "number": str(r["number"] or ""),
                "created_at": str(r["created_at"] or ""),
                "customer": str(r["customer"] or ""),
                "payment_type": str(r["payment_type"] or ""),
                "total": _num(r["total"]),
                "paid": _num(r["paid"]),
                # The one field the schema does not store and every reader wants.
                "remaining": _num(r["total"]) - _num(r["paid"]),
            }
            for r in invoice_rows
        ]

        ret_rows = session.execute(
            db.select(
                db.Return.number,
                db.Return.created_at,
                db.Return.reason,
                db.Return.total,
                db.func.coalesce(db.Sale.number, "").label("sale_number"),
            )
            .outerjoin(db.Sale, db.Return.sale_id == db.Sale.id)
            .where(*_where(db, db.Return.created_at, since, until))
            .order_by(db.Return.id.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        return_rows = [
            {
                "number": str(r["number"] or ""),
                "created_at": str(r["created_at"] or ""),
                "sale_number": str(r["sale_number"] or ""),
                "reason": str(r["reason"] or ""),
                "total": _num(r["total"]),
            }
            for r in ret_rows
        ]

        # created_by is free text — there is no FK from a sale to an employee — so
        # this groups by whatever name was recorded, and rows written before the
        # column existed group under "".
        staff_rows = session.execute(
            db.select(
                db.func.coalesce(db.Sale.created_by, "").label("label"),
                db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("value"),
                db.func.count(db.Sale.id).label("count"),
            )
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by(db.Sale.created_by)
            .order_by(db.func.sum(db.Sale.total).desc())
            .limit(TOP_N)
        ).mappings().all()
        by_staff = [
            {"label": str(r["label"] or ""), "value": _num(r["value"]),
             "count": int(r["count"] or 0)}
            for r in staff_rows
        ]

    return {
        "kpi": kpi,
        "prev": prev,
        "granularity": grain,
        "previous_range": (psince, puntil),
        "trend": trend,
        "prev_trend": prev_trend,
        "by_hour": by_hour,
        "by_dow": by_dow,
        "payment_mix": payment_mix,
        "by_category": by_category,
        "top_value": top_value,
        "top_qty": top_qty,
        "by_staff": by_staff,
        "invoices": invoices,
        "returns": return_rows,
    }


# =====================================================================
# 2. INVENTORY AND PRODUCTS
# =====================================================================
def inventory(db, since: str, until: str) -> dict[str, Any]:
    """Product + Category. A stock count is about now; the range only decides what
    counts as stagnant."""
    with db.SessionFactory() as session:
        product_rows = session.execute(
            db.select(
                db.Product.id,
                db.Product.name,
                db.Product.barcode,
                db.Product.stock,
                db.Product.low_stock_threshold,
                db.Product.purchase_price,
                db.Product.sale_price,
                db.func.coalesce(db.Category.name, "").label("category"),
            )
            .outerjoin(db.Category, db.Product.category_id == db.Category.id)
            .order_by(db.Product.name)
            .limit(TABLE_MAX)
        ).mappings().all()

        stock_rows = []
        low_rows = []
        margin_rows = []
        for r in product_rows:
            stock = _num(r["stock"])
            cost = _num(r["purchase_price"])
            price = _num(r["sale_price"])
            threshold = _num(r["low_stock_threshold"])
            row = {
                "name": str(r["name"] or ""),
                "barcode": str(r["barcode"] or ""),
                "category": str(r["category"] or ""),
                "stock": stock,
                "purchase_price": cost,
                "sale_price": price,
                "value": stock * cost,
                "threshold": threshold,
                # Catalogue margin, not realised margin: what this product WOULD earn
                # at today's prices. `sales.top_value` is what it did earn.
                "margin": price - cost,
                "margin_pct": ((price - cost) / price * 100.0) if price else 0.0,
            }
            stock_rows.append(row)
            if stock <= threshold:
                low_rows.append(row)
            if price > 0:
                margin_rows.append(row)

        totals = session.execute(
            db.select(
                db.func.count(db.Product.id).label("count"),
                db.func.coalesce(
                    db.func.sum(db.Product.stock * db.Product.purchase_price), 0.0
                ).label("value_cost"),
                db.func.coalesce(
                    db.func.sum(db.Product.stock * db.Product.sale_price), 0.0
                ).label("value_retail"),
            )
        ).mappings().first()

        by_cat_rows = session.execute(
            db.select(
                db.func.coalesce(db.Category.name, "").label("label"),
                db.func.coalesce(
                    db.func.sum(db.Product.stock * db.Product.purchase_price), 0.0
                ).label("value"),
                db.func.count(db.Product.id).label("count"),
            )
            .outerjoin(db.Category, db.Product.category_id == db.Category.id)
            .group_by(db.Category.id)
            .order_by(
                db.func.sum(db.Product.stock * db.Product.purchase_price).desc()
            )
        ).mappings().all()
        # Stock VALUE by category, which is what a stock report is asked for. pos's
        # `report_inventory_detail.by_category` is sales revenue by category — a
        # different question wearing the same name.
        stock_by_category = [
            {"label": str(r["label"] or ""), "value": _num(r["value"]),
             "count": int(r["count"] or 0)}
            for r in by_cat_rows if _num(r["value"]) > 0
        ]

        # Two queries rather than a correlated subquery: the set of product ids that
        # moved in the range, then everything else. `sale_items.product_id` carries no
        # index, so one scan is worth more than a per-product lookup.
        sold = {
            row[0]
            for row in session.execute(
                db.select(db.SaleItem.product_id)
                .join(db.Sale, db.SaleItem.sale_id == db.Sale.id)
                .where(*_where(db, db.Sale.created_at, since, until))
                .group_by(db.SaleItem.product_id)
            ).all()
            if row[0] is not None
        }
        stagnant = [
            row for row, r in zip(stock_rows, product_rows, strict=False)
            if r["id"] not in sold and _num(r["stock"]) > 0
        ]

        low_rows.sort(key=lambda row: row["stock"])
        margin_rows.sort(key=lambda row: row["margin_pct"])
        stagnant.sort(key=lambda row: row["value"], reverse=True)

    return {
        "kpi": {
            "count": int(totals["count"] or 0),
            "value_cost": _num(totals["value_cost"]),
            "value_retail": _num(totals["value_retail"]),
            "low_stock": float(len(low_rows)),
            "stagnant": float(len(stagnant)),
        },
        "stock_by_category": stock_by_category,
        "stock_rows": stock_rows,
        "low_rows": low_rows,
        "stagnant_rows": stagnant[:TABLE_MAX],
        "margin_rows": margin_rows,
    }


# =====================================================================
# 3. PURCHASES AND SUPPLIERS
# =====================================================================
def purchases(db, since: str, until: str) -> dict[str, Any]:
    """PurchaseInvoice + PurchaseItem + Supplier + SupplierPayment."""
    grain = granularity_for(since, until)
    psince, puntil = previous_window(since, until)

    with db.SessionFactory() as session:
        def totals(a: str, b: str) -> dict[str, float]:
            row = session.execute(
                db.select(
                    db.func.count(db.PurchaseInvoice.id).label("count"),
                    db.func.coalesce(
                        db.func.sum(db.PurchaseInvoice.total), 0.0).label("total"),
                    db.func.coalesce(
                        db.func.sum(db.PurchaseInvoice.paid), 0.0).label("paid"),
                ).where(*_where(db, db.PurchaseInvoice.created_at, a, b))
            ).mappings().first()
            count = int(row["count"] or 0)
            total = _num(row["total"])
            paid = _num(row["paid"])
            return {
                "count": count,
                "total": total,
                "paid": paid,
                "outstanding": total - paid,
                "avg_invoice": total / count if count else 0.0,
            }

        kpi = totals(since, until)
        prev = totals(psince, puntil)

        paid_out = session.execute(
            db.select(
                db.func.coalesce(db.func.sum(db.SupplierPayment.amount), 0.0)
            ).where(*_where(db, db.SupplierPayment.created_at, since, until))
        ).scalar()
        kpi["settled"] = _num(paid_out)

        def daily(a: str, b: str) -> dict[str, dict[str, float]]:
            return _series(
                session.execute(
                    db.select(
                        db.func.substr(db.PurchaseInvoice.created_at, 1, 10).label("key"),
                        db.func.coalesce(
                            db.func.sum(db.PurchaseInvoice.total), 0.0).label("value"),
                    )
                    .where(*_where(db, db.PurchaseInvoice.created_at, a, b))
                    .group_by("key")
                ).mappings().all(),
                ("value",),
            )

        trend = _fill(daily(since, until), since, until, grain, ("value",))
        prev_trend = _fill(daily(psince, puntil), psince, puntil, grain, ("value",))
        for i, point in enumerate(prev_trend):
            point["label"] = trend[i]["label"] if i < len(trend) else point["label"]

        sup_rows = session.execute(
            db.select(
                db.func.coalesce(db.Supplier.name, "").label("label"),
                db.func.coalesce(
                    db.func.sum(db.PurchaseInvoice.total), 0.0).label("value"),
                db.func.coalesce(
                    db.func.sum(db.PurchaseInvoice.paid), 0.0).label("paid"),
                db.func.count(db.PurchaseInvoice.id).label("count"),
            )
            .outerjoin(db.Supplier, db.PurchaseInvoice.supplier_id == db.Supplier.id)
            .where(*_where(db, db.PurchaseInvoice.created_at, since, until))
            .group_by(db.Supplier.id)
            .order_by(db.func.sum(db.PurchaseInvoice.total).desc())
        ).mappings().all()
        by_supplier = [
            {
                "label": str(r["label"] or ""),
                "value": _num(r["value"]),
                "paid": _num(r["paid"]),
                "outstanding": _num(r["value"]) - _num(r["paid"]),
                "count": int(r["count"] or 0),
            }
            for r in sup_rows
        ]

        debt_rows = session.execute(
            db.select(db.Supplier.name, db.Supplier.phone, db.Supplier.debt)
            .where(db.Supplier.debt > 0)
            .order_by(db.Supplier.debt.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        debts = [
            {"name": str(r["name"] or ""), "phone": str(r["phone"] or ""),
             "debt": _num(r["debt"])}
            for r in debt_rows
        ]

        # Range-scoped payment rows, which pos has no query for: its
        # `fetch_supplier_payments` ignores dates entirely.
        pay_rows = session.execute(
            db.select(
                db.SupplierPayment.created_at,
                db.SupplierPayment.amount,
                db.func.coalesce(db.Supplier.name, "").label("supplier"),
            )
            .outerjoin(db.Supplier, db.SupplierPayment.supplier_id == db.Supplier.id)
            .where(*_where(db, db.SupplierPayment.created_at, since, until))
            .order_by(db.SupplierPayment.id.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        payments = [
            {"created_at": str(r["created_at"] or ""),
             "supplier": str(r["supplier"] or ""), "amount": _num(r["amount"])}
            for r in pay_rows
        ]

        invoice_rows = session.execute(
            db.select(
                db.PurchaseInvoice.number,
                db.PurchaseInvoice.created_at,
                db.PurchaseInvoice.total,
                db.PurchaseInvoice.paid,
                db.func.coalesce(db.Supplier.name, "").label("supplier"),
            )
            .outerjoin(db.Supplier, db.PurchaseInvoice.supplier_id == db.Supplier.id)
            .where(*_where(db, db.PurchaseInvoice.created_at, since, until))
            .order_by(db.PurchaseInvoice.id.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        invoices = [
            {
                "number": str(r["number"] or ""),
                "created_at": str(r["created_at"] or ""),
                "supplier": str(r["supplier"] or ""),
                "total": _num(r["total"]),
                "paid": _num(r["paid"]),
                "remaining": _num(r["total"]) - _num(r["paid"]),
            }
            for r in invoice_rows
        ]

    return {
        "kpi": kpi,
        "prev": prev,
        "granularity": grain,
        "previous_range": (psince, puntil),
        "trend": trend,
        "prev_trend": prev_trend,
        "by_supplier": by_supplier,
        "debts": debts,
        "payments": payments,
        "invoices": invoices,
    }


# =====================================================================
# 4. CUSTOMERS
# =====================================================================
def customers(db, since: str, until: str) -> dict[str, Any]:
    """Customer + CustomerPayment + the sales side of the debt."""
    grain = granularity_for(since, until)
    psince, puntil = previous_window(since, until)

    with db.SessionFactory() as session:
        debt_total = _num(
            session.execute(
                db.select(db.func.coalesce(db.func.sum(db.Customer.debt), 0.0))
                .where(db.Customer.debt > 0)
            ).scalar()
        )
        debtors_count = int(
            session.execute(
                db.select(db.func.count(db.Customer.id))
                .where(db.Customer.debt > 0)
            ).scalar() or 0
        )

        def collected(a: str, b: str) -> float:
            return _num(
                session.execute(
                    db.select(db.func.coalesce(db.func.sum(db.CustomerPayment.amount), 0.0))
                    .where(*_where(db, db.CustomerPayment.created_at, a, b))
                ).scalar()
            )

        def issued(a: str, b: str) -> float:
            """Debt created in the window: what was billed and not paid on credit
            invoices."""
            row = session.execute(
                db.select(
                    db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("total"),
                    db.func.coalesce(db.func.sum(db.Sale.paid), 0.0).label("paid"),
                )
                .where(*_where(db, db.Sale.created_at, a, b))
                .where(db.Sale.payment_type != "cash")
            ).mappings().first()
            return _num(row["total"]) - _num(row["paid"])

        kpi = {
            "debt": debt_total,
            "debtors": float(debtors_count),
            "collected": collected(since, until),
            "issued": issued(since, until),
        }
        prev = {
            "debt": debt_total,
            "debtors": float(debtors_count),
            "collected": collected(psince, puntil),
            "issued": issued(psince, puntil),
        }

        def daily(a: str, b: str) -> dict[str, dict[str, float]]:
            out: dict[str, dict[str, float]] = {}
            for row in session.execute(
                db.select(
                    db.func.substr(db.CustomerPayment.created_at, 1, 10).label("key"),
                    db.func.coalesce(
                        db.func.sum(db.CustomerPayment.amount), 0.0).label("collected"),
                )
                .where(*_where(db, db.CustomerPayment.created_at, a, b))
                .group_by("key")
            ).mappings().all():
                out.setdefault(str(row["key"])[:10], {})["collected"] = _num(row["collected"])
            for row in session.execute(
                db.select(
                    db.func.substr(db.Sale.created_at, 1, 10).label("key"),
                    db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("total"),
                    db.func.coalesce(db.func.sum(db.Sale.paid), 0.0).label("paid"),
                )
                .where(*_where(db, db.Sale.created_at, a, b))
                .where(db.Sale.payment_type != "cash")
                .group_by("key")
            ).mappings().all():
                slot = out.setdefault(str(row["key"])[:10], {})
                slot["issued"] = _num(row["total"]) - _num(row["paid"])
            return out

        trend = _fill(daily(since, until), since, until, grain, ("issued", "collected"))

        top_rows = session.execute(
            db.select(
                db.func.coalesce(db.Customer.name, "").label("label"),
                db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("value"),
                db.func.count(db.Sale.id).label("count"),
            )
            .join(db.Customer, db.Sale.customer_id == db.Customer.id)
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by(db.Customer.id)
            .order_by(db.func.sum(db.Sale.total).desc())
            .limit(TOP_N)
        ).mappings().all()
        # An inner join on purpose: a walk-in sale has no customer_id, and "who buys
        # the most" is a question about named customers.
        top_customers = [
            {"label": str(r["label"] or ""), "value": _num(r["value"]),
             "count": int(r["count"] or 0)}
            for r in top_rows
        ]

        debtor_rows = session.execute(
            db.select(db.Customer.id, db.Customer.name, db.Customer.phone,
                      db.Customer.debt)
            .where(db.Customer.debt > 0)
            .order_by(db.Customer.debt.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        last_pay = {
            row[0]: str(row[1] or "")[:10]
            for row in session.execute(
                db.select(db.CustomerPayment.customer_id,
                          db.func.max(db.CustomerPayment.created_at))
                .group_by(db.CustomerPayment.customer_id)
            ).all()
        }
        debtors = [
            {
                "name": str(r["name"] or ""),
                "phone": str(r["phone"] or ""),
                "debt": _num(r["debt"]),
                "last_payment": last_pay.get(r["id"], ""),
            }
            for r in debtor_rows
        ]

        pay_rows = session.execute(
            db.select(
                db.CustomerPayment.created_at,
                db.CustomerPayment.amount,
                db.func.coalesce(db.Customer.name, "").label("customer"),
            )
            .outerjoin(db.Customer, db.CustomerPayment.customer_id == db.Customer.id)
            .where(*_where(db, db.CustomerPayment.created_at, since, until))
            .order_by(db.CustomerPayment.id.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        payments = [
            {"created_at": str(r["created_at"] or ""),
             "customer": str(r["customer"] or ""), "amount": _num(r["amount"])}
            for r in pay_rows
        ]

    return {
        "kpi": kpi,
        "prev": prev,
        "granularity": grain,
        "previous_range": (psince, puntil),
        "trend": trend,
        "top_customers": top_customers,
        "debtors": debtors,
        "payments": payments,
    }


# =====================================================================
# 5. CASH AND TREASURY
# =====================================================================
def cash(db, since: str, until: str) -> dict[str, Any]:
    """CashSession + CashMovement. `type` is one of sale | cash_in | expense |
    cash_out — the four `add_cash_movement` and `finalize_sale` between them write."""
    grain = granularity_for(since, until)
    IN = ("sale", "cash_in")

    with db.SessionFactory() as session:
        type_rows = session.execute(
            db.select(
                db.CashMovement.type.label("key"),
                db.func.coalesce(db.func.sum(db.CashMovement.amount), 0.0).label("value"),
                db.func.count(db.CashMovement.id).label("count"),
            )
            .where(*_where(db, db.CashMovement.created_at, since, until))
            .group_by(db.CashMovement.type)
        ).mappings().all()
        # A GROUP BY over a date range, which pos has only per session
        # (`_session_totals`) — its ranged version derives the split in Python by
        # walking every movement row.
        by_type = [
            {"key": str(r["key"] or ""), "value": _num(r["value"]),
             "count": int(r["count"] or 0)}
            for r in type_rows if _num(r["value"]) > 0
        ]
        by_type.sort(key=lambda p: p["value"], reverse=True)

        totals = {row["key"]: _num(row["value"]) for row in type_rows}
        cash_in = sum(v for k, v in totals.items() if k in IN)
        cash_out = sum(v for k, v in totals.items() if k not in IN)
        kpi = {
            "net": cash_in - cash_out,
            "cash_in": cash_in,
            "cash_out": cash_out,
            "expenses": totals.get("expense", 0.0),
            "movements": float(sum(int(r["count"] or 0) for r in type_rows)),
        }

        flow_rows = session.execute(
            db.select(
                db.func.substr(db.CashMovement.created_at, 1, 10).label("key"),
                db.CashMovement.type.label("type"),
                db.func.coalesce(db.func.sum(db.CashMovement.amount), 0.0).label("value"),
            )
            .where(*_where(db, db.CashMovement.created_at, since, until))
            .group_by("key", db.CashMovement.type)
        ).mappings().all()
        daily: dict[str, dict[str, float]] = {}
        for r in flow_rows:
            slot = daily.setdefault(str(r["key"])[:10], {"in": 0.0, "out": 0.0})
            if str(r["type"]) in IN:
                slot["in"] += _num(r["value"])
            else:
                slot["out"] += _num(r["value"])
        trend = _fill(daily, since, until, grain, ("in", "out"))
        for point in trend:
            point["net"] = point["in"] - point["out"]

        reason_rows = session.execute(
            db.select(
                db.func.coalesce(db.CashMovement.reason, "").label("label"),
                db.func.coalesce(db.func.sum(db.CashMovement.amount), 0.0).label("value"),
                db.func.count(db.CashMovement.id).label("count"),
            )
            .where(*_where(db, db.CashMovement.created_at, since, until))
            .where(db.CashMovement.type == "expense")
            .group_by(db.CashMovement.reason)
            .order_by(db.func.sum(db.CashMovement.amount).desc())
            .limit(TOP_N)
        ).mappings().all()
        by_reason = [
            {"label": str(r["label"] or ""), "value": _num(r["value"]),
             "count": int(r["count"] or 0)}
            for r in reason_rows if _num(r["value"]) > 0
        ]

        # Sessions in the range, then one roll-up query for all of their movements.
        # `expected` and the variance are not stored anywhere — pos recomputes both
        # at read time in three separate places — so they are computed here once.
        session_rows = session.execute(
            db.select(
                db.CashSession.id,
                db.CashSession.opened_at,
                db.CashSession.closed_at,
                db.CashSession.opening_balance,
                db.CashSession.actual_cash,
                db.CashSession.status,
            )
            .where(*_where(db, db.CashSession.opened_at, since, until))
            .order_by(db.CashSession.id.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        ids = [r["id"] for r in session_rows]
        splits: dict[int, dict[str, float]] = {}
        if ids:
            for r in session.execute(
                db.select(
                    db.CashMovement.session_id.label("sid"),
                    db.CashMovement.type.label("type"),
                    db.func.coalesce(db.func.sum(db.CashMovement.amount), 0.0).label("value"),
                )
                .where(db.CashMovement.session_id.in_(ids))
                .group_by(db.CashMovement.session_id, db.CashMovement.type)
            ).mappings().all():
                slot = splits.setdefault(int(r["sid"]), {"in": 0.0, "out": 0.0})
                if str(r["type"]) in IN:
                    slot["in"] += _num(r["value"])
                else:
                    slot["out"] += _num(r["value"])

        sessions = []
        for r in session_rows:
            split = splits.get(int(r["id"]), {"in": 0.0, "out": 0.0})
            opening = _num(r["opening_balance"])
            expected = opening + split["in"] - split["out"]
            closed = r["actual_cash"] is not None
            actual = _num(r["actual_cash"]) if closed else 0.0
            sessions.append({
                "opened_at": str(r["opened_at"] or ""),
                "closed_at": str(r["closed_at"] or ""),
                "status": str(r["status"] or ""),
                "opening": opening,
                "cash_in": split["in"],
                "cash_out": split["out"],
                "expected": expected,
                "actual": actual,
                # Nothing, not zero, while the drawer is still open: a session with
                # no count yet has no variance, and 0.00 would read as "balanced".
                "difference": (actual - expected) if closed else None,
            })

        movement_rows = session.execute(
            db.select(
                db.CashMovement.created_at,
                db.CashMovement.type,
                db.CashMovement.amount,
                db.func.coalesce(db.CashMovement.reason, "").label("reason"),
                db.func.coalesce(db.Sale.number, "").label("sale_number"),
            )
            .outerjoin(db.Sale, db.CashMovement.sale_id == db.Sale.id)
            .where(*_where(db, db.CashMovement.created_at, since, until))
            .order_by(db.CashMovement.id.desc())
            .limit(TABLE_MAX)
        ).mappings().all()
        movements = [
            {
                "created_at": str(r["created_at"] or ""),
                "type": str(r["type"] or ""),
                "amount": _num(r["amount"]),
                # pos's own display rule: the reason, or the sale it came from.
                "reason": str(r["reason"] or "") or str(r["sale_number"] or ""),
            }
            for r in movement_rows
        ]

    return {
        "kpi": kpi,
        "prev": {},
        "granularity": grain,
        "trend": trend,
        "by_type": by_type,
        "by_reason": by_reason,
        "sessions": sessions,
        "movements": movements,
    }


# =====================================================================
# 6. PROFIT AND LOSS
# =====================================================================
def pnl(db, since: str, until: str) -> dict[str, Any]:
    """Revenue, cost of goods, and what expenses leave of the difference.

    REVENUE AND COST ARE TWO QUERIES, NEVER ONE

    `SUM(Sale.total)` on a statement joined to `sale_items` counts each invoice once
    per line. pos's `_daily_profit` does exactly that, so its revenue is inflated by
    the average basket size. Here the invoice totals and the line costs are summed
    separately and merged by day.
    """
    grain = granularity_for(since, until)
    psince, puntil = previous_window(since, until)

    with db.SessionFactory() as session:
        def revenue(a: str, b: str) -> float:
            return _num(session.execute(
                db.select(db.func.coalesce(db.func.sum(db.Sale.total), 0.0))
                .where(*_where(db, db.Sale.created_at, a, b))
            ).scalar())

        def cost(a: str, b: str) -> float:
            return _num(session.execute(
                db.select(db.func.coalesce(
                    db.func.sum(db.SaleItem.qty * db.Product.purchase_price), 0.0))
                .join(db.Sale, db.SaleItem.sale_id == db.Sale.id)
                .join(db.Product, db.SaleItem.product_id == db.Product.id)
                .where(*_where(db, db.Sale.created_at, a, b))
            ).scalar())

        def expenses(a: str, b: str) -> float:
            return _num(session.execute(
                db.select(db.func.coalesce(db.func.sum(db.CashMovement.amount), 0.0))
                .where(*_where(db, db.CashMovement.created_at, a, b))
                .where(db.CashMovement.type == "expense")
            ).scalar())

        def block(a: str, b: str) -> dict[str, float]:
            rev = revenue(a, b)
            cog = cost(a, b)
            exp = expenses(a, b)
            return {
                "revenue": rev,
                "cost": cog,
                "gross": rev - cog,
                "expenses": exp,
                "net": rev - cog - exp,
                "margin": ((rev - cog) / rev * 100.0) if rev else 0.0,
            }

        kpi = block(since, until)
        prev = block(psince, puntil)

        rev_rows = session.execute(
            db.select(
                db.func.substr(db.Sale.created_at, 1, 10).label("key"),
                db.func.coalesce(db.func.sum(db.Sale.total), 0.0).label("revenue"),
            )
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by("key")
        ).mappings().all()
        cost_rows = session.execute(
            db.select(
                db.func.substr(db.Sale.created_at, 1, 10).label("key"),
                db.func.coalesce(
                    db.func.sum(db.SaleItem.qty * db.Product.purchase_price), 0.0
                ).label("cost"),
            )
            .join(db.SaleItem, db.SaleItem.sale_id == db.Sale.id)
            .join(db.Product, db.SaleItem.product_id == db.Product.id)
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by("key")
        ).mappings().all()
        exp_rows = session.execute(
            db.select(
                db.func.substr(db.CashMovement.created_at, 1, 10).label("key"),
                db.func.coalesce(
                    db.func.sum(db.CashMovement.amount), 0.0).label("expenses"),
            )
            .where(*_where(db, db.CashMovement.created_at, since, until))
            .where(db.CashMovement.type == "expense")
            .group_by("key")
        ).mappings().all()

        daily: dict[str, dict[str, float]] = {}
        for r in rev_rows:
            daily.setdefault(str(r["key"])[:10], {})["revenue"] = _num(r["revenue"])
        for r in cost_rows:
            daily.setdefault(str(r["key"])[:10], {})["cost"] = _num(r["cost"])
        for r in exp_rows:
            daily.setdefault(str(r["key"])[:10], {})["expenses"] = _num(r["expenses"])

        trend = _fill(daily, since, until, grain, ("revenue", "cost", "expenses"))
        for point in trend:
            point["gross"] = point["revenue"] - point["cost"]
            point["net"] = point["gross"] - point["expenses"]

        cat_rows = session.execute(
            db.select(
                db.func.coalesce(db.Category.name, "").label("label"),
                db.func.coalesce(db.func.sum(db.SaleItem.total), 0.0).label("revenue"),
                db.func.coalesce(
                    db.func.sum(db.SaleItem.qty * db.Product.purchase_price), 0.0
                ).label("cost"),
                db.func.coalesce(db.func.sum(db.SaleItem.qty), 0.0).label("qty"),
            )
            .join(db.Sale, db.SaleItem.sale_id == db.Sale.id)
            .join(db.Product, db.SaleItem.product_id == db.Product.id)
            .outerjoin(db.Category, db.Product.category_id == db.Category.id)
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by(db.Category.id)
        ).mappings().all()
        by_category = []
        for r in cat_rows:
            rev = _num(r["revenue"])
            cog = _num(r["cost"])
            by_category.append({
                "name": str(r["label"] or ""),
                "revenue": rev,
                "cost": cog,
                "profit": rev - cog,
                "qty": _num(r["qty"]),
                "margin": ((rev - cog) / rev * 100.0) if rev else 0.0,
            })
        by_category.sort(key=lambda row: row["profit"], reverse=True)

        prod_rows = session.execute(
            db.select(
                db.func.min(db.SaleItem.name).label("label"),
                db.func.coalesce(db.func.sum(db.SaleItem.total), 0.0).label("revenue"),
                db.func.coalesce(
                    db.func.sum(db.SaleItem.qty * db.Product.purchase_price), 0.0
                ).label("cost"),
                db.func.coalesce(db.func.sum(db.SaleItem.qty), 0.0).label("qty"),
            )
            .join(db.Sale, db.SaleItem.sale_id == db.Sale.id)
            .join(db.Product, db.SaleItem.product_id == db.Product.id)
            .where(*_where(db, db.Sale.created_at, since, until))
            .group_by(db.SaleItem.product_id)
        ).mappings().all()
        by_product = []
        for r in prod_rows:
            rev = _num(r["revenue"])
            cog = _num(r["cost"])
            by_product.append({
                "name": str(r["label"] or ""),
                "revenue": rev,
                "cost": cog,
                "profit": rev - cog,
                "qty": _num(r["qty"]),
                "margin": ((rev - cog) / rev * 100.0) if rev else 0.0,
            })
        by_product.sort(key=lambda row: row["profit"], reverse=True)

    return {
        "kpi": kpi,
        "prev": prev,
        "granularity": grain,
        "previous_range": (psince, puntil),
        "trend": trend,
        "by_category": by_category[:TABLE_MAX],
        "by_product": by_product[:TABLE_MAX],
        "top_profit": by_product[:TOP_N],
    }


#: Tab id -> the function that answers it. The controller iterates this and nothing
#: else, so adding a tab is one entry plus one spec in admin.TABS.
QUERIES = {
    "sales": sales,
    "inventory": inventory,
    "purchases": purchases,
    "customers": customers,
    "cash": cash,
    "pnl": pnl,
}
