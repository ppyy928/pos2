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

## Diagnostics

`app/diagnostics.py` installs logging before anything else in `run.py` starts, so
every later failure — including a refused launch — leaves a record. On a windowed
exe there is no stderr; these files are the only witness.

Written to `logs/` (beside the project in development, beside the executable in a
frozen build, with `%LOCALAPPDATA%/MIZAN/logs` and the temp directory as fallbacks
when that spot is not writable):

| File | What it holds |
| --- | --- |
| `app.log` | INFO and up: the startup banner, the business audit trail (logins, sales, cash sessions, backups). |
| `debug.log` | Everything, including Qt warnings and every soft fallback. First stop when reproducing a bug. |
| `errors.log` | ERROR/CRITICAL only, with full tracebacks. |
| `crash.log` | `faulthandler` dumps of native crashes — segfaults inside Qt's C++ that Python hooks cannot see. |

Coverage, without touching a hundred `except` sites: the controllers' `rejected`
signals are tapped once in `root.py` (a direct connection still runs inside the
emitting `except` block, so the traceback is recovered), `_set_error` logs before
its dedup check, the three pool-thread runnables log their failures, and
`sys.excepthook` / `threading.excepthook` / `qInstallMessageHandler` catch
everything else — QML's `console.*` included.

### The action trace

`app/instrument.py` is the other half: what the operator *did*, not only what
broke. `App.__init__` calls `install()`, which walks the bridge and — without any
edit to `app/bridge/` — wraps every `@Slot` and connects a logger to every event
signal. QML reports its own half through `app.diag` / `Mizan/Diag.qml`. All of it
is DEBUG on `mizan.trace`, so it lands in `debug.log` and leaves `app.log` as the
audit trail:

```
* NavRail: navigate products
* PageHost: show products
> workflows.open(key='product_form', context={product_id=552})
  > session.can(permission='products.view')
  < session.can = True 0.0ms
  * DialogHost: open product_form {product_id=552}
  > products.one(product_id=552)
  < products.one = {id=552, name='Cola 33cl', +9} 3.1ms
  ~ workflows.requested('product_form', {product_id=552})
< workflows.open 41.2ms
```

`>` a call, `<` its return with the elapsed time, `!` a call that raised, `~` a
signal, `*` a QML action, `.` a QML note. Indentation is call depth, which is what
makes the file a causal chain rather than a list.

Two things are promoted out of the trace because they are defects rather than
history: a slot that raised (ERROR in `errors.log`, with the traceback **and** the
arguments it was called with) and a call that blocked the GUI thread for longer
than `MIZAN_SLOW_MS` (WARNING in `app.log`).

Not traced, deliberately: `@Property` getters and property-notification signals
(`busyChanged` fires on every load — one keystroke would cost a screenful), and
any argument whose name looks like a secret. `auth.login(username, password)`
logs `password=***`, decided once from the parameter name, so no call site can
forget it.

Knobs:

```
python run.py --debug          # DEBUG chatter on the console (files unchanged)
python run.py --no-trace       # no wrappers at all
set MIZAN_LOG_DIR=D:\somewhere # a different log directory, for support sessions
set MIZAN_TRACE=0              # same as --no-trace, for a frozen build
set MIZAN_TRACE_NOTIFY=1       # add property-notification signals
set MIZAN_SLOW_MS=20           # the "blocked the GUI thread" threshold
set MIZAN_TRACE_WIDTH=250      # show more of each value
```

Settings ends with a Diagnostics card that names the log directory and opens it,
so collecting a bug report is a button rather than a path read down a phone line.

The files rotate by size, and a Windows file lock makes a process fall back to
`app.<pid>.log` rather than lose records.

## Layout

| Path | What is in it |
| --- | --- |
| `app/bridge/` | One controller per subject — till, sales, purchases, stock, printing, cash, settings. `root.py` wires them together and is the only file that knows about more than one. |
| `qml/Mizan/` | The component library: tables, cards, the keypad, the product finder, the form group, the payment sheet. Registered in `qml/Mizan/qmldir`. |
| `qml/pages/` | Routed screens, one per navigation destination. |
| `qml/dialogs/` | Workflow dialogs, keyed by `app/bridge/workflows.py` and loaded by `Mizan/DialogHost.qml`. |
| `vendor/fluentpyside/` | The Fluent style, scaled. Patched, not upstream. |
| `tools/` | `qml_check.py` compiles every QML file; `dialog_shots.py` renders every dialog to a PNG; `log_check.py` proves the diagnostics and the action trace work; `scale_fluent.py` builds the vendored style. |

## Product photos

Optional, off nobody's critical path, and spread across both trees — so here is where
every part of it is:

| Part | Where |
| --- | --- |
| The column | `products.image_path` in `pos/app/data/db.py` — a bare **file name**, never a path |
| The files | `pos/appdata/product_images/`, beside the database, named by content hash |
| Store / forget | `db.store_product_image()` downscales to 640px with Pillow; `db.discard_product_image()` deletes only when no other product still points at the name |
| The boundary | `app/bridge/images.py` — a stored name becomes a `file:///` URL, a picked URL becomes a path |
| Choosing one | `qml/dialogs/ProductFormDialog.qml`: the 160px square in the Identity group, and a native `FileDialog`. Nothing is copied until Save |
| Showing them | `qml/Mizan/PosTile.qml` draws the same square as a band above the name — `showImage` from the grid, `imageSource` from the row |
| The switch | `ui.product_images` (Language & Appearance). `Till.imageCards` also requires `db.any_product_image()`, so a shop with no photos keeps the compact cards it has always had |

A photo is never required and a missing file is never an error: both answer "" and both
draw the same placeholder. Backups copy the database only — the photo folder is not in
them, which is a limitation and not an oversight: `create_backup` writes one file.

## Checking a change

```
python tools/qml_check.py        # every .qml compiles
python -m tools.log_check        # logging + the action trace, headless
python tools/dialog_shots.py     # every dialog, as a picture
python -m ruff check app run.py tools
```

`qml_check.py` catches what a running app would only find when an operator opened the
screen: a syntax error, an unknown type, a misspelled property. `log_check.py` proves
the four log files, the crash hooks and the trace still hold — including that a
password never reaches a log line and that the whole bridge is wrapped, not most of
it. `dialog_shots.py` catches what neither can — a heading that repeats the label
under it, a list that runs past the frame, a group with no visual separation.
