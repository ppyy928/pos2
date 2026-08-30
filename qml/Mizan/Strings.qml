pragma Singleton
import QtQuick

/*
 * Translated strings, with live EN/FR/AR switching.
 *
 * Why not qsTr(): pos already owns a working three-language catalogue keyed by
 * string ("login.title", "nav.pos", ...) with runtime switching. Qt's own
 * mechanism would mean extracting every string into .ts files, translating them
 * again, compiling .qm, and reloading a QTranslator — the same result for a lot
 * of work, and it would leave two sources of truth for the same French. So the
 * catalogue is carried over as-is and reached through here.
 *
 * How live switching works, since it is not obvious: `map` is a *binding* on
 * app.i18n.strings, so it changes when the language does. `t()` reads `map`
 * while it runs, and QML captures property reads made inside a function called
 * from a binding — so `text: Strings.t("login.title")` is re-evaluated on every
 * language change, with no signal handler and no explicit dependency.
 *
 * The fallback argument is not defensive padding: it is what keeps a screen
 * legible before the bridge exists at all. Pass the English text.
 */
QtObject {
    id: strings

    readonly property bool ready: (typeof app !== "undefined") && app && app.i18n

    readonly property var map: ready ? app.i18n.strings : ({})

    /* "en" | "fr" | "ar". Drives the language selector and nothing else —
       direction is a separate question, see `rtl`. */
    readonly property string language: ready ? app.i18n.language : "en"

    /* Arabic is the only RTL language here, but ask the bridge rather than
       comparing to "ar": adding Hebrew or Farsi should not mean editing QML. */
    readonly property bool rtl: ready ? app.i18n.isRtl : false

    /* Translate `key`, falling back to `fallback` and then to the key itself.
       The key is a deliberate last resort: a missing string shows up as
       "login.submit" on the button, which is unmistakable in a screenshot. */
    function t(key, fallback) {
        var value = map[key]
        if (value !== undefined && value !== "")
            return value
        return fallback !== undefined ? fallback : key
    }

    /* Same, with %1-style arguments: t2("cart.n_items", "%1 items", count). */
    function t2(key, fallback, a1, a2) {
        var out = t(key, fallback)
        if (a1 !== undefined) out = out.replace("%1", a1)
        if (a2 !== undefined) out = out.replace("%2", a2)
        return out
    }

    /* Named placeholders: tf("pagination.showing", "...", {from: 1, to: 20, total: 93}).
       pos's catalogue uses both styles — most strings are %1/%2, but a few of the
       longer sentences name their slots ("Showing {from}-{to} of {total}") so a
       translator can reorder them freely. Both are kept as they are written, so
       the catalogue can be shared with pos verbatim rather than being rewritten
       into one style and then diverging.

       Every occurrence is replaced, not just the first, and a value the caller
       did not supply is left as its literal {name}: an untranslated slot is
       visible on screen, where a silent empty string would not be. */
    function tf(key, fallback, values) {
        var out = t(key, fallback)
        if (!values)
            return out
        for (var name in values)
            out = out.split("{" + name + "}").join(values[name])
        return out
    }

    function setLanguage(code) {
        if (ready)
            app.i18n.setLanguage(code)
    }
}
