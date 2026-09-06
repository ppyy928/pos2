import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The front door.
 *
 *   ┌────────────────────────────────────────────────┐
 *   │ ▣ MIZAN POS                                    │  wordmark, over the backdrop
 *   │                                                │
 *   │      ___       ┌──────────────┐                │
 *   │     |o o|      │  Store Login │                │
 *   │     |___|      │  [username]  │                │  one card, one column
 *   │      / \       │  [password]  │                │
 *   │   a counter    │  [ Login   ] │                │
 *   │   terminal     │  En Fr ع     │                │
 *   │                └──────────────┘                │
 *   │ Version 2.4                                    │
 *   └────────────────────────────────────────────────┘
 *
 * WHAT CHANGED, AND WHY
 *
 * This was a 1040x640 card split into a white form panel and a dark brand panel
 * carrying a hand-drawn shopping bag (a Canvas composition, since deleted).
 * That layout existed to work around a real constraint — a flush two-pane split
 * cannot be done here, because `clip: true` on a rounded Rectangle clips
 * rectangularly and a square-cornered pane pokes out through the rounded corner —
 * and the workaround was a panel floating inside a card, which is two nested
 * surfaces to say one thing.
 *
 * Dropping the split panel removed that problem: the backdrop is the whole window,
 * so there are no panes to align and no corners to reconcile; the form is one card
 * in the middle of it; and the brand mark moves out onto the backdrop where it has
 * room.
 *
 * The Canvas that drew the bag is gone with it: hand-drawing the mark is the thing
 * being replaced, and a file nothing referenced was one more place to look.
 *
 * THE BACKDROP
 *
 * The gradient, plus one illustration beside the card: `assets/storefront.svg` — a
 * shop, seen from the pavement. Awning, sign, stocked window, open door, crates out
 * front. Drawn here rather than borrowed, in the app's own palette; provenance and the
 * reason the colours are baked into the file are in assets/CREDITS.md.
 *
 * It replaces a stock drawing of a phone being tapped on a card reader (unDraw's
 * "Mobile payments"), which was itself a replacement for a blurred photograph of a
 * market street. Both were about paying; neither was about a shop. The people who log
 * into this are standing behind a counter in one, and a picture of the thing they are
 * standing in is the only one that says "this is your shop's till" before a single word
 * is read. The photograph had a second problem: the blur was baked into the file
 * because this build has no run-time blur (QtQuick.Effects / MultiEffect is not
 * verified present, which is why nothing in FluentPySide has a shadow either), and it
 * cost 178KB of JPEG against 6KB of vector.
 *
 * The scrim stays QML, so the darkening can be retuned for a theme without touching
 * an asset; it is what keeps the wordmark and the version stamp legible.
 *
 * A missing or unreadable asset leaves the gradient, because a login screen that
 * cannot be logged into is the one failure it may not have.
 *
 * DEPTH WITHOUT SHADOWS
 *
 * Unchanged from the port: FluentPySide has no shadow idiom anywhere, so the card
 * separates from the backdrop with surface contrast, a 1px border and a rim
 * highlight along its top edge.
 *
 * Card surfaces come from Tokens.login* rather than Fluent.cardBackground: those
 * are translucent by design — they are meant to sit over Mica — and a translucent
 * card over anything with contrast in it is an unreadable card.
 */
