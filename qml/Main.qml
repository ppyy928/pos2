import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import QtQuick.Window
import FluentControls
import Mizan

/*
 * The application shell: window chrome, navigation rail, page host.
 *
 * Built on FluentWindowBase rather than FluentWindow. FluentWindowBase is the
 * part of the library that is genuinely hard to reproduce — frameless flags,
 * DWM rounded corners, the resize hit-testing, theme registration, the float
 * layer for popups — and it is all reused verbatim. FluentWindow adds
 * NavigationView + NavigationBar on top, and that is the one part of the
 * library that cannot be scaled up safely: NavigationItem fixes its row height
 * in an expression (40 + …) while the button inside it uses a bare literal
 * (37), so scaling the literals alone puts a 55px button inside a 40px row.
 * The rail is therefore ours (NavRail), sized from Mizan.Tokens. Every actual
 * widget still comes from FluentControls.
 */
FluentWindowBase {
    id: window

    title: qsTr("MIZAN POS")

    width: 1440
    height: 900
    // The rail collapses itself below 1200, so the minimum is set by the POS
    // screen: cart + tile grid + totals dock.
    minimumWidth: 1180
    minimumHeight: 760

    // 56 — a command bar's height, and Fluent's own scaled default. Not pushed
    // to 64: the caption buttons sit at the top of their Row, so a taller bar
    // only adds a gap under Close.
    titleBarHeight: Tokens.size.command

    // We draw the brand mark and the window actions ourselves, in titleBarHost.
    titleEnabled: false

    /*
     * RTL for Arabic. In Qt Widgets this was QApplication.setLayoutDirection;
     * the QML equivalent is LayoutMirroring, which reverses anchors and Layouts
     * for the whole tree that inherits it. Driven by the i18n bridge once it is
     * registered, and simply false before then — the guard is evaluated when
     * the binding is first established, which is after run.py has set its
     * context properties.
     */
    readonly property bool rtl: (typeof app !== "undefined" && app && app.i18n)
                                ? app.i18n.isRtl : false
    LayoutMirroring.enabled: rtl
    LayoutMirroring.childrenInherit: true

    /*
     * The signed-in employee dict from db.authenticate(), or null. This is the
     * gate for the whole shell: null means the login layer is up and everything
     * behind it is inert. Held here rather than in the login page because the
     * page is unloaded once it succeeds, and `role`/`permissions` outlive it —
     * they are what the rail and the pages check.
     */
    property var currentUser: null
    readonly property bool signedIn: currentUser !== null

    /* Who is at the till is the first question a support log has to answer, and
       the shell is where that becomes true. `auth.login` and its result are
       already traced on the Python side; this is the shell agreeing. */
    onCurrentUserChanged: {
        if (currentUser)
            Diag.action("shell", "signed in", currentUser.name || currentUser.username)
        else
            Diag.action("shell", "signed out")
    }

    /*
     * Theme changes go through the manager, never through Fluent.setTheme():
     * Fluent.isDark is *bound* to the _themeMode context property, so assigning
     * it directly breaks that binding for the rest of the session and the native
     * DWM frame stops following the theme.
     */
    function toggleTheme() {
        if (typeof _themeManager === "undefined" || !_themeManager) {
            Diag.warn("shell", "no theme manager; the theme cannot be changed")
            return
        }
        Diag.action("shell", "theme", Fluent.isDark ? "light" : "dark")
        _themeManager.setTheme(Fluent.isDark ? "light" : "dark")
    }

    /*
     * Called from run.py --mica, and only after DWM has accepted the backdrop.
     * This property is what makes the window and its background rectangle
     * transparent, so setting it before Mica is confirmed would leave a
     * see-through window on any machine that refuses the backdrop.
     */
    function setBackdropEnabled(enabled) {
        Fluent.backdropEnabled = enabled
    }

    // =====================================================================
    // TITLE BAR
    // =====================================================================
    /*
     * FluentWindowBase's default property collects declared children into the
     * content area, so an explicit parent is how anything reaches the title bar
     * from a derived window. Plain Items do not accept mouse events, so the
     * empty space in here still drags the window.
     */
    Item {
        parent: window.titleBarHost
        /* `parent`, not the host by name. Anchoring to an item names a *relation*
           — parent or sibling — and Qt resolves it when the anchor is set, which
           is before the `parent` assignment above has necessarily been applied;
           naming window.titleBarHost there costs a "Cannot anchor to an item that
           isn't a parent or sibling" and leaves the title bar contents unsized.
           Anchoring to whatever the parent turns out to be cannot get that
           wrong. */
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacing.md
            spacing: Tokens.spacing.sm

            // Brand mark. The one place the accent appears as a solid fill in
            // the chrome, so the window reads as MIZAN before anything loads.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: Tokens.icon.lg
                height: Tokens.icon.lg
                radius: Tokens.radius.sm
                color: Tokens.brand

                Icon {
                    anchors.centerIn: parent
                    icon: "ic_fluent_cart_20_regular"
                    size: Tokens.icon.sm
                    color: Tokens.onBrand
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: qsTr("MIZAN POS")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
                color: Fluent.textPrimary
            }

            // Drag zone.
            Item { Layout.fillWidth: true }

            QC.ToolButton {
                Layout.alignment: Qt.AlignVCenter
                icon.name: Fluent.isDark ? "ic_fluent_weather_sunny_20_regular"
                                         : "ic_fluent_weather_moon_20_regular"
                onClicked: window.toggleTheme()

                QC.ToolTip.visible: hovered
                QC.ToolTip.delay: 400
                QC.ToolTip.text: Fluent.isDark ? qsTr("Light theme")
                                               : qsTr("Dark theme")
            }
        }
    }

    // =====================================================================
    // SHELL
    // =====================================================================
    RowLayout {
        anchors.fill: parent
        spacing: 0

        /*
         * Disabled, not just covered, while the login layer is up. The layer's
         * backdrop is an opaque Rectangle, and a Rectangle does not accept mouse
         * events — clicks would fall straight through to the rail underneath,
         * and Tab would walk into it. Disabling the subtree is what actually
         * blocks both.
         */
        enabled: window.signedIn

        NavRail {
            id: rail
            Layout.fillHeight: true
            // One-way: the rail asks, the host decides, the rail reflects. The
            // checked state can never disagree with what is on screen.
            currentKey: host.currentKey
            onActivated: (key) => {
                // The operator's own navigation, told apart in the log from the
                // programmatic kind (a dashboard card, a link in a detail view),
                // which arrives through Destinations.requested below.
                Diag.action("NavRail", "navigate", key)
                host.show(key)
            }
        }

        PageHost {
            id: host
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Login arrives later as an overlay above the shell, not as a
            // destination, so the shell always starts on a real page.
            Component.onCompleted: show(Destinations.defaultKey)
        }
    }

    /*
     * Window-wide hooks, inside an Item because they are not Items themselves.
     *
     * FluentWindowBase's default property is `contentArea.children`, which is a
     * list of QQuickItem — so a Shortcut or a Connections declared straight in
     * the window fails at load with "Cannot assign object of type QQuickShortcut
     * to list property content", and takes the whole shell with it. A zero-sized
     * Item is a legal child of that list and a legal parent for both, and it
     * costs nothing: it has no size, no paint and no input area.
     */
    Item {
        id: hooks

        // Collapsing the rail is the one chrome action worth a shortcut — on a
        // 1366px till it is the difference between 4 and 5 tile columns.
        Shortcut {
            sequence: "Ctrl+B"
            onActivated: {
                rail.collapsed = !rail.collapsed
                Diag.action("shell", "Ctrl+B rail",
                            rail.collapsed ? "collapsed" : "expanded")
            }
        }

        // Escape backs out of a drill-down (order detail, product editor) and does
        // nothing at the top of a module, where it must stay free for the POS page.
        // Gated on signedIn as well, so it cannot collide with the login layer's own
        // Escape — two enabled shortcuts on one sequence is an ambiguous activation,
        // and neither fires.
        Shortcut {
            sequence: "Escape"
            enabled: window.signedIn && host.depth > 1
            onActivated: {
                Diag.action("shell", "Escape back")
                host.pop()
            }
        }

        Connections {
            // Null while the loader is inactive, which is a no-op rather than an
            // error.
            target: loginLayer.item

            function onAuthenticated(user) {
                window.currentUser = user
            }

            function onCloseRequested() {
                // The last line of a normal run, and the one that tells a crash
                // apart from a shutdown when the log ends without it.
                Diag.action("shell", "quit requested from the login screen")
                Qt.quit()
            }
        }

        /* Nothing is scannable before somebody signs in, and the login form's two
           fields are the last place a stray burst should be interpreted. The
           decoder never swallows a keystroke either way — see its own header — but
           off is off. */
        Binding {
            target: (typeof app !== "undefined" && app) ? app.scanner : null
            property: "enabled"
            value: window.signedIn
        }

        /* Printing is a device, and a device fails while some other screen is
           open. The window says so. */
        Connections {
            target: (typeof app !== "undefined" && app) ? app.sales : null
            ignoreUnknownSignals: true

            function onPrintFailed(message) {
                shellToasts.show(message, Severity.caution)
            }
        }

        /* A page asking to be somewhere else — a dashboard card, a link in a
           detail view. Only the shell owns navigation, so this is the one place
           that acts on it. */
        Connections {
            target: Destinations
            function onRequested(key) {
                Diag.action("shell", "navigate requested by a page", key)
                host.show(key)
            }
        }

        /* The workflow router asks, the window answers. Every page funnels its
           "open something else" through app.workflows, which checks the
           permission and then emits this — so a dialog is opened in exactly one
           place, outlives the page that asked for it, and a refusal is always
           said out loud. */
        Connections {
            target: (typeof app !== "undefined" && app) ? app.workflows : null
            ignoreUnknownSignals: true

            function onRequested(key, context) {
                dialogs.show(key, context)
            }

            function onRefused(message) {
                shellToasts.show(message, Severity.caution)
            }
        }

        /* The session ended from somewhere that was not the login form — the
           idle lock, today — and the shell has to land where signing out
           lands: no operator, no dialogs, login layer up. Signing IN is not
           handled here; the login layer's own `authenticated` signal is that
           path, and this only ever clears. */
        Connections {
            target: (typeof app !== "undefined" && app) ? app.session : null
            ignoreUnknownSignals: true

            function onChanged() {
                if (!app.session.signedIn && window.currentUser !== null) {
                    Diag.action("shell", "session ended — locking")
                    window.currentUser = null
                    dialogs.closeAll()
                }
            }
        }
    }

    // =====================================================================
    // LOGIN LAYER
    // =====================================================================
    /*
     * An overlay, not a destination: it has no rail entry, no history, and the
     * shell must not be reachable behind it. It covers the content area but not
     * the title bar, so the window can still be dragged, themed and closed while
     * signed out.
     *
     * A Loader so the page — and its Canvas — is released once it succeeds, and
     * rebuilt from scratch if it is ever needed again (lock screen, switch user).
     */
    Loader {
        id: loginLayer
        anchors.fill: parent
        z: 10
        active: !window.signedIn
        source: "pages/LoginPage.qml"
    }

    /* Dialogs live here, not on the page that opens them: PageHost replaces the
       page on every navigation, and a dialog parented to it would go with it.
       Above the login layer, so a workflow refusal is still readable if one
       somehow arrives during sign-in. */
    DialogHost {
        id: dialogs
        anchors.fill: parent
        z: 20

        onUnavailable: (key) => shellToasts.show(
            qsTr("That screen is not part of this build yet."), Severity.info)
        /* A file that exists and will not load is a defect, and it says which. */
        onFailed: (key, message) => shellToasts.show(key + ": " + message,
                                                     Severity.error)
    }

    /* The shell's own toasts — workflow refusals and dialog failures. Pages keep
       their own host so a page-level message sits above that page's furniture. */
    ToastHost {
        id: shellToasts
        z: 60
    }
}
