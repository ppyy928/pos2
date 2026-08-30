# pos2

The QML front end for MIZAN POS: a PySide6 + Qt Quick shell over the data layer of the
original Qt Widgets application.

## It needs `pos/` beside it

This tree is **not standalone**. `app/bridge/legacy.py` mounts the older project's
package explicitly:

```python
PACKAGE = Path(__file__).resolve().parents[3] / "pos" / "app"
```

so the two directories must be siblings:

```
POS/
├── pos/     ← the original app: models, migrations, printing, i18n catalogue
└── pos2/    ← this repo
```

Everything stateful — the SQLAlchemy models, the migrations, the receipt and label
renderers, the string catalogue — lives in `pos/` and is shared. `pos2/app/bridge/`
is a set of `QObject` controllers that expose it to QML and format it; it owns no
business rules of its own.

## Running it

```
python run.py
```

`run.py` checks that `vendor/fluentpyside` has been through `tools/scale_fluent.py`
before it starts, and refuses to launch against a pristine or half-scaled copy — the
whole app's geometry comes from that table. The vendored style is committed for that
reason: a fresh clone must have the scaled copy, not the upstream one.

## Layout

| Path | What is in it |
| --- | --- |
| `app/bridge/` | One controller per subject — till, sales, purchases, stock, printing, cash, settings. `root.py` wires them together and is the only file that knows about more than one. |
| `qml/Mizan/` | The component library: tables, cards, the keypad, the product finder, the form group, the payment sheet. Registered in `qml/Mizan/qmldir`. |
| `qml/pages/` | Routed screens, one per navigation destination. |
| `qml/dialogs/` | Workflow dialogs, keyed by `app/bridge/workflows.py` and loaded by `Mizan/DialogHost.qml`. |
| `vendor/fluentpyside/` | The Fluent style, scaled. Patched, not upstream. |
| `tools/` | `qml_check.py` compiles every QML file; `dialog_shots.py` renders every dialog to a PNG; `scale_fluent.py` builds the vendored style. |

## Checking a change

```
python tools/qml_check.py        # every .qml compiles
python tools/dialog_shots.py     # every dialog, as a picture
python -m ruff check app run.py tools
```

`qml_check.py` catches what a running app would only find when an operator opened the
screen: a syntax error, an unknown type, a misspelled property. `dialog_shots.py`
catches what neither can — a heading that repeats the label under it, a list that runs
past the frame, a group with no visual separation.