Item {
    id: page

    // ------------------------------------------------------------------ API
    /* Carries the employee dict from db.authenticate():
       { id, name, username, role, permissions }. */
    signal authenticated(var user)
    signal closeRequested()

    // --------------------------------------------------------------- metrics
    readonly property int cardWidth: 460
    readonly property int gutter: Tokens.size.pagePadding

    // Room for the leading icon inside a field, and for the trailing reveal
    // button. Named because both fields and both mirror cases refer to them.
    readonly property int fieldIconGutter: Tokens.spacing.md + Tokens.icon.sm + Tokens.spacing.sm
    readonly property int fieldActionGutter: Tokens.size.controlSmall + Tokens.spacing.sm

    // ----------------------------------------------------------------- state
    readonly property var auth: (typeof app !== "undefined" && app && app.auth)
                                ? app.auth : null
    readonly property bool busy: auth ? auth.busy : false
    property string errorText: ""

    /* Index order must match the Segmented labels below. */
    readonly property var languages: ["en", "fr", "ar"]

    function languageIndex() {
        var i = languages.indexOf(Strings.language)
        return i < 0 ? 0 : i
    }

    function submit() {
        if (busy)
            return

        var username = usernameField.text.trim()
        /* An empty field moves focus and says nothing else. The placeholder
           already states what goes there, and the alternative — inventing
           "Enter your username." — would mean three new catalogue entries in
           three languages to say what a blinking cursor already says. */
        if (username === "") {
            usernameField.forceActiveFocus()
            return
        }
        if (passwordField.text === "") {
            passwordField.forceActiveFocus()
            return
        }
        if (!auth) {
            /* Deliberately not translated: a build-state message that disappears
               the moment the bridge lands, not a product string. It says what is
               actually wrong — a spinner that never resolves, or a generic
               "invalid password", would both be lies. */
            errorText = "The data layer is not connected yet."
            return
        }

        errorText = ""
        /* Async on purpose: verification is PBKDF2 with a deliberately high
           iteration count, which would freeze the UI on the GUI thread. The
           result arrives on the signals below. */
        auth.login(username, passwordField.text)
    }

    Connections {
        target: page.auth
        // The bridge is built alongside these pages; tolerate it not having
        // grown both signals yet rather than filling the log with warnings.
        ignoreUnknownSignals: true

        function onSucceeded(user) {
            page.errorText = ""
            passwordField.text = ""
            page.authenticated(user)
        }

        function onFailed(message) {
            page.errorText = (message && message !== "")
                ? message
                : Strings.t("login.error", "Invalid username or password.")
            passwordField.selectAll()
            passwordField.forceActiveFocus()
        }
    }

    /* Explicit, because a default button does not fire while a text field holds
       focus — the same reason pos installs QShortcuts on this screen. */
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: page.visible
        onActivated: page.submit()
    }
    Shortcut {
        sequence: "Escape"
        enabled: page.visible
        onActivated: page.closeRequested()
    }

    Component.onCompleted: usernameField.forceActiveFocus()

    /* Small caps field label. Both fields use it, so the type treatment cannot
       drift between them. Declared before its first use: an inline component
       referenced above its own declaration is not reliably resolved. */
    component FieldLabel: QC.Label {
        Layout.fillWidth: true
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.overline
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
        color: Fluent.textSecondary
    }

    // ------------------------------------------------------------------------
    // Backdrop
    // ------------------------------------------------------------------------
    /* The whole window, and now the only backdrop: the gradient this screen was
       designed around. What sits on it is a drawing of the thing this program is,
       not a photograph of a street it might stand in. */
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.lighter(Tokens.loginFrom, 1.25) }
            GradientStop { position: 0.42; color: Tokens.loginFrom }
            GradientStop { position: 1.0;  color: Tokens.loginTo }
        }
    }

    /*
     * The illustration: the shop this till stands in.
     *
     * A storefront — awning, sign board, a window with stock on the shelves, an open
     * door, crates on the pavement. What was here before was a stock drawing of a card
     * being tapped and, before that, a blurred market street: one said "paying
     * happens", the other said "somewhere busy", and neither said "this is your shop".
     * The person logging in is standing in the thing on the left.
     *
     * `assets/storefront.svg`, drawn for this screen in the app's own palette: light
     * shapes and brand emerald, nothing darker than the sign board, because the file's
     * colours are what get drawn — QML cannot tint an SVG's internals at run time — and
     * anything near-black would disappear into the bottom of the gradient. Provenance in
     * assets/CREDITS.md.
     *
     * It sits on the LEADING side, beside the card, never behind it: on a narrow
     * window there is no room for both, and a picture under a login form is a
     * picture nobody sees. `anchors.left` is mirrored to the right in Arabic by the
     * root's LayoutMirroring, so there is nothing to reverse by hand.
     */
    Image {
        id: artwork
        objectName: "loginArtwork"

        /* Space on one side of the centred card, less the gutters. Below `minRoom`
           the illustration is not shrunk into a smudge — it is dropped. */
        readonly property real sideRoom:
            (page.width - page.cardWidth) / 2 - page.gutter * 2
        readonly property real minRoom: 260

        source: "../assets/storefront.svg"
        visible: sideRoom >= minRoom
        anchors.left: parent.left
        anchors.leftMargin: page.gutter
        anchors.verticalCenter: parent.verticalCenter
        /* Nudged up by the version stamp's band so the pavement does not sit in the
           darkest part of the scrim. */
        anchors.verticalCenterOffset: -Tokens.size.command / 2

        width: Math.min(520, Math.max(0, sideRoom))
        fillMode: Image.PreserveAspectFit
        /* An SVG is rasterised at `sourceSize`, so it is given twice the width it is
           ever drawn at: Qt then downscales, which is the case its default filtering
           handles well, and the raster stays sharp on a 2x display. */
        sourceSize.width: 1040
        asynchronous: true
        cache: true
        opacity: status === Image.Ready && visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Fluent.anim.speed }
        }
    }

    /*
     * The scrim: one layer now, not two.
     *
     * The flat tint that used to sit here existed to put a floor under a photograph
     * — to cap how bright its lightest part could be. There is no photograph to cap
     * any more, and over a gradient it only muddied the brand colour. What remains
     * is the top-and-bottom darkening, which is what keeps the wordmark and the
     * version stamp legible; both live in bands where the gradient is at its
     * lightest.
     */
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.42) }
            GradientStop { position: 0.32; color: Qt.rgba(0, 0, 0, 0.06) }
            GradientStop { position: 0.74; color: Qt.rgba(0, 0, 0, 0.12) }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.52) }
        }
    }

    // ------------------------------------------------------------------------
    // Wordmark, over the backdrop
    // ------------------------------------------------------------------------
    RowLayout {
        id: wordmark
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: page.gutter
        spacing: Tokens.spacing.md

        Rectangle {
            implicitWidth: 48
            implicitHeight: 48
            radius: Tokens.radius.md
            color: Tokens.brand

            Icon {
                anchors.centerIn: parent
                icon: "ic_fluent_cart_20_regular"
                size: Tokens.icon.lg
                color: Tokens.onBrand
            }
        }

        ColumnLayout {
            spacing: 0

            /* The product name comes from the catalogue, not a literal, so there is
               one place to change it. Note that the catalogue says "DZ-Retail POS"
               while the window title, the app id and this folder all say MIZAN —
               that disagreement predates this port and is settled in i18n.py. */
            QC.Label {
                text: Strings.t("app.name", "DZ-Retail POS")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.subtitle
                font.weight: Font.Bold
                font.letterSpacing: 1.2
                color: Tokens.onChrome
            }

            QC.Label {
                text: Strings.t("app.tagline", "Enterprise Smart Management System")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Tokens.onChromeMuted
            }
        }

        Item { Layout.fillWidth: true }
    }

    // ------------------------------------------------------------------------
    // The card
    // ------------------------------------------------------------------------
    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - page.gutter * 2, page.cardWidth)
        /* Sized by its contents, floored so a short form does not look like a
           fragment, and capped so it never collides with the wordmark or the
           version line on a short window. */
        height: Math.min(parent.height - page.gutter * 2 - 2 * Tokens.size.command,
                         Math.max(420, form.implicitHeight + 2 * Tokens.spacing.xxl))

        radius: Tokens.radius.lg
        color: Tokens.loginSurface
        border.width: 1
        border.color: Tokens.loginBorder

        /* Rim light along the top edge — the library's own way of suggesting depth
           where it has no shadow. Inset by the corner radius so it stops before the
           rounding rather than crossing it. */
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: parent.radius
            height: 1
            color: Tokens.loginRim
            opacity: Tokens.isDark ? 1.0 : 0.7
        }

        ColumnLayout {
            id: form
            anchors.fill: parent
            anchors.margins: Tokens.spacing.xxl
            spacing: Tokens.spacing.md

            Item { Layout.fillHeight: true }

            QC.Label {
                Layout.fillWidth: true
                text: Strings.t("login.title", "Store Login")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.title
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
            }

            QC.Label {
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacing.sm
                text: Strings.t("login.subtitle", "Access your store account")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Fluent.textSecondary
                wrapMode: Text.WordWrap
            }

            FieldLabel {
                text: Strings.t("login.username", "Username")
            }

            QC.TextField {
                id: usernameField
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                placeholderText: Strings.t("login.username.ph",
                                           "Enter operator username")
                /* Padding does not mirror by itself the way anchors do, so the
                   gutter has to change sides explicitly for Arabic. It asks
                   Strings.rtl rather than `mirrored`: that flag belongs to Control,
                   and TextField descends from TextInput instead — reading it here is
                   a ReferenceError at run time, not a compile error. FilterBar's
                   fields ask the same question. */
                leftPadding: Strings.rtl ? Tokens.spacing.md : page.fieldIconGutter
                rightPadding: Strings.rtl ? page.fieldIconGutter : Tokens.spacing.md
                onAccepted: page.submit()

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacing.md
                    icon: "ic_fluent_person_20_regular"
                    size: Tokens.icon.sm
                    color: parent.activeFocus ? Fluent.accent : Fluent.textSecondary
                }
            }

            FieldLabel {
                Layout.topMargin: Tokens.spacing.xs
                text: Strings.t("login.password", "Password")
            }

            QC.TextField {
                id: passwordField
                property bool revealed: false

                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                echoMode: revealed ? TextInput.Normal : TextInput.Password
                placeholderText: Strings.t("login.password.ph", "Enter password")
                leftPadding: Strings.rtl ? page.fieldActionGutter : page.fieldIconGutter
                rightPadding: Strings.rtl ? page.fieldIconGutter : page.fieldActionGutter
                onAccepted: page.submit()

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacing.md
                    icon: "ic_fluent_lock_closed_20_regular"
                    size: Tokens.icon.sm
                    color: parent.activeFocus ? Fluent.accent : Fluent.textSecondary
                }

                /* A MouseArea rather than a ToolButton: it is how the library
                   builds its own controls, and it keeps the hit target at exactly
                   40 inside a 48 field instead of inheriting a styled button's
                   implicit size. */
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacing.xs
                    width: Tokens.size.controlSmall
                    height: Tokens.size.controlSmall
                    radius: Tokens.radius.sm
                    color: revealArea.containsMouse ? Fluent.subtleSecondary : "transparent"
                    opacity: revealArea.pressed ? 0.6 : 1.0

                    Icon {
                        anchors.centerIn: parent
                        icon: passwordField.revealed
                            ? "ic_fluent_eye_off_20_regular"
                            : "ic_fluent_eye_20_regular"
                        size: Tokens.icon.sm
                        color: Fluent.textSecondary
                    }

                    MouseArea {
                        id: revealArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: passwordField.revealed = !passwordField.revealed
                    }
                }
            }

            /* InfoBar hard-binds `width: parent.width`, which fights
               Layout.fillWidth if it goes into a layout directly. This wrapper is
               what the layout manages; the bar fills it. */
            Item {
                Layout.fillWidth: true
                Layout.topMargin: visible ? Tokens.spacing.xs : 0
                Layout.preferredHeight: visible ? errorBar.height : 0
                visible: page.errorText !== ""

                /* No title. InfoBar hides its title Label when the string is empty,
                   and the body already says the whole thing — a heading above it
                   would only be a second invented string saying "that failed"
                   twice. */
                InfoBar {
                    id: errorBar
                    severity: Severity.error
                    text: page.errorText
                    closable: false
                    timeout: -1
                }
            }

            QC.Button {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.sm
                Layout.preferredHeight: Tokens.size.command
                highlighted: true      // accent fill — brand emerald
                enabled: !page.busy
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.DemiBold
                /* Busy shows as text, not a ProgressRing: the ring's colour is
                   hardcoded to Fluent.accent, which is this button's own fill — an
                   invisible spinner. */
                text: page.busy
                    ? Strings.t("login.busy", "Signing in…")
                    : Strings.t("login.submit", "Login")
                onClicked: page.submit()
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.xs
                implicitHeight: 1
                color: Fluent.divider
            }

            Segmented {
                id: langPicker
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.xs
                items: ["English", "Français", "العربية"]

                /* Segmented assigns its own currentIndex from a MouseArea, which
                   would destroy a binding placed on it — the same trap as
                   Fluent.setTheme() breaking isDark. So the link to Strings runs
                   imperatively both ways. It converges: assigning an unchanged
                   value emits nothing. */
                onCurrentIndexChanged: Strings.setLanguage(page.languages[currentIndex])
                Component.onCompleted: currentIndex = page.languageIndex()
            }

            Connections {
                target: Strings
                function onLanguageChanged() {
                    langPicker.currentIndex = page.languageIndex()
                }
            }

            QC.Button {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: Tokens.size.controlSmall
                flat: true             // subtle config, not accent
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                text: Strings.t("login.close", "Close")
                onClicked: page.closeRequested()
            }
        }
    }

    // ------------------------------------------------------------------------
    // Build stamp, over the photograph
    // ------------------------------------------------------------------------
    /* What pos puts here. It replaced a shield-and-reassurance row: that would
       have been a claim about where the data lives, and this screen is not the
       place to make one the app cannot verify. */
    QC.Label {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: page.gutter
        text: Strings.t("login.version", "Version 2.4 — Desktop edition")
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.caption
        color: Tokens.onChromeMuted
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }
}
