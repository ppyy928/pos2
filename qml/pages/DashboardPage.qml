import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The morning screen. Ported from pos's dashboard over its report functions.
 *
 * Six figures, all for today, and every one of them is a question somebody asks
 * before opening: what did we take, what did we make on it, what did we spend,
 * what is on the shelves, who owes us, who do we owe. Each card jumps to the
 * screen that can do something about it — a number nobody can act on is
 * decoration.
 *
 * Nothing here is computed from another page's numbers. Each card is one of pos's
 * report queries, so the dashboard and the page it points at cannot disagree.
 */
Item {
    id: root

    readonly property var ctrl: (typeof app !== "undefined" && app) ? app.dashboard : null
    readonly property var session: (typeof app !== "undefined" && app) ? app.session : null

    /*
     * The period this screen reports on.
     *
     * Three presets, because a morning screen has three questions and no more: what
     * happened today, how the week is going, how the month is going. Anything
     * narrower or wider is a report, and Reports has the full set of presets plus
     * two date fields.
     *
     * `days` counts today as one, so 1 is today alone. The selector governs the
     * three period figures (sales, profit, spending) and all three charts; the other
     * three cards are balances — stock value, what customers owe, what the shop owes
     * — and pos's functions for those take no dates at all, because a debt is true
     * now rather than over a fortnight.
     */
    readonly property var periods: [
        { key: "today",  days: 1,
          label: Strings.t("reports.preset.today", "Today") },
        { key: "last7",  days: 7,
          label: Strings.t("reports.preset.last7", "Last 7 days") },
        { key: "last30", days: 30,
          label: Strings.t("reports.preset.last30", "Last 30 days") }
    ]

    /* The week, not today. pos's dashboard defaulted to the same window
       (pos/app/pages/dashboard.py:140-146): one day is a dot on a curve. */
    property int periodIndex: 1

    readonly property int periodDays: root.periods[root.periodIndex].days

    function refresh() {
        if (ctrl)
            ctrl.load(root.periodDays)
    }

    readonly property bool busy: ctrl ? ctrl.busy : false
    readonly property var cards: ctrl ? ctrl.cards : null

    /*
     * The three chart series, over the period selected above.
     *
     * The controller hands back the window it actually queried and every chart card
     * prints it under its title. Three of the six figures above them are balances
     * that ignore the period, so the charts have to say which days they mean.
     */
    readonly property var series: ctrl ? ctrl.series : null
    readonly property var trend: (series && series.trend) ? series.trend : []
    readonly property var mix: (series && series.mix) ? series.mix : []
    readonly property var ranking: (series && series.ranking) ? series.ranking : []
    readonly property string chartRange: (series && series.range) ? series.range : ""
    readonly property string mixTotal: (series && series.total) ? series.total : ""

    signal navigate(string key)

    function value(key) {
        if (!cards)
            return "—"
        var found = cards[key]
        return (found === undefined || found === null || found === "") ? "—" : found
    }

    function number(key) {
        if (!cards)
            return 0
        var found = cards[key]
        return typeof found === "number" ? found : 0
    }

    /* PageHost gives a page no navigation of its own, and the shell's ids are
       not in a page's scope chain — so a card asks through the singleton both
       ends already import. */
    function go(entry) {
        if (entry.workflow !== undefined) {
            if (workflows)
                workflows.open(entry.workflow, entry.context || ({}))
            return
        }
        Destinations.request(entry.page)
    }

    /*
     * The shortcuts, and why these seven.
     *
     * Not "every page" — the rail already lists every page, and repeating it here
     * as fourteen cards makes the dashboard a second menu instead of a place to
     * start work. What back offices put on this screen (Square, Odoo, Vend,
     * Shopify POS all converge on it) is the till plus the things a shop *creates*:
     * a product, a delivery, a customer, a return, and opening or closing the
     * drawer. Those are the daily verbs.
     *
     * So six of the seven open a form, not a page. The exception at the end is the
     * debtor list, which is the one *reading* task a shop does every day in a
     * market that sells on account.
     *
     * Each carries the permission it needs, and a card the operator cannot use is
     * not shown rather than shown dead — the router would refuse it anyway, and a
     * grid of refusals is not a starting point.
     */
    readonly property var shortcuts: {
        var out = [
            {
                key: "pos",
                page: "pos",
                icon: "ic_fluent_cart_20_regular",
                label: Strings.t("nav.pos", "Point of Sale"),
                tone: "primary",
                permission: "pos.sell",
                primary: true
            },
            {
                key: "product",
                workflow: "product_form",
                context: ({}),
                icon: "ic_fluent_box_multiple_20_regular",
                label: Strings.t("product.add_title", "New product"),
                tone: "info",
                permission: "products.view"
            },
            {
                key: "purchase",
                workflow: "purchase_form",
                context: ({}),
                icon: "ic_fluent_vehicle_truck_profile_20_regular",
                label: Strings.t("purchases.new", "New purchase"),
                tone: "info",
                permission: "purchases.view"
            },
            {
                key: "customer",
                workflow: "customer_edit",
                context: ({}),
                icon: "ic_fluent_person_add_20_regular",
                label: Strings.t("customers.add", "New customer"),
                tone: "success",
                permission: "customers.manage"
            },
            {
                key: "return",
                workflow: "sale_select",
                context: ({ purpose: "return" }),
                icon: "ic_fluent_arrow_undo_20_regular",
                label: Strings.t("return.create_title", "New return"),
                tone: "warning",
                permission: "sales.edit"
            },
            {
                /* One card, two states: a drawer is either open or it is not, and
                   the shop only ever wants the other one. */
                key: "drawer",
                workflow: "cash_entry",
                context: ({ purpose: root.drawerOpen ? "close" : "open" }),
                icon: root.drawerOpen ? "ic_fluent_lock_closed_20_regular"
                                      : "ic_fluent_lock_open_20_regular",
                label: root.drawerOpen
                       ? Strings.t("cash.close_session", "Close the drawer")
                       : Strings.t("cash.open_session", "Open the drawer"),
                tone: "success",
                permission: "cash.manage"
            },
            {
                key: "debts",
                page: "customers",
                icon: "ic_fluent_wallet_20_regular",
                label: Strings.t("dashboard.debts", "Who owes money"),
                tone: "warning",
                permission: "customers.view"
            }
        ]

        var allowed = []
        for (var i = 0; i < out.length; i++) {
            var entry = out[i]
            if (entry.page !== undefined && !Destinations.isBuilt(entry.page))
                continue
            if (entry.permission && session && !session.can(entry.permission))
                continue
            allowed.push(entry)
        }
        return allowed
    }

    /* Read for the drawer card's two states. Loaded on arrival because this screen
       is often the first one opened in the morning, which is exactly when the
       answer matters. */
    readonly property bool drawerOpen: drawer ? drawer.isOpen : false
    readonly property var drawer: (typeof app !== "undefined" && app) ? app.cash : null

    /*
     * A shortcut, as a card.
     *
     * Bigger than a till tile on purpose: this is the one screen an owner opens
     * cold, on a machine across the shop, and the target has to be findable rather
     * than merely hittable. Same states as PosTile — subtle fill on hover, a
     * toned edge, a focus ring — because it is the same gesture.
     */
    component Shortcut: QC.AbstractButton {
        id: card

        property var entry: ({})
        property string tone: "primary"
        property bool primary: false

        implicitWidth: 280
        implicitHeight: 168
        hoverEnabled: true

        Accessible.role: Accessible.Button
        Accessible.name: text

        background: Rectangle {
            radius: Tokens.radius.lg
            color: card.down ? Fluent.subtleTertiary
                 : card.hovered ? Fluent.subtleSecondary
                                : Fluent.cardBackground
            Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

            /* The till is the reason the machine is switched on, so its card keeps
               a brand edge without being hovered. */
            border.width: card.primary ? 2 : 1
            border.color: card.primary ? Tokens.brand
                        : card.hovered ? Tokens.toneInk(card.tone)
                                       : Fluent.dividerBorder

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: Fluent.accent
                visible: card.visualFocus
            }
        }

        contentItem: ColumnLayout {
            spacing: Tokens.spacing.md

            /* The glyph in its own colour on a tint of the same — the pattern the
               KPI cards already use, so a colour means the same thing on both
               halves of this screen. The primary card inverts it. */
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Tokens.icon.xl + 2 * Tokens.spacing.md
                implicitHeight: implicitWidth
                radius: Tokens.radius.lg
                color: card.primary ? Tokens.brand : Tokens.toneFill(card.tone)

                Icon {
                    anchors.centerIn: parent
                    icon: card.entry.icon !== undefined ? card.entry.icon : ""
                    size: Tokens.icon.xl
                    color: card.primary ? Tokens.onBrand : Tokens.toneInk(card.tone)
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: card.text
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.bodyLarge
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        onClicked: root.go(entry)
    }


    Component.onCompleted: {
        root.refresh()
        /* The drawer card needs to know which of its two states it is in, and this
           screen is often the first one opened in the morning. */
        if (drawer)
            drawer.load()
    }

    /*
     * Re-read on arrival, which is what the Refresh button in the header used to be
     * for.
     *
     * Nothing invalidates this screen: its six figures come from six separate report
     * functions over four different tables, so there is no one signal to listen to —
     * a sale, a purchase, an expense and a stock edit all move it, from four other
     * pages. Coming back to it is exactly the moment its numbers are stale, and it is
     * also the only moment anybody looks.
     */
    onVisibleChanged: {
        if (!visible)
            return
        root.refresh()
        if (drawer)
            drawer.load()
    }

    Connections {
        target: root.ctrl
        ignoreUnknownSignals: true
        function onRejected(message) { toast.show(message, Severity.caution) }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.size.pagePadding
        spacing: Tokens.spacing.lg

        PageHeader {
            Layout.fillWidth: true
            title: Strings.t("nav.dashboard", "Dashboard")
            description: Strings.t("dashboard.description",
                                   "The shop, at a glance.")

            /* The period, then Refresh. In the header rather than in a bar of its
               own because this screen has no other filter — one control does not
               need a container, and the KPI band is what should be directly under
               the title. */
            actionItems: [
                QC.ComboBox {
                    /* A Row sets only x, so a vertical anchor inside one is safe —
                       and needed, because the combo and the button do not have the
                       same natural height and the taller one defines the row. */
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 210
                    model: root.periods
                    textRole: "label"
                    currentIndex: root.periodIndex
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.body
                    /* Safe to bind currentIndex here, unlike on the Reports screen:
                       this combo is the only thing that ever writes periodIndex, so
                       the binding it destroys on activation was already agreeing
                       with it. */
                    onActivated: (index) => {
                        root.periodIndex = index
                        root.refresh()
                    }
                }
            ]
        }

        /* The body scrolls: six figures and a card for every screen do not fit a
           760px window, and the header stays put so the period selector is always
           where it was. */
        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            QC.ScrollBar.vertical: FluentScrollBar { policy: QC.ScrollBar.AsNeeded }

        ColumnLayout {
            id: body
            width: scroller.width
            spacing: Tokens.spacing.lg

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("dashboard.period_sales", "Sales")
                value: root.value("sales_total")
                valueTooltip: root.value("sales_total_full")
                subtext: Strings.tf("dashboard.sales_count", "{count} sales",
                                    { count: root.value("sales_count") })
                glyph: "ic_fluent_receipt_money_20_regular"
                tone: "primary"
            }

            KpiCard {
                label: Strings.t("dashboard.period_profit", "Net profit")
                value: root.value("profit")
                valueTooltip: root.value("profit_full")
                glyph: "ic_fluent_data_trending_20_regular"
                tone: "success"
                /* Selling at a loss for a day is possible and worth seeing. */
                valueTone: root.number("profit_raw") < 0 ? "danger" : ""
            }

            KpiCard {
                label: Strings.t("dashboard.period_expenses", "Expenses")
                value: root.value("expenses")
                valueTooltip: root.value("expenses_full")
                glyph: "ic_fluent_money_hand_20_regular"
                tone: "warning"
            }
        }

        CardRow {
            Layout.fillWidth: true

            KpiCard {
                label: Strings.t("reports.inv.value", "Stock value")
                value: root.value("inventory_value")
                valueTooltip: root.value("inventory_value_full")
                subtext: Strings.tf("dashboard.low_stock_count", "{count} low on stock",
                                    { count: root.value("low_stock") })
                subtextTone: root.number("low_stock_raw") > 0 ? "warning" : ""
                glyph: "ic_fluent_box_multiple_20_regular"
                tone: "info"
            }

            KpiCard {
                label: Strings.t("dashboard.customer_debts", "Owed to the shop")
                value: root.value("customer_debt")
                valueTooltip: root.value("customer_debt_full")
                glyph: "ic_fluent_people_team_20_regular"
                tone: "danger"
                valueTone: root.number("customer_debt_raw") > 0 ? "danger" : ""
            }

            KpiCard {
                label: Strings.t("dashboard.supplier_due", "Owed to suppliers")
                value: root.value("supplier_debt")
                valueTooltip: root.value("supplier_debt_full")
                glyph: "ic_fluent_vehicle_truck_profile_20_regular"
                tone: "warning"
                valueTone: root.number("supplier_debt_raw") > 0 ? "warning" : ""
            }
        }

        /*
         * The week behind today's six figures.
         *
         * WHY HERE
         *
         * Under the KPIs and over the quick actions, which is the order pos's own
         * dashboard used (pos/app/pages/dashboard.py:152-270) and the order the
         * screen already implies: the figures say what happened, the charts say
         * whether that is normal, and the actions are what you do about it. Putting
         * a chart above the KPIs would push the six numbers an owner opens this
         * screen for below the fold.
         *
         * WHY THREE, AND WHY THESE THREE
         *
         * Each one answers a question the KPI cards cannot:
         *   the curve      is today normal, or is the week going somewhere?
         *   the donut      how much of that money is actually in the drawer?
         *                  (this product sells on account — Destinations has a
         *                   whole debtor shortcut — so the split matters daily)
         *   the ranking    what is moving, and therefore what to reorder?
         *
         * pos charted two more here, inventory alerts and largest debts. Both are
         * already on this screen in a cheaper form: the stock KPI carries its own
         * "N low on stock" subtext, and the debtor list is one of the seven quick
         * action cards. A chart that repeats a card is a longer page, not a
         * better one.
         *
         * WHY THE SIZES
         *
         * 2 : 3, the ratio pos used for the same pair (reports.py's `ratio=(2,3)`).
         * A donut is a fixed circle and gets no better with width; a curve does
         * nothing else. Wrapping to one column under 940 rather than at a device
         * breakpoint, because 940 is where 2/5ths of the row stops holding a legend
         * beside a readable ring — DonutChart drops its legend under the ring on
         * its own below 460, and this keeps that from happening at 1366.
         *
         * The ranking is full width and stands alone. Horizontal bars are a list:
         * they want the width for their names, and pairing them with anything would
         * cost the labels that make them readable.
         */
        GridLayout {
            id: chartRow

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.sm
            visible: root.mix.length > 0 || root.trend.length > 1

            columns: body.width > 940 ? 2 : 1
            columnSpacing: Tokens.spacing.lg
            rowSpacing: Tokens.spacing.lg

            ChartCard {
                Layout.fillWidth: true
                Layout.horizontalStretchFactor: 2
                visible: root.mix.length > 0

                title: Strings.t("reports.sales.payment_mix", "Payment methods")
                subtitle: "\u200e" + root.chartRange
                /* Emerald: this card is about money arriving. The slices carry
                   their own tones from the controller — cash / partial / debt are
                   success / info / warning, the same three colours the rest of the
                   product gives those three ideas — so the palette is never
                   consulted and a slice cannot change colour when it changes rank. */
                ink: Tokens.hue.emerald
                contentHeight: 260

                DonutChart {
                    anchors.fill: parent
                    slices: root.mix
                    centerValue: root.mixTotal
                    centerLabel: Strings.t("reports.sales.total", "Total sales")
                }
            }

            ChartCard {
                Layout.fillWidth: true
                Layout.horizontalStretchFactor: 3
                visible: root.trend.length > 1

                title: Strings.t("reports.sales.trend", "Sales trend")
                subtitle: "\u200e" + root.chartRange
                ink: Tokens.hue.indigo
                contentHeight: 260

                LineChart {
                    anchors.fill: parent
                    points: root.trend
                    ink: Tokens.hue.indigo
                }
            }
        }

        ChartCard {
            Layout.fillWidth: true
            visible: root.ranking.length > 0

            title: Strings.t("reports.sales.top_revenue", "Top products by revenue")
            subtitle: "\u200e" + root.chartRange
            /* Teal is the products hue in Tokens.moduleHue, so this ranking is the
               same colour as the Products screen it sends you to. */
            ink: Tokens.hue.teal
            /* Sized to its rows, not to a round number: dashboard_stats returns at
               most five products, and a card with room for eight would sit on two
               inches of empty tint. 46 is one row — a caption line, the 6px gap and
               a 14px bar — plus BarsH's own inter-row spacing. */
            contentHeight: Math.max(1, root.ranking.length) * 46 + Tokens.spacing.xs

            BarsH {
                anchors.fill: parent
                rows: root.ranking
                ink: Tokens.hue.teal
                showRank: true
                emphasiseFirst: true
            }
        }

        /* Where to start work: the till, the five things a shop creates, and the
           debtor list. A Flow rather than a grid with computed cells — the cards are
           a fixed size and the row simply wraps, which is what makes it right on a
           1366px till and on a 2560px monitor without arithmetic. */
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.sm
            text: Strings.t("dashboard.quick_actions", "Quick actions")
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
            color: Fluent.textTertiary
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.md

            Repeater {
                model: root.shortcuts

                delegate: Shortcut {
                    required property var modelData

                    entry: modelData
                    text: modelData.label
                    tone: modelData.tone
                    primary: modelData.primary === true
                }
            }
        }

        Item { Layout.fillWidth: true; implicitHeight: Tokens.spacing.lg }
        }
        }
    }

    LoadingOverlay {
        visible: root.busy && !root.cards
    }

    ToastHost {
        id: toast
        bottomMargin: Tokens.size.pagePadding
    }
}
