import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import QtQuick.Templates as T
import FluentControls
import Mizan

/*
 * The front door: two zones, one composition.
 *
 *   ┌────────────────────────────────────┬───────────────────────┐
 *   │  (brand field, ~58%)               │  (form zone, ~42%)    │
 *   │  deep navy → petrol, with an       │  white surface        │
 *   │  abstract composition of shelves   │                       │
 *   │  and a receipt, drawn low-opacity  │  Sign in              │
 *   │                                    │  Use your operator …  │
 *   │  ▣ MIZAN POS                       │  USERNAME             │
 *   │  Sales and inventory, in balance.  │  [person _________ ]  │
 *   │                                    │  PASSWORD             │
 *   │                                    │  [lock _________ 👁 ] │
 *   │                                    │  ⚠ Invalid …          │
 *   │                                    │  [      Sign in    ]  │
 *   │                                    │  ─────────────────    │
 *   │                                    │  Language [English ▾] │
 *   │                                    │  Version 2.4 — …      │
 *   └────────────────────────────────────┴───────────────────────┘
 *
 * A DOOR, NOT A LANDING PAGE — AND NOT A BLANK CANVAS
 *
 * The two versions this screen has been through sat at either extreme: a
 * storefront illustration with a marketing headline behind the form, and a
 * pale canvas with a lonely card floating in the middle of it. The first
 * answered a question the operator had already answered by opening the app;
 * the second had no product in it at all. This one is the middle the brief
 * asks for: a deliberately composed brand field whose geometry — organised
 * blocks in a disciplined grid, a receipt's ruled lines — says "retail
 * software" without illustrating a supermarket, and a clean white
 * authentication surface that carries the whole form.
 *
 * The background is drawn, not downloaded: layered rectangles at low alpha,
 * no runtime image fetch, nothing to fail. The emerald light rises from the
 * lower right of a navy-to-petrol run, so the composition never fades into
 * the dead black the old gradient left at the bottom.
 *
 * SMALLER WINDOWS
 *
 * Below ~940px the brand field becomes a full-bleed backdrop and the form
 * floats on it as a card — the composition stays visible around the card, so
 * the character survives; the card carries a compact brand row, because it
 * is then the only brand on screen.
 *
 * WHAT STAYED
 *
 * The auth contract is untouched: `app.auth.login(username, password)` off
 * the GUI thread (PBKDF2 at 600 000 iterations), `succeeded(user)`,
 * `failed("")` for bad credentials and a verbatim message for a broken
 * database, `busy` while the hash runs. The username survives a failed
 * attempt; the password is selected for retyping. Enter submits. Switching
 * language retranslates and flips the layout direction live — the two zones
 * swap sides with everything else.
 *
 * A NOTE ON CAPS LOCK
 *
 * QML cannot query the keyboard's Caps Lock state — QKeyEvent exposes it only
 * to C++ event filters — so no indicator is drawn rather than a guessed one.
 */
