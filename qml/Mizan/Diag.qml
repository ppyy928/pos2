pragma Singleton

import QtQml

/*
 * The trace, as QML sees it.
 *
 *     Diag.action("PosPage", "pay pressed", { total: 1245.41 })
 *     Diag.action("NavRail", "navigate", key)
 *     Diag.note("StockCountDialog", "sheet has 240 lines")
 *     Diag.warn("ImportDialog", "no column chosen for the name")
 *     Diag.fail("PageHost", "products page: " + component.errorString())
 *
 * Everything Python does is traced automatically (app/instrument.py wraps every
 * bridge slot and watches every signal). This is the other half: what the
 * operator did, which exists only in QML. Both go to the same `mizan.trace`
 * channel and the same debug.log, in call order — so a support log shows the
 * navigation, the dialog that opened, the slot it called and the toast that came
 * back, in that order, rather than four unrelated facts.
 *
 * WHY A SINGLETON IN FRONT OF app.diag
 *
 * `app` is a context property, and `tools/qml_check.py` deliberately loads the
 * whole tree without it — so every read of `app` in this app is guarded. One
 * guard here is one guard; the same guard repeated in every component that wants
 * to log is a guard that gets forgotten. With no bridge, every function below is
 * a no-op and nothing on screen changes.
 *
 * It also gives the payload a default. A Qt slot's arguments are all required,
 * so `app.diag.action(source, what)` would be a TypeError at the boundary;
 * `Diag.action(source, what)` is not.
 *
 * WHAT TO LOG, AND WHAT NOT TO
 *
 * Actions and defects, not state. A binding that fires on every keystroke, a
 * hover, a repaint, an animation frame — those are not actions, and the point of
 * this file is a log a person can read to the end.
 */
QtObject {
    id: diag

    readonly property var bridge: (typeof app !== "undefined" && app && app.diag)
                                  ? app.diag : null

    /* Whether anything written here is being kept. Worth testing before building
       an expensive detail object, and nothing else. */
    readonly property bool enabled: bridge !== null && bridge.tracing

    /* Where the four log files are, for a screen that offers to show them. */
    readonly property string logDir: bridge ? bridge.logDir : ""

    /* Something the operator did. `detail` is optional. */
    function action(source, what, detail) {
        if (bridge)
            bridge.action(source, what, detail === undefined ? null : detail)
    }

    /* A fact about what a screen decided, when the action alone is not enough. */
    function note(source, message) {
        if (bridge)
            bridge.note(source, message)
    }

    /* Something is wrong, the screen carried on. Reaches app.log as well. */
    function warn(source, message) {
        if (bridge)
            bridge.warn(source, message)
        else
            console.warn(source + ": " + message)
    }

    /* A defect: a page that would not load, a component that would not build.
       Reaches errors.log. Falls back to the console so a failure during startup
       — before the bridge exists — is still said out loud somewhere. */
    function fail(source, message) {
        if (bridge)
            bridge.fail(source, message)
        else
            console.error(source + ": " + message)
    }

    /* Open the log folder in the file manager. What a support screen calls. */
    function openLogFolder() {
        return bridge ? bridge.openLogFolder() : false
    }
}