Item {
    id: page

    // ------------------------------------------------------------------ API
    /* Carries the employee dict from db.authenticate():
       { id, name, username, role, permissions }. */
    signal authenticated(var user)

    // --------------------------------------------------------------- metrics
    /* Below this width the two zones collapse into backdrop + card. */
    readonly property bool wide: page.width >= 940
    readonly property int formWidth: 400
    readonly property int formPadding: 40
    readonly property int gutter: Tokens.size.pagePadding

    /* The brand field's share of a wide window. 58/40 with a little slack,
       per the brief: enough field for the composition to breathe, enough
       surface for the form to sit comfortably. */
    readonly property real brandShare: 0.58

    // Room for the leading icon inside a field, and for the trailing reveal
    // button. Named because both fields and both mirror cases refer to them.
    readonly property int fieldIconGutter: Tokens.spacing.md + Tokens.icon.sm + Tokens.spacing.sm
    readonly property int fieldActionGutter: Tokens.size.controlSmall + Tokens.spacing.sm

    // ----------------------------------------------------------------- state
    readonly property var auth: (typeof app !== "undefined" && app && app.auth)
                                ? app.auth : null
    readonly property bool busy: auth ? auth.busy : false
    property string errorText: ""

    /* Index order must match the ComboBox model below. */
    readonly property var languages: ["en", "fr", "ar"]
    readonly property var languageLabels: ["English", "Français", "العربية"]

    function languageIndex() {
        var i = languages.indexOf(Strings.language)
        return i < 0 ? 0 : i
    }

    function submit() {
        if (busy)
            return

        var username = usernameField.text.trim()
        /* An empty field moves focus and says nothing else. The label already
           states what goes there, and the alternative — inventing "Enter your
           username." — would mean three new catalogue entries in three
           languages to say what a blinking cursor already says. */
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
            /* One sentence, and it never says which half was wrong: "invalid
               username" tells an attacker the username exists. The username is
               left as typed so a typo is visible to its author. */
            page.errorText = (message && message !== "")
                ? message
                : Strings.t("login.error", "Invalid username or password.")
            passwordField.selectAll()
            passwordField.forceActiveFocus()
        }
    }

    /* Explicit, because a default button does not fire while a text field holds
       focus — the same reason the POS page installs QShortcuts. */
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: page.visible
        onActivated: page.submit()
    }

    Component.onCompleted: usernameField.forceActiveFocus()

    // ---------------------------------------------------------------- pieces
    /* Small field label above a field. Both fields use it, so the type
       treatment cannot drift between them. Caps and letter-spacing are the
       Fluent label convention; `overline` is 13px, a label size and not a
       content size. Declared before its first use: an inline component
       referenced above its own declaration is not reliably resolved. */
    component FieldLabel: QC.Label {
        Layout.fillWidth: true
        font.family: Tokens.font.family
        font.pixelSize: Tokens.font.overline
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
        color: Tokens.workspace.textSub
    }

    /*
     * THE PRIMARY ACTION, DRAWN RATHER THAN STYLED.
     *
     * The Fluent style's `highlighted` fill follows Fluent.accent, which
     * run.py points at the brand — but the button's own label, hover, pressed
     * and busy states are worth owning here, and PayButton/ChromeButton are
     * the app's precedent for a drawn button. Filled in the one emerald, with
     * white ink (4.5:1+ at this size), a focus ring drawn OUTSIDE the fill so
     * it stays visible, and a busy state that changes the word rather than
     * faking a spinner whose colour would match the fill exactly.
     */
    component SignInButton: T.AbstractButton {
        id: primary

        implicitHeight: Tokens.size.command
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus

        Accessible.role: Accessible.Button
        Accessible.name: text

        background: Rectangle {
            radius: Tokens.radius.md
            /* Disabled is a neutral grey from Tokens, not the style: the
               style defines no controlFillDisabled, and a binding that names
               a missing property silently keeps the emerald — a busy button
               that never looked busy. */
            color: !primary.enabled ? Tokens.disabledFill
                   : primary.down ? Tokens.brandPressed
                   : primary.hovered ? Tokens.brandHover
                   : Tokens.brand
            Behavior on color {
                ColorAnimation { duration: Fluent.anim.appearance }
            }

            /* Focus outside the fill, where it is visible against any state —
                the same construction PayButton uses on the dark dock. */
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: parent.radius + 3
                color: "transparent"
                border.width: 2
                border.color: Tokens.brand
                visible: primary.visualFocus
            }
        }

        contentItem: Text {
            text: primary.text
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.bodyLarge
            font.weight: Font.DemiBold
            color: primary.enabled ? Tokens.onBrand : Fluent.textDisabled
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ------------------------------------------------------------------ view
    /*
     * THE BRAND FIELD
     *
     * A wide window gives it 58% and the form the rest; a narrow one lets it
     * become the full-bleed backdrop with the form as a card floating on it.
     * Either way it is the same surface: the navy→petrol run, the emerald
     * light, the drawn composition, and (wide only) the brand block.
     */
    Rectangle {
        id: brandField

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: page.wide ? Math.round(parent.width * page.brandShare)
                         : parent.width

        gradient: Gradient {
            GradientStop { position: 0.0; color: Tokens.loginFrom }
            GradientStop { position: 0.55; color: Tokens.loginMid }
            GradientStop { position: 1.0; color: Tokens.loginTo }
        }

        /* The emerald light — restrained, and rising from the lower right
           where the composition sits, so the petrol end of the gradient is
           where the eye lands rather than where the screen dies. */
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.round(parent.width * 0.85)
            height: Math.round(parent.height * 0.75)
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: "#2A087F5B" }
            }
        }

        /* Soft horizontal shelf lines behind everything: the boards the
           blocks sit on, at the lowest alpha that still registers. */
        Column {
            anchors.fill: parent
            spacing: 78
            Repeater {
                model: 6
                delegate: Rectangle {
                    width: parent.width
                    height: 1
                    color: "#14FFFFFF"
                }
            }
        }

        /*
         * THE SHELF WALL — organised inventory blocks, right of centre.
         *
         * A disciplined grid of rounded rectangles at low alpha, a few of
         * them carrying a faint emerald fill as if stocked. This is the whole
         * illustration: no clipart, no carts, no statistics.
         */
        Grid {
            id: shelfWall

            anchors.right: parent.right
            anchors.rightMargin: 72
            anchors.verticalCenter: parent.verticalCenter
            columns: 3
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
                model: 12

                delegate: Rectangle {
                    /* A deterministic sprinkle of "stocked" cells — not a
                       random one, so the composition is identical on every
                       launch and in every screenshot. */
                    readonly property bool lit: index % 5 === 2

                    width: 92
                    height: 64
                    radius: 8
                    color: lit ? "#1A3ECF7A" : "#0DFFFFFF"
                    border.width: 1
                    border.color: lit ? "#593ECF7A" : "#2A97B4D6"
                }
            }
        }

        /*
         * THE RECEIPT — a tall ruled column beside the shelves.
         *
         * Lines of varying width ending in two emerald ones, which is what a
         * receipt is: items, then the total. Drawn at 70% so it reads as a
         * layer of the composition and not as a control.
         */
        Rectangle {
            anchors.right: shelfWall.left
            anchors.rightMargin: 56
            anchors.verticalCenter: parent.verticalCenter
            width: 124
            height: 312
            radius: 10
            color: "#B30D2536"
            border.width: 1
            border.color: "#26FFFFFF"

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Repeater {
                    /* [width-fraction, is-total] — the last two lines are the
                       receipt's answer, in the brand's green. */
                    model: [[0.92, 0], [0.55, 0], [0.78, 0], [0.60, 0],
                            [0.88, 0], [0.45, 0], [0.96, 1], [0.70, 1]]

                    delegate: Rectangle {
                        required property var modelData

                        readonly property bool isTotal: modelData[1] === 1

                        width: Math.round((parent.width) * modelData[0])
                        height: 5
                        radius: 2.5
                        color: isTotal ? "#5E3ECF7A" : "#2EFFFFFF"
                    }
                }
            }
        }

        /* THE BRAND BLOCK — the mark, the name, one quiet line. Wide windows
           only; a narrow window's card carries its own compact row, and the
           two must never both be on screen. */
        ColumnLayout {
            visible: page.wide
            anchors.left: parent.left
            anchors.leftMargin: 72
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.lg

            RowLayout {
                spacing: Tokens.spacing.md

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Tokens.icon.xl
                    implicitHeight: Tokens.icon.xl
                    radius: Tokens.radius.md
                    color: Tokens.brand

                    Icon {
                        anchors.centerIn: parent
                        icon: "ic_fluent_cart_20_regular"
                        size: Tokens.icon.lg
                        color: Tokens.onBrand
                    }
                }

                /* The name the window's title bar carries — the same words in
                   the same weight, so the product identifies itself once. The
                   catalogue's `app.name` ("DZ-Retail POS") is not drawn on
                   this screen: two names on one door is a contradiction, not
                   a hierarchy. */
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: Strings.t("app.product", "MIZAN POS")
                    font.family: Tokens.font.family
                    font.pixelSize: 30
                    font.weight: Font.Bold
                    font.letterSpacing: 0.8
                    color: "#FFFFFF"
                }
            }

            Text {
                Layout.leftMargin: 2
                text: Strings.t("login.tagline",
                                "Sales and inventory, in balance.")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: "#9FB3C8"
            }
        }
    }

    /*
     * THE FORM SURFACE
     *
     * Wide: a white zone filling the remainder of the window, its form
     * constrained to a comfortable 400px and centred. Narrow: a card floating
     * on the brand field, with the composition still visible around it — the
     * brief's "background around the form" rather than a blank canvas.
     */
    Rectangle {
        id: formPanel

        color: Tokens.loginSurface
        border.width: page.wide ? 0 : 1
        border.color: Tokens.workspace.border
        radius: page.wide ? 0 : Tokens.radius.lg

        anchors.top: parent.top
        anchors.bottom: parent.bottom

        state: page.wide ? "zone" : "card"
        states: [
            State {
                name: "zone"
                AnchorChanges {
                    target: formPanel
                    anchors.left: brandField.right
                    anchors.right: page.right
                }
            },
            State {
                name: "card"
                AnchorChanges {
                    target: formPanel
                    anchors.left: undefined
                    anchors.right: undefined
                    anchors.horizontalCenter: page.horizontalCenter
                    anchors.verticalCenter: page.verticalCenter
                }
                PropertyChanges {
                    target: formPanel
                    width: Math.min(page.width - 2 * page.gutter, 440)
                    height: Math.min(page.height - 2 * page.gutter,
                                     form.implicitHeight + 2 * page.formPadding)
                }
            }
        ]

        ColumnLayout {
            id: form

            anchors.centerIn: parent
            width: Math.min(parent.width - 2 * page.formPadding, page.formWidth)
            spacing: Tokens.spacing.md

            // -- compact identity, on the card only
            /* A narrow window has no brand field, so the card says the name
               once, quietly. On a wide window the brand field already said it
               and this row is absent — never twice. */
            RowLayout {
                Layout.fillWidth: true
                visible: !page.wide
                spacing: Tokens.spacing.sm

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Tokens.icon.lg
                    implicitHeight: Tokens.icon.lg
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
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: Strings.t("app.product", "MIZAN POS")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.bodyLarge
                    font.weight: Font.Bold
                    font.letterSpacing: 0.4
                    color: Tokens.workspace.text
                }
            }

            // -- heading and one functional line
            Text {
                Layout.fillWidth: true
                Layout.topMargin: page.wide ? 0 : Tokens.spacing.md
                text: Strings.t("login.heading", "Sign in")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.title
                font.weight: Font.DemiBold
                color: Tokens.workspace.text
            }

            Text {
                Layout.fillWidth: true
                text: Strings.t("login.heading.support",
                                "Use your operator account to access the register.")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                color: Tokens.workspace.textSub
                wrapMode: Text.WordWrap
            }

            // -- the fields
            FieldLabel {
                Layout.topMargin: Tokens.spacing.xs
                text: Strings.t("login.username", "Username")
            }

            /* The field's own frame is drawn here rather than taken from the
               style, so the focus treatment is the emerald the rest of the
               app uses — a blue focus ring on an emerald screen was one of
               the loudest complaints about the version this replaces, and the
               style's ring follows a token this screen should not depend on.
               The same construction PaymentEntry's amount field uses. */
            QC.TextField {
                id: usernameField
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.size.control
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                placeholderText: Strings.t("login.username.ph",
                                           "Enter operator username")
                Accessible.name: Strings.t("login.username", "Username")
                /* Padding does not mirror by itself the way anchors do, so the
                   gutter has to change sides explicitly for Arabic. It asks
                   Strings.rtl rather than `mirrored`: that flag belongs to
                   Control, and TextField descends from TextInput instead —
                   reading it here is a ReferenceError at run time, not a
                   compile error. FilterBar's fields ask the same question. */
                leftPadding: Strings.rtl ? Tokens.spacing.md : page.fieldIconGutter
                rightPadding: Strings.rtl ? page.fieldIconGutter : Tokens.spacing.md
                onAccepted: page.submit()

                background: Rectangle {
                    radius: Tokens.radius.md
                    color: Tokens.workspace.surface
                    border.width: usernameField.activeFocus ? 2 : 1
                    border.color: usernameField.activeFocus
                                  ? Tokens.brand : Tokens.workspace.border

                    Behavior on border.color {
                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacing.md
                    icon: "ic_fluent_person_20_regular"
                    size: Tokens.icon.sm
                    color: parent.activeFocus ? Tokens.brand
                                              : Tokens.workspace.textSub
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
                Accessible.name: Strings.t("login.password", "Password")
                leftPadding: Strings.rtl ? page.fieldActionGutter : page.fieldIconGutter
                rightPadding: Strings.rtl ? page.fieldIconGutter : page.fieldActionGutter
                onAccepted: page.submit()

                background: Rectangle {
                    radius: Tokens.radius.md
                    color: Tokens.workspace.surface
                    border.width: passwordField.activeFocus ? 2 : 1
                    border.color: passwordField.activeFocus
                                  ? Tokens.brand : Tokens.workspace.border

                    Behavior on border.color {
                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacing.md
                    icon: "ic_fluent_lock_closed_20_regular"
                    size: Tokens.icon.sm
                    color: parent.activeFocus ? Tokens.brand
                                              : Tokens.workspace.textSub
                }

                /* A MouseArea rather than a ToolButton: it is how the library
                   builds its own controls, and it keeps the hit target at
                   exactly 40 inside a 48 field. */
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacing.xs
                    width: Tokens.size.controlSmall
                    height: Tokens.size.controlSmall
                    radius: Tokens.radius.sm
                    color: revealArea.containsMouse
                           ? Tokens.workspace.inset : "transparent"
                    opacity: revealArea.pressed ? 0.6 : 1.0

                    Icon {
                        anchors.centerIn: parent
                        icon: passwordField.revealed
                            ? "ic_fluent_eye_off_20_regular"
                            : "ic_fluent_eye_20_regular"
                        size: Tokens.icon.sm
                        color: Tokens.workspace.textSub
                    }

                    MouseArea {
                        id: revealArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: passwordField.revealed = !passwordField.revealed
                    }

                    QC.ToolTip {
                        text: passwordField.revealed
                              ? Strings.t("login.hide_password", "Hide password")
                              : Strings.t("login.show_password", "Show password")
                        visible: revealArea.containsMouse
                        delay: 400
                    }
                }
            }

            // -- inline error, only ever about what just happened
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: visible ? Tokens.spacing.xs : 0
                visible: page.errorText !== ""
                spacing: Tokens.spacing.sm

                Icon {
                    Layout.alignment: Qt.AlignTop
                    icon: "ic_fluent_error_circle_20_regular"
                    size: Tokens.icon.sm
                    color: Tokens.danger
                    /* Nudged down so the glyph's optical centre lines up with
                       the first text line, not its bounding box. */
                    Layout.topMargin: 2
                }

                Text {
                    Layout.fillWidth: true
                    text: page.errorText
                    wrapMode: Text.WordWrap
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    color: Tokens.danger
                }
            }

            // -- the one primary action
            SignInButton {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.xs
                enabled: !page.busy
                /* The busy word changes and the button refuses a second press
                   — that is the whole loading state, and it is honest: a
                   spinner the colour of the fill would be invisible, and a
                   disabled button that still invited the press would not be
                   disabled. */
                text: page.busy
                    ? Strings.t("login.busy", "Signing in…")
                    : Strings.t("login.submit", "Sign in")
                onClicked: page.submit()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.sm
                implicitHeight: 1
                color: Tokens.workspace.border
            }

            // -- language, secondary to authentication
            /* A combo, not a row of three buttons: the setting is a choice
               between three equally valid options, which is exactly what a
               ComboBox says, and the row of segments it replaces read as
               three primary actions competing with Sign in. It sits below the
               divider, in the form's quietest zone. */
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.md

                Text {
                    Layout.fillWidth: true
                    text: Strings.t("login.language", "Language")
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    color: Tokens.workspace.textSub
                }

                QC.ComboBox {
                    id: languageBox

                    implicitWidth: 160
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    model: page.languageLabels
                    /* Imperative both ways: ComboBox assigns its own
                       currentIndex from its popup, which would destroy a
                       binding — the same trap as Segmented, documented on the
                       old picker. Assigning an unchanged value emits nothing,
                       so the two converge. */
                    Component.onCompleted: currentIndex = page.languageIndex()
                    onActivated: (index) => Strings.setLanguage(page.languages[index])

                    Connections {
                        target: Strings
                        function onLanguageChanged() {
                            languageBox.currentIndex = page.languageIndex()
                        }
                    }
                }
            }

            // -- build stamp, at the composition's bottom edge
            /* What pos puts here, in the quietest ink on the white surface:
               a version stamp is support information, and the form is for
               the one thing this screen exists to do. */
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.xs
                text: Strings.t("login.version", "Version 2.4 — Desktop edition")
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Tokens.workspace.textSub
                elide: Text.ElideRight
            }
        }
    }
}
